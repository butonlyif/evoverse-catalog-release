`timescale 1ns/1ps
//==============================================================================
// i2c_slave_bfm -- 开漏 I2C 从机行为模型（仅仿真，供多 TB 复用）
//
// - 7bit 地址 0x1A（0x34 写 / 0x35 读）
// - 写方向：3 数据字节 = {regH, regL, val}，cap_we 单拍脉冲上报
// - 读方向：以 rd_data（按 cur_reg 组合给出的值）逐字节发送，master ACK 续发
// - nack_addr：地址字节强制 NACK（缺件测试）
// - stretch_n：每个 scl_fall 起拉伸 SCL N 个 clk（须 < master 看门狗窗口）
// - stuck_scl：持续拉低 SCL（看门狗触发测试）
// - cap_list：捕获队列，每次写捕获 push_back {addr[15:0], data[7:0]}，
//   TB 层次化读取/清空（u_slv.cap_list.delete()）做 golden 全序列比对
// - n_stop：STOP 计数（事务边界核对），TB 层次化读取/清零
// - 采样约定：数据位在 scl_rise 采样；master ACK 在第 9 个 scl_rise 采样
//   （此时 master 仍驱动 ACK 位，避开其随后释放 SDA 的同沿竞态）
//==============================================================================
module i2c_slave_bfm (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        scl,          // 总线（1=释放）
    input  logic        sda,
    output logic        sda_pull,     // 1=拉低 SDA
    output logic        scl_pull,     // 1=拉低 SCL
    input  logic        nack_addr,
    input  logic [31:0] stretch_n,
    input  logic        stuck_scl,
    output logic [15:0] cap_reg,
    output logic [7:0]  cap_val,
    output logic        cap_we,
    output logic        cap_stop,
    input  logic [7:0]  rd_data,
    output logic [15:0] cur_reg
);

    typedef struct packed {
        logic [15:0] addr;           // 16-bit 寄存器地址
        logic [7:0]  data;           // 写入值
    } cap_entry_t;

    cap_entry_t  cap_list[$];        // 捕获序列（供 golden 全序列比对）
    int unsigned n_stop = 0;         // STOP 计数

    typedef enum logic [1:0] {S_IDLE, S_ADDR, S_WDATA, S_RDATA} state_e;

    state_e      st;
    logic        scl_q, sda_q;
    logic [3:0]  bitcnt;       // 0..7 数据位，8 = ACK 相
    logic [7:0]  shift;
    logic        ack_drove;
    logic [7:0]  byte0, byte1;
    logic [1:0]  dcnt;
    logic [7:0]  tx_shift;
    logic [31:0] stretch_cnt;

    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            scl_q <= 1'b1;
            sda_q <= 1'b1;
        end else begin
            scl_q <= scl;
            sda_q <= sda;
        end

    wire scl_rise  =  scl & ~scl_q;
    wire scl_fall  = ~scl &  scl_q;
    wire start_det = ~sda &  sda_q &  scl &  scl_q;   // SDA 高电平期下降
    wire stop_det  =  sda & ~sda_q &  scl;            // SDA 高电平期上升（含与
                                                      // SCL 同沿释放的 STOP）

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_IDLE; bitcnt <= 0; shift <= 0; ack_drove <= 0;
            byte0 <= 0; byte1 <= 0; dcnt <= 0; tx_shift <= 0;
            sda_pull <= 0; scl_pull <= 0; stretch_cnt <= 0;
            cap_reg <= 0; cap_val <= 0; cap_we <= 0; cap_stop <= 0;
            n_stop <= 0;
        end else begin
            cap_we   <= 1'b0;
            cap_stop <= 1'b0;

            // ---- SCL 拉伸 / 卡死 ----
            if (stretch_cnt != 0)      stretch_cnt <= stretch_cnt - 1'b1;
            else if (scl_fall && stretch_n != 0) stretch_cnt <= stretch_n;
            scl_pull <= stuck_scl | (stretch_cnt != 0);

            // ---- 协议 FSM ----
            if (stop_det) begin
                st       <= S_IDLE;
                sda_pull <= 1'b0;
                cap_stop <= 1'b1;
                n_stop   <= n_stop + 1'b1;
`ifdef DBG
                $display("[DBG-SLV] %m t=%0t STOP", $time);
