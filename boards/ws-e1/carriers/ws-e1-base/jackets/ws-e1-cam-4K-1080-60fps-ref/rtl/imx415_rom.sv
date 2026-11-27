// =============================================================================
// imx415_rom.sv -- IMX415 I2C 初始化序列 ROM（自动生成，勿手改）
//
// 生成器 : tools/gen_imx415_rom.py
// 源文件 : sw/top_demo/src/imx415_init.c（唯一真值：改序列先改 C，再重跑生成器）
// 序列   : [   0..108] 基表 109 条（standby 首条, imx415_reg_tbl）
//          [109..119] geo 11 条（MODE_4K=1 -> geo4k / 0 -> geo1080）
//          [120..121] LANEMODE 2 条（0x4001=0x03, 0x4002=0x00）
//          [122..139] DPHY 1782Mbps 18 条（9×16-bit LE，TCLKZERO hi=0x01 必写）
//          [140..141] stream-on 2 条（0x3002=0x00 先于 0x3000=0x00，顺序敏感）
// 共 142 条写事务；每条 = START + 0x34 + {regH,regL,val} + STOP（7bit 地址 0x1A）。
// =============================================================================
module imx415_rom #(
    parameter bit MODE_4K = 1'b1   // 1=cam0 4K60 all-pixel, 0=cam1 1080p60 2/2 binning
) (
    input  logic [7:0]  idx,       // 0..N_ENTRIES-1
    output logic [23:0] data,      // {regH, regL, val}
    output logic [7:0]  last_idx   // = N_ENTRIES-1，控制器表尾判定（防双源漂移）
);

    localparam int N_ENTRIES = 142;

    assign last_idx = 8'd141;

    always_comb begin
        case (idx)
            8'd0  : data = 24'h30_00_01;  // standby
            8'd1  : data = 24'h30_31_00;  // ADBIT 10bit
            8'd2  : data = 24'h30_32_00;  // MDBIT 10bit (reset 0x01)
            8'd3  : data = 24'h30_E2_32;  // BLKLEVEL[7:0] = 50
            8'd4  : data = 24'h30_E3_00;  // BLKLEVEL[9:8]
            8'd5  : data = 24'h30_C0_0A;  // OUTSEL (cam2_1080p.md fixed value)
            8'd6  : data = 24'h30_C1_00;  // DRV
            8'd7  : data = 24'h32_D4_21;
            8'd8  : data = 24'h32_EC_A1;
            8'd9  : data = 24'h34_52_7F;
            8'd10 : data = 24'h34_53_03;
            8'd11 : data = 24'h35_8A_04;
            8'd12 : data = 24'h35_A1_02;
            8'd13 : data = 24'h36_BC_0C;
            8'd14 : data = 24'h36_CC_53;
            8'd15 : data = 24'h36_CD_00;
            8'd16 : data = 24'h36_CE_3C;
            8'd17 : data = 24'h36_D0_8C;
            8'd18 : data = 24'h36_D1_00;
            8'd19 : data = 24'h36_D2_71;
            8'd20 : data = 24'h36_D4_3C;
            8'd21 : data = 24'h36_D6_53;
            8'd22 : data = 24'h36_D7_00;
            8'd23 : data = 24'h36_D8_71;
            8'd24 : data = 24'h36_DA_8C;
            8'd25 : data = 24'h36_DB_00;
            8'd26 : data = 24'h37_24_02;
            8'd27 : data = 24'h37_26_02;
            8'd28 : data = 24'h37_32_02;
            8'd29 : data = 24'h37_34_03;
            8'd30 : data = 24'h37_36_03;
            8'd31 : data = 24'h37_42_03;
            8'd32 : data = 24'h38_62_E0;
            8'd33 : data = 24'h38_CC_30;
            8'd34 : data = 24'h38_CD_2F;
            8'd35 : data = 24'h39_5C_0C;
            8'd36 : data = 24'h3A_42_D1;
            8'd37 : data = 24'h3A_4C_77;
            8'd38 : data = 24'h3A_E0_02;
            8'd39 : data = 24'h3A_EC_0C;
            8'd40 : data = 24'h3B_00_2E;
            8'd41 : data = 24'h3B_06_29;
            8'd42 : data = 24'h3B_98_25;
            8'd43 : data = 24'h3B_99_21;
            8'd44 : data = 24'h3B_9B_13;
            8'd45 : data = 24'h3B_9C_13;
            8'd46 : data = 24'h3B_9D_13;
            8'd47 : data = 24'h3B_9E_13;
            8'd48 : data = 24'h3B_A1_00;
            8'd49 : data = 24'h3B_A2_06;
            8'd50 : data = 24'h3B_A3_0B;
            8'd51 : data = 24'h3B_A4_10;
            8'd52 : data = 24'h3B_A5_14;
            8'd53 : data = 24'h3B_A6_18;
            8'd54 : data = 24'h3B_A7_1A;
            8'd55 : data = 24'h3B_A8_1A;
            8'd56 : data = 24'h3B_A9_1A;
            8'd57 : data = 24'h3B_AC_ED;
            8'd58 : data = 24'h3B_AD_01;
            8'd59 : data = 24'h3B_AE_F6;
            8'd60 : data = 24'h3B_AF_02;
            8'd61 : data = 24'h3B_B0_A2;
            8'd62 : data = 24'h3B_B1_03;
            8'd63 : data = 24'h3B_B2_E0;
            8'd64 : data = 24'h3B_B3_03;
            8'd65 : data = 24'h3B_B4_E0;
            8'd66 : data = 24'h3B_B5_03;
            8'd67 : data = 24'h3B_B6_E0;
            8'd68 : data = 24'h3B_B7_03;
            8'd69 : data = 24'h3B_B8_E0;
            8'd70 : data = 24'h3B_BA_E0;
            8'd71 : data = 24'h3B_BC_DA;
            8'd72 : data = 24'h3B_BE_88;
            8'd73 : data = 24'h3B_C0_44;
            8'd74 : data = 24'h3B_C2_7B;
            8'd75 : data = 24'h3B_C4_A2;
            8'd76 : data = 24'h3B_C8_BD;
            8'd77 : data = 24'h3B_CA_BD;  // ---- legacy geometry rows (VMAX 6576 = 30fps basis): kept for the verified write order only; the geo1080 block in imx415_init_once() overwrites the mode-dependent values ----
            8'd78 : data = 24'h30_1C_04;  // WINMODE window crop
            8'd79 : data = 24'h30_20_01;
            8'd80 : data = 24'h30_21_01;  // H/V binning
            8'd81 : data = 24'h30_22_01;  // ADDMODE 2/2
            8'd82 : data = 24'h30_24_B0;
            8'd83 : data = 24'h30_25_19;  // VMAX = 6576 (30fps)
            8'd84 : data = 24'h30_28_6D;
            8'd85 : data = 24'h30_29_01;  // HMAX = 365
            8'd86 : data = 24'h30_40_88;
            8'd87 : data = 24'h30_41_02;  // PIX_HST = 0x288
            8'd88 : data = 24'h30_42_08;
            8'd89 : data = 24'h30_43_0A;  // PIX_HWIDTH = 0xA08
            8'd90 : data = 24'h30_44_F0;
            8'd91 : data = 24'h30_45_02;  // PIX_VST = 0x2F0
            8'd92 : data = 24'h30_46_40;
            8'd93 : data = 24'h30_47_0B;  // PIX_VWIDTH = 0xB40
            8'd94 : data = 24'h30_50_08;  // SHR0
            8'd95 : data = 24'h30_D9_02;
            8'd96 : data = 24'h30_DA_01;  // DIG_CLP (binning 2/2)
            8'd97 : data = 24'h30_08_7F;  // BCWAIT_TIME
            8'd98 : data = 24'h30_0A_5B;  // CPWAIT_TIME
            8'd99 : data = 24'h30_33_04;  // SYS_MODE = 1782 Mbps
            8'd100: data = 24'h31_15_00;  // INCKSEL1
            8'd101: data = 24'h31_16_24;
            8'd102: data = 24'h31_18_C0;
            8'd103: data = 24'h31_1A_E0;
            8'd104: data = 24'h31_1E_24;
            8'd105: data = 24'h40_0C_01;  // INCKSEL6 (1782 col)
            8'd106: data = 24'h40_74_00;  // INCKSEL7 (>=1440: 0)
            8'd107: data = 24'h40_04_48;
            8'd108: data = 24'h40_05_09;  // TXCLKESC 0x948
            // ---- [109..119] geo（MODE 分支）----
            8'd109: data = MODE_4K ? 24'h30_1C_00 : 24'h30_1C_00;  // WINMODE: all-pixel
            8'd110: data = MODE_4K ? 24'h30_20_00 : 24'h30_20_01;  // H binning off
            8'd111: data = MODE_4K ? 24'h30_21_00 : 24'h30_21_01;  // V binning off
            8'd112: data = MODE_4K ? 24'h30_22_00 : 24'h30_22_01;  // ADDMODE off
            8'd113: data = MODE_4K ? 24'h30_24_CA : 24'h30_24_CA;  // VMAX = 2250 -> 60fps
            8'd114: data = MODE_4K ? 24'h30_25_08 : 24'h30_25_08;
            8'd115: data = MODE_4K ? 24'h30_26_00 : 24'h30_26_00;
            8'd116: data = MODE_4K ? 24'h30_28_26 : 24'h30_28_26;  // HMAX = 550 (0x226)
            8'd117: data = MODE_4K ? 24'h30_29_02 : 24'h30_29_02;
            8'd118: data = MODE_4K ? 24'h30_D9_06 : 24'h30_D9_02;  // DIG_CLP_VSTART: all-pixel (regmap: 06h=all-pixel/crop, 02h=binning)
            8'd119: data = MODE_4K ? 24'h30_DA_02 : 24'h30_DA_01;  // DIG_CLP_VNUM: all-pixel (02h)
            // ---- [120..121] LANEMODE ----
            8'd120: data = 24'h40_01_03;  // LANEMODE 4-lane (val=0x03)
            8'd121: data = 24'h40_02_00;  // LANEMODE hi byte
            // ---- [122..139] DPHY 1782Mbps ----
            8'd122: data = 24'h40_18_B7;  // TCLKPOST
            8'd123: data = 24'h40_19_00;  // TCLKPOST hi
            8'd124: data = 24'h40_1A_67;  // TCLKPREPARE
            8'd125: data = 24'h40_1B_00;  // TCLKPREPARE hi
            8'd126: data = 24'h40_1C_6F;  // TCLKTRAIL
            8'd127: data = 24'h40_1D_00;  // TCLKTRAIL hi
            8'd128: data = 24'h40_1E_DF;  // TCLKZERO (hi 0x401F = 0x01!)
            8'd129: data = 24'h40_1F_01;  // TCLKZERO (hi 0x401F = 0x01!) hi
            8'd130: data = 24'h40_20_6F;  // THSPREPARE
            8'd131: data = 24'h40_21_00;  // THSPREPARE hi
            8'd132: data = 24'h40_22_CF;  // THSZERO
            8'd133: data = 24'h40_23_00;  // THSZERO hi
            8'd134: data = 24'h40_24_6F;  // THSTRAIL
            8'd135: data = 24'h40_25_00;  // THSTRAIL hi
            8'd136: data = 24'h40_26_B7;  // THSEXIT
            8'd137: data = 24'h40_27_00;  // THSEXIT hi
            8'd138: data = 24'h40_28_5F;  // TLPX
            8'd139: data = 24'h40_29_00;  // TLPX hi
            // ---- [140..141] stream-on ----
            8'd140: data = 24'h30_02_00;  // master-mode start（须仍在 standby 中）
            8'd141: data = 24'h30_00_00;  // standby 释放 -> 流启动
            default: data = 24'h0;
        endcase
    end

endmodule
