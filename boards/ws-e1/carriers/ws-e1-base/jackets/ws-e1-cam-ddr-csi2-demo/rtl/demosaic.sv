//============================================================================
// demosaic.sv - Bayer RAW10 -> RGB10 去马赛克（AXI4-Stream，重构自
// raw10_color.v 的 S0..S3a 段；WB 与 BT.601 拆出为独立模块）
//
// 数据流（全链）:
//   raw_2_axi4st (RAW10 窗口流) -> [demosaic 本模块] -> wb_axis -> rgb2yuv_axis
//
// AXI4-Stream 约定（与 raw_2_axi4st 一致）:
//   输入  tdata[39:0]  4xRAW10 打包（px0 在 LSB，行内从左到右）
//         tlast = EOL（行末拍）; tuser = {eof, sol, sof}
//   输出  tdata[119:0] 每拍 4 像素 x {R,G,B} 各 10-bit，
//         px p 占 [30*p +: 30] = {R,G,B}（R 在高位）
//         tlast/tuser 同上；无 tready —— 源不可暂停，1:1 拍映射，
//         下游以 always-ready 消费
//
// 结构（沿用板上验证过的 raw10_color 内核，逐拍语义不变）:
//   - 四组轮转行缓存（mod 4）：写 line L 时读 mid=L-1、up=L-2，
//     写口与两个读口永远不同 BRAM；读口全同步（Titanium BRAM 无异步
//     读口，异步读会被 EFX-0657 落到 LUTRAM），每行数据存双副本各带
//     1 个同步读口：副本 1 读地址 gcnt（下一拍得组 j-1，窗中心/左邻
//     链）、副本 2 读地址 gcnt+1（下一拍得组 j，窗右邻活值）；行选
//     多路在寄存器之后（不阻碍 BRAM 推断），与旧异步读版逐拍等价
//   - S2 窗口锁存：4 px x 9 采样，边缘钳位三类：
//     水平行首/行尾缺邻 -> 钳到镜像列 px1/px2（与真邻同列奇偶、同
//     Bayer 站类；旧版钳自身中心，站类相反 -> 行尾 1 列异色：相机
//     紫列/竖条异常色）；
//     垂直帧顶/帧底缺行 -> up/down := mid（顶行主拍+flush 窗、残行
//     主拍+flush 窗全覆盖；旧版只钳 early 主拍，残行下行吃到下一帧
//     行 0 -> 底行活动画面鬼影）。
//   - 行尾 flush：行末拍后借一个空闲拍补锁 GW-1 组的窗口（要求
//     行间至少 1 个空闲拍 —— raw_2_axi4st 的行消隐保证）；行首填充
//     窗由 kp 链杀掉。每行输出恰好 GW 组。flush 拍行选下标回退一
//     档（route 已在行末拍末沿自增，见行选处注释 —— 行尾组 up/mid
//     行错位 = 相机右缘紫列/竖条行尾异色的根因）。
//   - Bayer 相位 (CSR): 0=RGGB 1=GRBG 2=GBRG 3=BGGR，(行[0],px[0])
//     选象限；adaptive (CSR): R/B 站点 G 方向选择（dH/dV），
//     相等回落四邻均值（与 bilinear 逐位一致）
//
// 输出成帧（残行显式标记，垂直偏移修复）:
//   窗口中心行是 mid = 输入行-1 —— demosaic 的因果性决定内容天然
//   滞后输入一行：帧末行（center=LINES-1）只能在下一输入帧行 0 期间
//   流出（"残行"）。旧的输出侧自由计数帧界（eof = oline==LINES-1）
//   与内容行无锚：一旦某帧行 span 的发射拍数偏离（无缝流放弃 flush、
//   热接入首行相位），帧界即整体旋转一行 —— 板级表现为切换后随机
//   0/1 行垂直偏移、落定后不动（shape 消隐排水相位决定吞掉的是残行
//   还是内容行）。现改为随数据流水显式标记残行：
//     res_win：主拍 k_cnt==0、flush 拍 k_cnt==1 的窗即上一帧末行，
//       标记打 4 拍（rf1..rf4）与输出拍对齐；
//     eof 钉在残行行末（ocnt==GW-1 && rf4），oline 回 0 落在内容行 0
//       —— 每个输出帧恒为真 [0..LINES-1]，切换后首帧即对齐，与
//       排水相位无关。
//   上电首帧行 0 期间的 BRAM 垃圾窗口不发射（seen_frame 门控）。
//
// 参数约束: GW <= 512（组计数 9 bit）; LINES <= 2048（行计数 11 bit，
//   仅接口兼容 —— 帧长由输入流决定）; GW 必须等于上游窗口流的每行
//   拍数（H_ACTIVE/4）。
//============================================================================