`endif
            end else if (start_det) begin
                st        <= S_ADDR;
                bitcnt    <= 0;
                ack_drove <= 1'b0;
                sda_pull  <= 1'b0;
                dcnt      <= 0;
`ifdef DBG
                $display("[DBG-SLV] %m t=%0t START", $time);
`endif
            end else begin
                case (st)
                    S_IDLE: ;
                    // ---------------- 地址字节 ----------------
                    S_ADDR: begin
                        if (scl_rise && bitcnt < 8) begin
                            shift  <= {shift[6:0], sda};
                            bitcnt <= bitcnt + 1'b1;
`ifdef DBG
                            $display("[DBG-SLV] %m t=%0t bit%0d sda=%b",
                                     $time, bitcnt, sda);
`endif
                        end else if (scl_fall && bitcnt == 8 && !ack_drove) begin
                            // 第 9 拍低电平期驱动 ACK/NACK（sda_pull=1 拉低=ACK）
                            sda_pull  <= (shift[7:1] == 7'h1A) & ~nack_addr;
                            ack_drove <= 1'b1;
`ifdef DBG
                            $display("[DBG-SLV] t=%0t ADDR=%02x ackpull=%b",
                                     $time, shift,
                                     (shift[7:1] == 7'h1A) & ~nack_addr);
`endif
                        end else if (scl_fall && bitcnt == 8 && ack_drove) begin
                            sda_pull  <= 1'b0;
                            ack_drove <= 1'b0;
                            bitcnt    <= 0;
`ifdef DBG
                            $display("[DBG-SLV] t=%0t ADDR=%02x dispatch",
                                     $time, shift);
`endif
                            if (!nack_addr && shift[7:1] == 7'h1A) begin
                                dcnt <= 0;
                                if (shift[0]) begin          // 读
                                    st       <= S_RDATA;
                                    tx_shift <= {rd_data[6:0], 1'b0};
                                    sda_pull <= ~rd_data[7]; // MSB 先行
                                end else begin
                                    st <= S_WDATA;
                                end
                            end else begin
                                st <= S_IDLE;            // NACK：等 STOP
                            end
                        end
                    end
                    // ---------------- 写数据字节 ----------------
                    S_WDATA: begin
                        if (scl_rise && bitcnt < 8) begin
                            shift  <= {shift[6:0], sda};
                            bitcnt <= bitcnt + 1'b1;
                        end else if (scl_fall && bitcnt == 8 && !ack_drove) begin
                            sda_pull  <= 1'b1;           // 数据恒 ACK（拉低）
                            ack_drove <= 1'b1;
                        end else if (scl_fall && bitcnt == 8 && ack_drove) begin
                            sda_pull  <= 1'b0;
                            ack_drove <= 1'b0;
                            bitcnt    <= 0;
                            case (dcnt)
                                2'd0: begin byte0 <= shift; dcnt <= 2'd1; end
                                2'd1: begin byte1 <= shift; dcnt <= 2'd2; end
                                default: begin
                                    cap_reg <= {byte0, byte1};
                                    cap_val <= shift;
                                    cap_we  <= 1'b1;
                                    dcnt    <= 2'd0;
                                    cap_list.push_back(
                                        cap_entry_t'({byte0, byte1, shift}));
                                end
                            endcase
                        end
                    end
                    // ---------------- 读数据字节 ----------------
                    S_RDATA: begin
                        if (scl_fall && bitcnt < 7) begin
                            sda_pull <= ~tx_shift[7];    // 下一位
                            tx_shift <= {tx_shift[6:0], 1'b0};
                            bitcnt   <= bitcnt + 1'b1;
                        end else if (scl_fall && bitcnt == 7) begin
                            sda_pull <= 1'b0;            // 释放给 master ACK
                            bitcnt   <= 8;
                        end else if (scl_rise && bitcnt == 8) begin
                            if (!sda) begin              // master ACK：续发
                                tx_shift <= {rd_data[6:0], 1'b0};
                                sda_pull <= ~rd_data[7];
                                bitcnt   <= 0;
                            end                          // NACK：等 STOP
                        end
                    end
                    default: ;
                endcase
            end
        end
    end

    // cur_reg：写指针字节装入即更新（读方向取数用）
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) cur_reg <= 16'h0;
        else if (st == S_WDATA && scl_fall && bitcnt == 8 && ack_drove)
            case (dcnt)
                2'd0:    cur_reg[15:8] <= shift;
                2'd1:    cur_reg[7:0]  <= shift;
                default: ;
            endcase

endmodule