module demosaic #(
    parameter int GW    = 480,      // 每行组数（= H_ACTIVE/4, <= 512）
    parameter int LINES = 1080      // 每帧行数（接口兼容，帧长由输入流决定；需为偶数）
) (
    input  logic        aclk,
    input  logic        aresetn,

    // RAW10 窗口流输入（AXI4-Stream 从口，无 tready）
    input  logic [39:0] s_axis_tdata,
    input  logic        s_axis_tvalid,
    input  logic        s_axis_tlast,   // EOL
    input  logic [2:0]  s_axis_tuser,   // {eof, sol, sof}

    // 处理参数（CSR 域，直接静态/慢变）
    input  logic [1:0]  bayer_phase,    // 0=RGGB 1=GRBG 2=GBRG 3=BGGR
    input  logic        adaptive,       // 1=R/B 站点自适应 G 方向

    // RGB10 输出（AXI4-Stream 主口，无 tready）
    output logic [119:0] m_axis_tdata,  // 4 px x {R,G,B} 10-bit, px0 在 LSB
    output logic         m_axis_tvalid,
    output logic         m_axis_tlast,  // EOL
    output logic [2:0]   m_axis_tuser   // {eof, sol, sof}
);

    //--------------------------------------------------------------------
    // 输入侧行计数：sof 清零、eol 递增。
    //   k_cnt==1 的行：窗中心是内容行 0（无真实上行 -> early，up:=mid）；
    //   k_cnt==0 的行：窗中心是上一帧末行（上行真实，非 early）—— 上游
    //   每帧恰好 LINES 行，帧末行的窗在本帧行 0 期间锁存并发射。
    //   meta 行奇偶由 ~k_cnt[0] 派生，跨帧末行（k_cnt==0）要求 LINES
    //   为偶数（1080 满足）。
    //--------------------------------------------------------------------
    logic [10:0] k_cnt;             // 输入行号（0 基, sof 清零）
    logic        seen_frame;        // 首帧输入完毕（此后行 0 的窗为真实内容）

    wire        in_sof  = s_axis_tvalid && s_axis_tuser[0];
    wire        in_eol  = s_axis_tvalid && s_axis_tlast;
    wire        in_line0 = k_cnt[0];

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            k_cnt      <= 11'd0;
            seen_frame <= 1'b0;
        end else if (in_sof) begin
            k_cnt <= 11'd0;
        end else if (in_eol) begin
            k_cnt      <= k_cnt + 11'd1;
            seen_frame <= seen_frame || s_axis_tuser[2];    // 首帧输入 eof
        end
    end

    //--------------------------------------------------------------------
    // S0/S1: 四组轮转行缓存（block RAM 推断，写口 + 2 个同步读口）
    //   route 每"行"推进一次；写 route(L) 行时读 mid=route-1、
    //   up=route-2（mod 4），读写永不撞同一 BRAM。
    //   Titanium BRAM 读口必须同步（EFX-0657），且每阵列至多 1 写 + 1
    //   同步读口 -> 每行数据存双副本：
    //     主副本   读地址 gcnt    -> 下一拍得组 j-1（窗中心/左邻链）
    //     n 副本   读地址 gcnt_n  -> 下一拍得组 j  （窗右邻"活值"）
    //   行选多路放在读寄存器之后、选择用当拍 route（与旧异步读版同拍
    //   同选择）—— 逐拍等价；唯一差异在行首填充窗（V0 拍）的 mid/up
    //   行选落到新 route 的 BRAM，该窗被 kp 链杀掉不发射，等效。
    //--------------------------------------------------------------------
    (* ram_style = "block" *) logic [39:0] line_a  [0:GW-1];
    (* ram_style = "block" *) logic [39:0] line_b  [0:GW-1];
    (* ram_style = "block" *) logic [39:0] line_c  [0:GW-1];
    (* ram_style = "block" *) logic [39:0] line_d  [0:GW-1];
    (* ram_style = "block" *) logic [39:0] line_an [0:GW-1];
    (* ram_style = "block" *) logic [39:0] line_bn [0:GW-1];
    (* ram_style = "block" *) logic [39:0] line_cn [0:GW-1];
    (* ram_style = "block" *) logic [39:0] line_dn [0:GW-1];

    logic [8:0]  gcnt;              // 行内组下标 0..GW-1
    logic [1:0]  route;             // 写 BRAM 选择，每行 +1（mod 4）
    logic [39:0] down_r;            // 当前行（down），组 j
    logic [39:0] down_d;            // 当前行，组 j-1
    logic [39:0] midq_d;            // mid 行，组 j-2
    logic [39:0] upq_d;             // up 行，组 j-2

    wire [8:0] gcnt_n = (gcnt == GW[8:0] - 9'd1) ? 9'd0 : gcnt + 9'd1;

    // 两个同步读口（副本各 1 个，read-before-write 无碰撞：读写不同 BRAM）
    logic [39:0] q_a, q_b, q_c, q_d;        // 组 j-1
    logic [39:0] qn_a, qn_b, qn_c, qn_d;    // 组 j（活值）
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            {q_a, q_b, q_c, q_d}     <= 160'd0;
            {qn_a, qn_b, qn_c, qn_d} <= 160'd0;
        end else if (s_axis_tvalid) begin
            q_a  <= line_a[gcnt];    q_b  <= line_b[gcnt];
            q_c  <= line_c[gcnt];    q_d  <= line_d[gcnt];
            qn_a <= line_an[gcnt_n]; qn_b <= line_bn[gcnt_n];
            qn_c <= line_cn[gcnt_n]; qn_d <= line_dn[gcnt_n];
        end
    end

    // 写口（双副本同地址同数据）
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            gcnt  <= 9'd0;
            route <= 2'd0;
        end else if (s_axis_tvalid) begin
            case (route)
                2'd0: begin line_a[gcnt] <= s_axis_tdata; line_an[gcnt] <= s_axis_tdata; end
                2'd1: begin line_b[gcnt] <= s_axis_tdata; line_bn[gcnt] <= s_axis_tdata; end
                2'd2: begin line_c[gcnt] <= s_axis_tdata; line_cn[gcnt] <= s_axis_tdata; end
                default: begin line_d[gcnt] <= s_axis_tdata; line_dn[gcnt] <= s_axis_tdata; end
            endcase
            // route 每行推进一次（一行必须存在同一块 BRAM 里）
            if (gcnt == GW[8:0] - 9'd1)
                route <= route + 2'd1;          // mod 4
            if (gcnt == GW[8:0] - 9'd1)
                gcnt <= 9'd0;
            else
                gcnt <= gcnt + 9'd1;
        end
    end

    //--------------------------------------------------------------------
    // 行尾 flush 请求（行选 flush 拍偏移依赖 flush_cycle，声明前移）
    //   窗口流水滞后输入 1 组：组 j 的拍锁存的是以组 j-1 为中心的窗。
    //   行首拍锁存的窗来自上一行尾寄存器（填充，输出被 kp 链杀掉）；
    //   GW-1 组借行间空闲拍补锁一个窗（右邻钳位到镜像列 px2，站类
    //   与真右邻一致）。
    //--------------------------------------------------------------------
    logic flush_pend;
    wire  flush_cycle = flush_pend && !s_axis_tvalid;

    // 行选（读寄存器之后的多路；消隐/flush 拍 q_* 保持、flush 拍
    // route 已自增 —— 见下）：
    //   主拍：route = 当前行槽，mid = route-1、up = route-2 行；
    //   flush 拍（行末空闲拍）：route 已在行末拍末沿 +1，q_* 恰为各
    //   槽 g479 新词，但若仍用 route-1/route-2，mid 选中刚写过的槽
    //   （同步读 read-before-write = 4 行前旧数据）、up 选中真中心
    //   行，行尾窗 up/mid 整体行错位（down 走 s_axis 延迟寄存器不
    //   受影响）—— 相机右缘紫列/竖条行尾异色的根因。flush 拍下标
    //   回退一档：mid 取 route-2、up 取 route-3。
    logic [1:0] sel_m, sel_u;
    always_comb begin
        sel_m = flush_cycle ? (route - 2'd2) : (route - 2'd1);
        sel_u = flush_cycle ? (route - 2'd3) : (route - 2'd2);
    end
    logic [39:0] mid_row,  up_row;      // mid/up 行，g479 窗中心/上行
    logic [39:0] mid_rown, up_rown;     // mid/up 行，右邻"活值"
    always_comb begin
        case (sel_m)                    // sel 直接索引 q 槽（a=0,b=1,c=2,d=3）
            2'd0: begin mid_row = q_a;  mid_rown = qn_a; end
            2'd1: begin mid_row = q_b;  mid_rown = qn_b; end
            2'd2: begin mid_row = q_c;  mid_rown = qn_c; end
            default: begin mid_row = q_d; mid_rown = qn_d; end
        endcase
        case (sel_u)                    // 同上
            2'd0: begin up_row = q_a;  up_rown = qn_a; end
            2'd1: begin up_row = q_b;  up_rown = qn_b; end
            2'd2: begin up_row = q_c;  up_rown = qn_c; end
            default: begin up_row = q_d; up_rown = qn_d; end
        endcase
    end
    // 注：flush 拍 mid_rown/up_rown 为 gcnt_n 回绕的地址 0 旧词，仅
    // 被 px3 右邻引用且随后被镜像列钳位覆写，无功能影响。

    // 延迟一拍寄存（down 行 j-1 / mid-up 行 j-2，flush 与行首钳位使用）
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            down_r <= 40'd0;
            down_d <= 40'd0;
            midq_d <= 40'd0;
            upq_d  <= 40'd0;
        end else if (s_axis_tvalid) begin
            down_r <= s_axis_tdata;             // down 行，组 j
            down_d <= down_r;                   // down 行，组 j-1
            midq_d <= mid_row;                  // mid 行，组 j-2
            upq_d  <= up_row;                   // up 行，组 j-2
        end
    end

    //--------------------------------------------------------------------
    // 行尾 flush 消费 + 内容标记
    //--------------------------------------------------------------------
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn)
            flush_pend <= 1'b0;
        else if (s_axis_tvalid) begin
            if (gcnt == GW[8:0] - 9'd1)
                flush_pend <= 1'b1;
            else if (gcnt == 9'd0)
                flush_pend <= 1'b0;     // 无缝流：flush 放弃（不推荐）
        end else if (flush_pend)
            flush_pend <= 1'b0;         // 本空闲拍消费
    end

    wire first_win = s_axis_tvalid && (gcnt == 9'd0);
    logic kp1, kp2, kp3;
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn)
            {kp1, kp2, kp3} <= 3'b0;
        else begin
            kp1 <= first_win;
            kp2 <= kp1;
            kp3 <= kp2;
        end
    end

    // 内容标记：只有上电首帧（seen_frame=0 期间）行 0 锁存的窗是
    // BRAM 垃圾，不得发射；稳态下行 0 的窗中心是上一帧末行（真实
    // 内容，必须发射 —— 帧末行跨帧流出的既定行为）。flush 拍在 eol
    // 之后，k_cnt 已自增（窗中心是"本行-1"），判据用 k_cnt >= 2。
    // 标记随数据同深度过流水，与 rgb_v2 对齐后置 out_started（只置
    // 不清）。
    logic  sc0, sc1, sc2, sc3;
    logic  out_started;
    wire   win_latch = s_axis_tvalid || flush_cycle;
    assign sc0 = win_latch && ((flush_cycle ? (k_cnt >= 11'd2)
                                            : (k_cnt != 11'd0))
                               || seen_frame);
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            {sc1, sc2, sc3} <= 3'b0;
            out_started     <= 1'b0;
        end else begin
            sc1 <= sc0;
            sc2 <= sc1;
            sc3 <= sc2;
            out_started <= out_started || sc3;
        end
    end

    //--------------------------------------------------------------------
    // 帧界标记（垂直偏移修复）：残行 = 上一帧末行，随数据流水显式
    // 标记。主拍 k_cnt==0 的窗（mid = 上一帧末行）与 flush 拍 k_cnt==1
    // 的补锁窗（该行 group GW-1）都是残行；标记打 4 拍（rf1..rf4）
    // 与输出拍对齐（win_latch -> win3_v -> rgb_v -> rgb_v2 -> 输出，
    // 填充窗恰被 kp3 在输出拍杀掉）。首帧 seen_frame=0 期间不标记。
    //--------------------------------------------------------------------
    wire res_win = win_latch && seen_frame
                   && (s_axis_tvalid ? (k_cnt == 11'd0)
                                     : (flush_cycle && (k_cnt == 11'd1)));
    logic rf1, rf2, rf3, rf4;
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn)
            {rf1, rf2, rf3, rf4} <= 4'b0;
        else begin
            rf1 <= res_win;
            rf2 <= rf1;
            rf3 <= rf2;
            rf4 <= rf3;
        end
    end

    //--------------------------------------------------------------------
    // 垂直边缘钳位源（边缘行幽灵修复）：
    //   top（mid = 内容行 0 的窗：主拍 k_cnt==1、行 1 的 flush 拍
    //     k_cnt==2）没有真实上行 —— mod-4 槽绕回，up 槽是上一帧
    //     1079 行的残留 -> up := mid（旧版只钳 early 主拍，flush 窗
    //     漏钳）；
    //   bottom（残行窗 res_win）没有真实下行 —— down 槽/活值是下一
    //     帧行 0 正在写入的数据 -> down := mid（旧版完全不钳，底行
    //     活动画面鬼影，静态图案不可见）。
    //   钳位在窗口锁存源处统一收口（主拍/flush 窗/行首左钳全盖），
    //   替代旧 in_early 二次覆写块（语义相同：直接引用当前窗的 mid
    //   数据源，规避 NBA 读到上一窗 mid）。
    //--------------------------------------------------------------------
    wire        top_v = win_latch && (s_axis_tvalid
                                      ? (k_cnt == 11'd1)
                                      : (flush_cycle && (k_cnt == 11'd2)));
    wire [39:0] up_eff  = top_v ? mid_row  : up_row;
    wire [39:0] upq_eff = top_v ? midq_d   : upq_d;
    wire [39:0] upn_eff = top_v ? mid_rown : up_rown;
    wire [39:0] dn_eff  = res_win ? mid_row  : down_r;
    wire [39:0] dnd_eff = res_win ? midq_d   : down_d;
    wire [39:0] dnn_eff = res_win ? mid_rown : s_axis_tdata;

    //--------------------------------------------------------------------
    // S2: 窗口锁存 - 4 px x 9 采样，边缘钳位
    //--------------------------------------------------------------------
    // w[px][row 0=up 1=mid 2=down][col 0=left 1=center 2=right]
    logic [9:0] w [4][3][3];

    logic [1:0] meta_s;             // mid 行奇偶，延迟到 S3
    logic       win3_v;

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            meta_s  <= 2'd0;
            win3_v  <= 1'b0;
            for (int p = 0; p < 4; p = p + 1) begin
                w[p][0][0] <= 10'd0; w[p][0][1] <= 10'd0; w[p][0][2] <= 10'd0;
                w[p][1][0] <= 10'd0; w[p][1][1] <= 10'd0; w[p][1][2] <= 10'd0;
                w[p][2][0] <= 10'd0; w[p][2][1] <= 10'd0; w[p][2][2] <= 10'd0;
            end
        end else if (win_latch) begin
            // 真实拍：写组 j+1、读 mid/up 行的组 j+1；行选
            // （mid_row/up_row 及 n 活值变体）持有组 j 与 j-1 —— 即
            // 正在锁存的窗。flush 拍从同一批寄存器补锁行末窗，
            // meta 不得重载。
            if (s_axis_tvalid) begin
                meta_s  <= ~in_line0;   // 下一窗的 mid 行奇偶
            end
            win3_v  <= 1'b1;
            for (int p = 0; p < 4; p = p + 1) begin
                w[p][0][0] <= (p == 0) ? upq_eff[39:30]
                                       : up_eff[10*(p-1) +: 10];
                w[p][0][1] <= up_eff[10*p +: 10];
                w[p][0][2] <= (p == 3) ? upn_eff[9:0]  : up_eff[10*(p+1) +: 10];
                w[p][1][0] <= (p == 0) ? midq_d[39:30]
                                       : mid_row[10*(p-1) +: 10];
                w[p][1][1] <= mid_row[10*p +: 10];
                w[p][1][2] <= (p == 3) ? mid_rown[9:0]
                                       : mid_row[10*(p+1) +: 10]; // j+1, 活值
                w[p][2][0] <= (p == 0) ? dnd_eff[39:30]
                                       : dn_eff[10*(p-1) +: 10];
                w[p][2][1] <= dn_eff[10*p +: 10];
                w[p][2][2] <= (p == 3) ? dnn_eff[9:0]
                                       : dn_eff[10*(p+1) +: 10]; // j+1, 活值
            end
            // 水平钳位（镜像列，站类正确）：
            //   行首窗（组 0）：px0 缺左邻 -> 钳到 px1（col+1 与真左邻
            //   col-1 同列奇偶、同站类；旧版钳自身中心站类相反）。
            //   行尾 flush 窗（组 GW-1）：px3 缺右邻 -> 钳到 px2（同理；
            //   旧版钳自身中心 -> 末列混站插值 = 行尾 1 列异色）。
            if (flush_cycle) begin
                w[3][0][2] <= up_eff[29:20];
                w[3][1][2] <= mid_row[29:20];
                w[3][2][2] <= dn_eff[29:20];
            end else begin
                if (gcnt == 9'd1) begin
                    w[0][0][0] <= up_eff[19:10];
                    w[0][1][0] <= mid_row[19:10];
                    w[0][2][0] <= dn_eff[19:10];
                end
            end
        end else begin
            win3_v <= 1'b0;
        end
    end

    //--------------------------------------------------------------------
    // S3: 逐像素去马赛克（双线性 + 自适应 G）-> RGB10 寄存
    //--------------------------------------------------------------------
    // Bayer 位置颜色: 0=R 1=G 2=B
    // 相位表修正（板级 P=1/P=2 异色定位）：P=1 旧表把 (rp=1,cp=1) 的
    // G 站分成 B（无效 Bayer 表），P=2 旧表实为 GRBG —— 与标称名互换。
    // 现按标准表实现（rp = 窗中心内容行号奇偶，cp = 列奇偶）：
    //   P=1 GRBG: (0,0)G (0,1)R (1,0)B (1,1)G
    //   P=2 GBRG: (0,0)G (0,1)B (1,0)R (1,1)G
    // P=0 RGGB / P=3 BGGR 两表本就正确，不动（相机 RGGB 零影响）。
    function automatic [1:0] c_of;
        input [1:0] ph;
        input       rp, cp;
        case (ph)
            2'd0: c_of = (!rp && !cp) ? 2'd0 : (rp && cp) ? 2'd2 : 2'd1;   // RGGB
            2'd1: c_of = (!rp && cp)  ? 2'd0 : (rp && !cp) ? 2'd2 : 2'd1;  // GRBG
            2'd2: c_of = (!rp && cp)  ? 2'd2 : (rp && !cp) ? 2'd0 : 2'd1;  // GBRG
            default: c_of = (!rp && !cp) ? 2'd2 : (rp && cp) ? 2'd0 : 2'd1;// BGGR
        endcase
    endfunction

    logic [119:0] rgb_q;            // S3 输出寄存（4 px x 30 bit）
    logic [119:0] rgb_q2;           // 输出对齐寄存：tvalid 链（win3_v ->
                                    // rgb_v -> rgb_v2 -> m_axis_tvalid）
                                    // 比 rgb_q 深一级，数据补一级寄存
                                    // 使 tdata 与 tvalid 同拍对齐
    logic         rgb_v, rgb_v2;    // S3 有效链

    wire [1:0] ph = bayer_phase;

    genvar gv;
    generate
        for (gv = 0; gv < 4; gv = gv + 1) begin : g_px
            wire [1:0] rp = meta_s;             // mid 行奇偶
            wire [1:0] cp = gv[0];              // 组内像素奇偶
            wire [1:0] cC  = c_of(ph, rp, cp);
            wire [1:0] cL  = c_of(ph, rp, cp ^ 2'd1);
            wire [1:0] cU  = c_of(ph, rp ^ 2'd1, cp);
            wire [1:0] cUL = c_of(ph, rp ^ 2'd1, cp ^ 2'd1);
            // up 行右邻用其左邻近似（垂直-对角平均），颜色码同 cUL
            wire [1:0] cUR = cUL;

            wire [9:0] vC  = w[gv][1][1];
            wire [9:0] vL  = w[gv][1][0];
            wire [9:0] vR  = w[gv][1][2];
            wire [9:0] vU  = w[gv][0][1];
            wire [9:0] vD  = w[gv][2][1];
            wire [9:0] vUL = w[gv][0][0];
            wire [9:0] vUR = w[gv][0][2];
            wire [9:0] vDL = w[gv][2][0];
            wire [9:0] vDR = w[gv][2][2];

            wire [11:0] cross_sum =
                {2'd0, vU} + {2'd0, vD} + {2'd0, vL} + {2'd0, vR};
            wire [11:0] diag_sum =
                {2'd0, vUL} + {2'd0, vUR} + {2'd0, vDL} + {2'd0, vDR};
            wire [10:0] vert_pair = {1'd0, vU} + {1'd0, vD};
            wire [10:0] horz_pair = {1'd0, vL} + {1'd0, vR};

            wire       x_is_r = (cL == 2'd0);       // 水平对的颜色
            // G 站点: R 来自 R 对，B 来自 B 对
            wire [9:0] gsite_r = x_is_r ? horz_pair[10:1] : vert_pair[10:1];
            wire [9:0] gsite_b = x_is_r ? vert_pair[10:1] : horz_pair[10:1];

            // 自适应 G（仅 R/B 站点）：dH=|W-E|、dV=|N-S| 11 位全宽
            // 比较；dH<dV 选水平均值、dH>dV 选垂直均值、相等回落
            // 四邻均值（与 bilinear 逐位一致）
            wire [10:0] dh = (vL > vR) ? ({1'b0, vL} - {1'b0, vR})
                                       : ({1'b0, vR} - {1'b0, vL});
            wire [10:0] dv = (vU > vD) ? ({1'b0, vU} - {1'b0, vD})
                                       : ({1'b0, vD} - {1'b0, vU});
            wire [9:0]  gsel = (dh < dv) ? horz_pair[10:1]
                             : (dh > dv) ? vert_pair[10:1]
                             : cross_sum[11:2];

            // 插值估计（10-bit，保持精度给下游 WB）
            wire [9:0] r0 = (cC == 2'd0) ? vC :
                            (cC == 2'd2) ? diag_sum[11:2] : gsite_r;
            wire [9:0] g0 = (cC == 2'd1) ? vC :
                            (adaptive ? gsel : cross_sum[11:2]);
            wire [9:0] b0 = (cC == 2'd2) ? vC :
                            (cC == 2'd0) ? diag_sum[11:2] : gsite_b;

            always_ff @(posedge aclk or negedge aresetn) begin
                if (!aresetn)
                    rgb_q[30*gv +: 30] <= 30'd0;
                else if (win3_v)
                    rgb_q[30*gv +: 30] <= {r0, g0, b0};
            end
        end
    endgenerate

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            rgb_v  <= 1'b0;
            rgb_v2 <= 1'b0;
        end else begin
            rgb_v  <= win3_v;
            rgb_v2 <= rgb_v;
        end
    end

    //--------------------------------------------------------------------
    // AXIS 输出 + 输出侧成帧计数
    //   输出拍 = rgb_q 延迟一拍呈现（与 rgb_v2/kp3 对齐，同 raw10_color
    //   的 wb_v2/kp3 对齐方式）；sol/tlast 由 ocnt 生成，eof/sof 由残行
    //   标记 rf4 锚定到内容行（见头部"输出成帧"）。
    //--------------------------------------------------------------------
    logic [8:0]  ocnt;              // 输出行内组下标 0..GW-1
    logic [10:0] oline;             // 输出行号 0..LINES-1（残行末尾回 0）

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            m_axis_tdata  <= 120'd0;
            m_axis_tvalid <= 1'b0;
            ocnt          <= 9'd0;
            oline         <= 11'd0;
        end else begin
            m_axis_tvalid <= rgb_v2 && !kp3 && out_started;
            m_axis_tdata  <= rgb_q2;
            rgb_q2        <= rgb_q;
            if (m_axis_tvalid) begin
                if (ocnt == GW[8:0] - 9'd1) begin
                    ocnt  <= 9'd0;
                    oline <= rf4 ? 11'd0 : (oline + 11'd1);
                end else begin
                    ocnt <= ocnt + 9'd1;
                end
            end
        end
    end

    always_comb begin
        m_axis_tlast = m_axis_tvalid && (ocnt == GW[8:0] - 9'd1);
        m_axis_tuser = {m_axis_tvalid && (ocnt == GW[8:0] - 9'd1)
                             && rf4,                                 // eof（残行行末）
                        m_axis_tvalid && (ocnt == 9'd0),             // sol
                        m_axis_tvalid && (ocnt == 9'd0)
                             && (oline == 11'd0)};                   // sof（内容行 0）
    end

endmodule
