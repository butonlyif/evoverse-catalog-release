////////////////////////////////////////////////////////////////////////////
//  TJ180A484S board top - SOC + SD Host
//
//  Port list matches outflow/TJ180A484S_template.v (Interface Designer).
//  PLL / GPIO binding: TJ180A484S.peri.xml
////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

// Phase C: instantiate the MIPI CSI-2 TX pipe (mipi_tx_top -> DPHY TX2).
// Comment this out to re-run the DDR-only isolation build (BISECTION
// scaffolding below then holds the MIPI PLLs/DPHY in reset).
`define MIPI_TX_ENABLE

module top_demo
(
  (* syn_peri_port = 0 *) input sd_cd_n,
  (* syn_peri_port = 0 *) input jtag_inst1_CAPTURE,
  (* syn_peri_port = 0 *) input jtag_inst1_DRCK,
  (* syn_peri_port = 0 *) input jtag_inst1_RESET,
  (* syn_peri_port = 0 *) input jtag_inst1_RUNTEST,
  (* syn_peri_port = 0 *) input jtag_inst1_SEL,
  (* syn_peri_port = 0 *) input jtag_inst1_SHIFT,
  (* syn_peri_port = 0 *) input jtag_inst1_TCK,
  (* syn_peri_port = 0 *) input jtag_inst1_TDI,
  (* syn_peri_port = 0 *) input jtag_inst1_TMS,
  (* syn_peri_port = 0 *) input jtag_inst1_UPDATE,
  (* syn_peri_port = 0 *) input sd_cmd_i,
  (* syn_peri_port = 0 *) input [3:0] sd_dat_i,
  (* syn_peri_port = 0 *) input system_uart_0_io_rxd,
  (* syn_peri_port = 0 *) input sd_clk_100m,
  (* syn_peri_port = 0 *) input sys_clk_125m,
  (* syn_peri_port = 0 *) input pll_sys_locked,
  (* syn_peri_port = 0 *) input pll_ddr_locked,
  (* syn_peri_port = 0 *) input i_clk_27m,
  (* syn_peri_port = 0 *) input pll_mipi_refclk_locked,
  (* syn_peri_port = 0 *) input pll_csi_locked,
  (* syn_peri_port = 0 *) input pixel_clk,
  (* syn_peri_port = 0 *) input esc_clk,
  (* syn_peri_port = 0 *) input mipi_refclk_25m,
  (* syn_peri_port = 0 *) input int_fb_clk_27m,
  (* syn_peri_port = 0 *) input dphy_tx2_WORD_CLKOUT_HS,
  (* syn_peri_port = 0 *) input dphy_tx2_PLL_UNLOCK,
  (* syn_peri_port = 0 *) input dphy_tx2_STOPSTATE_CLK,
  (* syn_peri_port = 0 *) input dphy_tx2_STOPSTATE_LAN0,
  (* syn_peri_port = 0 *) input dphy_tx2_STOPSTATE_LAN1,
  (* syn_peri_port = 0 *) input dphy_tx2_STOPSTATE_LAN2,
  (* syn_peri_port = 0 *) input dphy_tx2_STOPSTATE_LAN3,
  (* syn_peri_port = 0 *) input dphy_tx2_TX_READY_ESC,
  (* syn_peri_port = 0 *) input dphy_tx2_TX_READY_HS_LAN0,
  (* syn_peri_port = 0 *) input dphy_tx2_TX_READY_HS_LAN1,
  (* syn_peri_port = 0 *) input dphy_tx2_TX_READY_HS_LAN2,
  (* syn_peri_port = 0 *) input dphy_tx2_TX_READY_HS_LAN3,
  (* syn_peri_port = 0 *) input dphy_tx2_TX_ULPS_ACTIVE_CLK_NOT,
  (* syn_peri_port = 0 *) input dphy_tx2_TX_ULPS_ACTIVE_NOT_LAN0,
  (* syn_peri_port = 0 *) input dphy_tx2_TX_ULPS_ACTIVE_NOT_LAN1,
  (* syn_peri_port = 0 *) input dphy_tx2_TX_ULPS_ACTIVE_NOT_LAN2,
  (* syn_peri_port = 0 *) input dphy_tx2_TX_ULPS_ACTIVE_NOT_LAN3,
  (* syn_peri_port = 0 *) input ddr_inst_ARREADY_0,
  (* syn_peri_port = 0 *) input ddr_inst_ARREADY_1,
  (* syn_peri_port = 0 *) input ddr_inst_AWREADY_0,
  (* syn_peri_port = 0 *) input ddr_inst_AWREADY_1,
  (* syn_peri_port = 0 *) input [5:0] ddr_inst_BID_0,
  (* syn_peri_port = 0 *) input [5:0] ddr_inst_BID_1,
  (* syn_peri_port = 0 *) input [1:0] ddr_inst_BRESP_0,
  (* syn_peri_port = 0 *) input [1:0] ddr_inst_BRESP_1,
  (* syn_peri_port = 0 *) input ddr_inst_BVALID_0,
  (* syn_peri_port = 0 *) input ddr_inst_BVALID_1,
  (* syn_peri_port = 0 *) input ddr_inst_CFG_DONE,
  (* syn_peri_port = 0 *) input ddr_inst_CTRL_BUSY,
  (* syn_peri_port = 0 *) input [1:0] ddr_inst_CTRL_CKE,
  (* syn_peri_port = 0 *) input ddr_inst_CTRL_CMD_Q_ALMOST_FULL,
  (* syn_peri_port = 0 *) input ddr_inst_CTRL_DP_IDLE,
  (* syn_peri_port = 0 *) input ddr_inst_CTRL_INT,
  (* syn_peri_port = 0 *) input ddr_inst_CTRL_MEM_RST_VALID,
  (* syn_peri_port = 0 *) input [1:0] ddr_inst_CTRL_PORT_BUSY,
  (* syn_peri_port = 0 *) input ddr_inst_CTRL_REFRESH,
  (* syn_peri_port = 0 *) input [511:0] ddr_inst_RDATA_0,
  (* syn_peri_port = 0 *) input [511:0] ddr_inst_RDATA_1,
  (* syn_peri_port = 0 *) input [5:0] ddr_inst_RID_0,
  (* syn_peri_port = 0 *) input [5:0] ddr_inst_RID_1,
  (* syn_peri_port = 0 *) input ddr_inst_RLAST_0,
  (* syn_peri_port = 0 *) input ddr_inst_RLAST_1,
  (* syn_peri_port = 0 *) input [1:0] ddr_inst_RRESP_0,
  (* syn_peri_port = 0 *) input [1:0] ddr_inst_RRESP_1,
  (* syn_peri_port = 0 *) input ddr_inst_RVALID_0,
  (* syn_peri_port = 0 *) input ddr_inst_RVALID_1,
  (* syn_peri_port = 0 *) input ddr_inst_WREADY_0,
  (* syn_peri_port = 0 *) input ddr_inst_WREADY_1,
  (* syn_peri_port = 0 *) input system_spi_0_io_data_0_read,
  (* syn_peri_port = 0 *) input system_spi_0_io_data_1_read,
  (* syn_peri_port = 0 *) output sd_clk_hi,
  (* syn_peri_port = 0 *) output sd_cmd_o,
  (* syn_peri_port = 0 *) output sd_cmd_oe,
  (* syn_peri_port = 0 *) output [3:0] sd_dat_o,
  (* syn_peri_port = 0 *) output [3:0] sd_dat_oe,
  (* syn_peri_port = 0 *) output system_uart_0_io_txd,
  (* syn_peri_port = 0 *) output [32:0] ddr_inst_ARADDR_0,
  (* syn_peri_port = 0 *) output [32:0] ddr_inst_ARADDR_1,
  (* syn_peri_port = 0 *) output ddr_inst_ARAPCMD_0,
  (* syn_peri_port = 0 *) output ddr_inst_ARAPCMD_1,
  (* syn_peri_port = 0 *) output [1:0] ddr_inst_ARBURST_0,
  (* syn_peri_port = 0 *) output [1:0] ddr_inst_ARBURST_1,
  (* syn_peri_port = 0 *) output [5:0] ddr_inst_ARID_0,
  (* syn_peri_port = 0 *) output [5:0] ddr_inst_ARID_1,
  (* syn_peri_port = 0 *) output [7:0] ddr_inst_ARLEN_0,
  (* syn_peri_port = 0 *) output [7:0] ddr_inst_ARLEN_1,
  (* syn_peri_port = 0 *) output ddr_inst_ARLOCK_0,
  (* syn_peri_port = 0 *) output ddr_inst_ARLOCK_1,
  (* syn_peri_port = 0 *) output ddr_inst_ARQOS_0,
  (* syn_peri_port = 0 *) output ddr_inst_ARQOS_1,
  (* syn_peri_port = 0 *) output [2:0] ddr_inst_ARSIZE_0,
  (* syn_peri_port = 0 *) output [2:0] ddr_inst_ARSIZE_1,
  (* syn_peri_port = 0 *) output ddr_inst_ARSTN_0,
  (* syn_peri_port = 0 *) output ddr_inst_ARSTN_1,
  (* syn_peri_port = 0 *) output ddr_inst_ARVALID_0,
  (* syn_peri_port = 0 *) output ddr_inst_ARVALID_1,
  (* syn_peri_port = 0 *) output [32:0] ddr_inst_AWADDR_0,
  (* syn_peri_port = 0 *) output [32:0] ddr_inst_AWADDR_1,
  (* syn_peri_port = 0 *) output ddr_inst_AWALLSTRB_0,
  (* syn_peri_port = 0 *) output ddr_inst_AWALLSTRB_1,
  (* syn_peri_port = 0 *) output ddr_inst_AWAPCMD_0,
  (* syn_peri_port = 0 *) output ddr_inst_AWAPCMD_1,
  (* syn_peri_port = 0 *) output [1:0] ddr_inst_AWBURST_0,
  (* syn_peri_port = 0 *) output [1:0] ddr_inst_AWBURST_1,
  (* syn_peri_port = 0 *) output [3:0] ddr_inst_AWCACHE_0,
  (* syn_peri_port = 0 *) output [3:0] ddr_inst_AWCACHE_1,
  (* syn_peri_port = 0 *) output ddr_inst_AWCOBUF_0,
  (* syn_peri_port = 0 *) output ddr_inst_AWCOBUF_1,
  (* syn_peri_port = 0 *) output [5:0] ddr_inst_AWID_0,
  (* syn_peri_port = 0 *) output [5:0] ddr_inst_AWID_1,
  (* syn_peri_port = 0 *) output [7:0] ddr_inst_AWLEN_0,
  (* syn_peri_port = 0 *) output [7:0] ddr_inst_AWLEN_1,
  (* syn_peri_port = 0 *) output ddr_inst_AWLOCK_0,
  (* syn_peri_port = 0 *) output ddr_inst_AWLOCK_1,
  (* syn_peri_port = 0 *) output ddr_inst_AWQOS_0,
  (* syn_peri_port = 0 *) output ddr_inst_AWQOS_1,
  (* syn_peri_port = 0 *) output [2:0] ddr_inst_AWSIZE_0,
  (* syn_peri_port = 0 *) output [2:0] ddr_inst_AWSIZE_1,
  (* syn_peri_port = 0 *) output ddr_inst_AWVALID_0,
  (* syn_peri_port = 0 *) output ddr_inst_AWVALID_1,
  (* syn_peri_port = 0 *) output ddr_inst_BREADY_0,
  (* syn_peri_port = 0 *) output ddr_inst_BREADY_1,
  (* syn_peri_port = 0 *) output ddr_inst_CFG_RESET,
  (* syn_peri_port = 0 *) output ddr_inst_CFG_SEL,
  (* syn_peri_port = 0 *) output ddr_inst_CFG_START,
  (* syn_peri_port = 0 *) output ddr_inst_RREADY_0,
  (* syn_peri_port = 0 *) output ddr_inst_RREADY_1,
  (* syn_peri_port = 0 *) output [511:0] ddr_inst_WDATA_0,
  (* syn_peri_port = 0 *) output [511:0] ddr_inst_WDATA_1,
  (* syn_peri_port = 0 *) output ddr_inst_WLAST_0,
  (* syn_peri_port = 0 *) output ddr_inst_WLAST_1,
  (* syn_peri_port = 0 *) output [63:0] ddr_inst_WSTRB_0,
  (* syn_peri_port = 0 *) output [63:0] ddr_inst_WSTRB_1,
  (* syn_peri_port = 0 *) output ddr_inst_WVALID_0,
  (* syn_peri_port = 0 *) output ddr_inst_WVALID_1,
  (* syn_peri_port = 0 *) output jtag_inst1_TDO,
  (* syn_peri_port = 0 *) output system_spi_0_io_data_0_write,
  (* syn_peri_port = 0 *) output system_spi_0_io_data_0_writeEnable,
  (* syn_peri_port = 0 *) output system_spi_0_io_data_1_write,
  (* syn_peri_port = 0 *) output system_spi_0_io_data_1_writeEnable,
  (* syn_peri_port = 0 *) output system_spi_0_io_sclk_write,
  (* syn_peri_port = 0 *) output system_spi_0_io_ss,
  // MIPI TX peri pins
  (* syn_peri_port = 0 *) output pll_mipi_refclk_rstn,
  (* syn_peri_port = 0 *) output pll_csi_rstn,
  (* syn_peri_port = 0 *) output dphy_tx2_PLL_SSC_EN,
  (* syn_peri_port = 0 *) output dphy_tx2_RESET_N,
  (* syn_peri_port = 0 *) output [7:0] dphy_tx2_TX_DATA_ESC,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_LPDT_ESC,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_VALID_ESC,
  (* syn_peri_port = 0 *) output [3:0] dphy_tx2_TX_TRIGGER_ESC,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_REQUEST_ESC_LAN0,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_REQUEST_ESC_LAN1,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_REQUEST_ESC_LAN2,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_REQUEST_ESC_LAN3,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_REQUEST_HS,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_REQUEST_HS_LAN0,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_REQUEST_HS_LAN1,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_REQUEST_HS_LAN2,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_REQUEST_HS_LAN3,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_SKEW_CAL_HS_LAN0,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_SKEW_CAL_HS_LAN1,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_SKEW_CAL_HS_LAN2,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_SKEW_CAL_HS_LAN3,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_ULPS_CLK,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_ULPS_ESC_LAN0,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_ULPS_ESC_LAN1,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_ULPS_ESC_LAN2,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_ULPS_ESC_LAN3,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_ULPS_EXIT,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_ULPS_EXIT_LAN0,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_ULPS_EXIT_LAN1,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_ULPS_EXIT_LAN2,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_ULPS_EXIT_LAN3,
  (* syn_peri_port = 0 *) output [15:0] dphy_tx2_TX_DATA_HS_LAN0,
  (* syn_peri_port = 0 *) output [15:0] dphy_tx2_TX_DATA_HS_LAN1,
  (* syn_peri_port = 0 *) output [15:0] dphy_tx2_TX_DATA_HS_LAN2,
  (* syn_peri_port = 0 *) output [15:0] dphy_tx2_TX_DATA_HS_LAN3,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_WORD_VALID_HS_LAN0,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_WORD_VALID_HS_LAN1,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_WORD_VALID_HS_LAN2,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_WORD_VALID_HS_LAN3
);

    //-------------------------------------------------------------------------
    // Global async reset (active-high w_sysclk_arst -> top_soc_sd.io_asyncReset)
    //
    // Same as ti180_oob_top (without user switch):
    //   io_asyncResetn = pll_sys_locked & pll_ddr_locked
    //   w_sysclk_arst    = ~io_asyncResetn
    //
    // SOC io_memoryReset / io_systemReset are outputs from soc_ti180.
    // DDR cfg FSM below waits for io_memoryReset deassert before starting.
    //-------------------------------------------------------------------------
    wire        io_asyncResetn;
    wire        w_sysclk_arst;
    wire        io_memoryReset;
    wire        io_systemReset;

    // video stream: top_soc_sd (video_reader) -> mipi_tx_top (both @ sys_clk_125m)
    wire [63:0] w_vid_data;
    wire        w_vid_valid;
    wire        w_vid_pause;

    assign io_asyncResetn = pll_sys_locked & pll_ddr_locked;
    assign w_sysclk_arst    = ~io_asyncResetn;

    //-------------------------------------------------------------------------
    // LPDDR configuration FSM (same flow as ti180_oob_top / top_soc)
    //-------------------------------------------------------------------------
    localparam [1:0] IDLE      = 2'b00,
                     CFG_START = 2'b01,
                     CFG_DONE  = 2'b11;

    reg  [1:0]  cfg_st, cfg_next;
    reg  [7:0]  cfg_count;
    wire        ddr_cfg_ok;
    reg         r_ddr_reset;

    assign ddr_cfg_ok = (cfg_st == CFG_DONE);

    always @(posedge sys_clk_125m or posedge w_sysclk_arst) begin
        if (w_sysclk_arst)
            r_ddr_reset <= 1'b1;
        else
            r_ddr_reset <= io_memoryReset;
    end

    always @(posedge sys_clk_125m or posedge r_ddr_reset) begin
        if (r_ddr_reset) begin
            cfg_st    <= IDLE;
            cfg_count <= 8'h0;
        end else begin
            cfg_st <= cfg_next;
            if (cfg_st == IDLE)
                cfg_count <= cfg_count + 1'b1;
            else
                cfg_count <= 8'h0;
        end
    end

    always @(*) begin
        cfg_next = cfg_st;
        case (cfg_st)
            IDLE: begin
                if (cfg_count == 8'hff)
                    cfg_next = CFG_START;
                else
                    cfg_next = IDLE;
            end
            CFG_START: begin
                if (ddr_inst_CFG_DONE)
                    cfg_next = CFG_DONE;
                else
                    cfg_next = CFG_START;
            end
            CFG_DONE: cfg_next = CFG_DONE;
            default:  cfg_next = IDLE;
        endcase
    end

    assign ddr_inst_CFG_START = (cfg_st != IDLE);
    assign ddr_inst_CFG_RESET = (cfg_st == IDLE);
    assign ddr_inst_CFG_SEL   = 1'b0;

    //-------------------------------------------------------------------------
    // SOC io_ddrA <-> ddr_inst AXI port 0 (same glue as ti180_oob_top inst_soc_oob)
    //-------------------------------------------------------------------------
    wire [31:0] io_ddrA_ar_payload_addr_i;
    wire [31:0] io_ddrA_aw_payload_addr_i;
    wire [7:0]  io_ddrA_ar_payload_id_i;
    wire [7:0]  io_ddrA_aw_payload_id_i;
    wire [7:0]  io_ddrA_b_payload_id_i;
    wire [7:0]  io_ddrA_r_payload_id_i;

    assign ddr_inst_ARID_0 = {io_ddrA_ar_payload_id_i[7:6], io_ddrA_ar_payload_id_i[3:0]};
    assign ddr_inst_AWID_0 = {io_ddrA_aw_payload_id_i[7:6], io_ddrA_aw_payload_id_i[3:0]};
    assign io_ddrA_b_payload_id_i = {ddr_inst_BID_0[5:4], 2'b00, ddr_inst_BID_0[3:0]};
    assign io_ddrA_r_payload_id_i = {ddr_inst_RID_0[5:4], 2'b00, ddr_inst_RID_0[3:0]};

    assign ddr_inst_ARSTN_0     = ddr_cfg_ok;
    assign ddr_inst_ARAPCMD_0   = 1'b0;
    assign ddr_inst_AWALLSTRB_0 = 1'b0;
    assign ddr_inst_AWAPCMD_0   = 1'b0;
    assign ddr_inst_AWCOBUF_0   = 1'b0;
    assign ddr_inst_ARADDR_0    = {1'b0, io_ddrA_ar_payload_addr_i};
    assign ddr_inst_AWADDR_0    = {1'b0, io_ddrA_aw_payload_addr_i};

    //-------------------------------------------------------------------------
    // DDR AXI port 1: read-only verification reader (in top_soc_sd)
    //-------------------------------------------------------------------------
    wire [31:0] mem1_ar_payload_addr;
    wire [5:0]  mem1_ar_payload_id;
    wire [7:0]  mem1_ar_payload_len;
    wire [2:0]  mem1_ar_payload_size;
    wire [1:0]  mem1_ar_payload_burst;
    wire        mem1_ar_payload_lock;
    wire        mem1_ar_payload_qos;
    wire        mem1_ar_valid;
    wire        mem1_ar_ready;
    wire [511:0] mem1_r_payload_data;
    wire [5:0]  mem1_r_payload_id;
    wire [1:0]  mem1_r_payload_resp;
    wire        mem1_r_payload_last;
    wire        mem1_r_valid;
    wire        mem1_r_ready;

    assign ddr_inst_ARSTN_1     = ddr_cfg_ok;
    assign ddr_inst_ARVALID_1   = mem1_ar_valid;
    assign ddr_inst_ARADDR_1    = {1'b0, mem1_ar_payload_addr};
    assign ddr_inst_ARBURST_1   = mem1_ar_payload_burst;
    assign ddr_inst_ARID_1      = mem1_ar_payload_id;
    assign ddr_inst_ARLEN_1     = mem1_ar_payload_len;
    assign ddr_inst_ARLOCK_1    = mem1_ar_payload_lock;
    assign ddr_inst_ARQOS_1     = mem1_ar_payload_qos;
    assign ddr_inst_ARSIZE_1    = mem1_ar_payload_size;
    assign ddr_inst_ARAPCMD_1   = 1'b0;

    /* DDR port 1 read response path -> top_soc_sd */
    assign mem1_ar_ready        = ddr_inst_ARREADY_1;
    assign mem1_r_valid         = ddr_inst_RVALID_1;
    assign mem1_r_payload_data  = ddr_inst_RDATA_1;
    assign mem1_r_payload_id    = ddr_inst_RID_1;
    assign mem1_r_payload_resp  = ddr_inst_RRESP_1;
    assign mem1_r_payload_last  = ddr_inst_RLAST_1;

    // No write path on port 1
    assign ddr_inst_AWVALID_1   = 1'b0;
    assign ddr_inst_AWADDR_1    = 33'h0;
    assign ddr_inst_AWALLSTRB_1 = 1'b0;
    assign ddr_inst_AWAPCMD_1   = 1'b0;
    assign ddr_inst_AWBURST_1   = 2'h0;
    assign ddr_inst_AWCACHE_1   = 4'h0;
    assign ddr_inst_AWCOBUF_1   = 1'b0;
    assign ddr_inst_AWID_1      = 6'h0;
    assign ddr_inst_AWLEN_1     = 8'h0;
    assign ddr_inst_AWLOCK_1    = 1'b0;
    assign ddr_inst_AWQOS_1     = 1'b0;
    assign ddr_inst_AWSIZE_1    = 3'h0;

    assign ddr_inst_WVALID_1    = 1'b0;
    assign ddr_inst_WDATA_1     = 512'h0;
    assign ddr_inst_WLAST_1     = 1'b0;
    assign ddr_inst_WSTRB_1     = 64'h0;

    assign ddr_inst_BREADY_1    = 1'b1;
    assign ddr_inst_RREADY_1    = mem1_r_ready;

    //-------------------------------------------------------------------------
    // SOC + SD Host
    //
    // Clock merge (Interface Designer): pll_sys generates two outputs -
    //   sd_clk_100m (CLKOUT0, feedback, 100 MHz) -> SD host base clock
    //   sys_clk_125m (CLKOUT1, 125 MHz)          -> whole SoC + DDR AXI
    // top_soc_sd keeps its legacy port names (i_soc_clk/i_axi0_mem_clk/i_sd_clk);
    // both SoC clocks are tied to the single sys_clk_125m net.
    //-------------------------------------------------------------------------
    top_soc_sd u_top_soc_sd (
        .i_soc_clk                      (sys_clk_125m),
        .io_asyncReset                  (w_sysclk_arst),
        .i_axi0_mem_clk                 (sys_clk_125m),
        .io_memoryReset                 (io_memoryReset),
        .io_systemReset                 (io_systemReset),
        .i_sd_clk                       (sd_clk_100m),

        .mem_ar_valid                   (ddr_inst_ARVALID_0),
        .mem_ar_ready                   (ddr_inst_ARREADY_0),
        .mem_ar_payload_addr            (io_ddrA_ar_payload_addr_i),
        .mem_ar_payload_id              (io_ddrA_ar_payload_id_i),
        .mem_ar_payload_region          (),
        .mem_ar_payload_len             (ddr_inst_ARLEN_0),
        .mem_ar_payload_size            (ddr_inst_ARSIZE_0),
        .mem_ar_payload_burst           (ddr_inst_ARBURST_0),
        .mem_ar_payload_lock            (ddr_inst_ARLOCK_0),
        .mem_ar_payload_cache           (),
        .mem_ar_payload_qos             (ddr_inst_ARQOS_0),
        .mem_ar_payload_prot            (),

        .mem_aw_valid                   (ddr_inst_AWVALID_0),
        .mem_aw_ready                   (ddr_inst_AWREADY_0),
        .mem_aw_payload_addr            (io_ddrA_aw_payload_addr_i),
        .mem_aw_payload_id              (io_ddrA_aw_payload_id_i),
        .mem_aw_payload_region          (),
        .mem_aw_payload_len             (ddr_inst_AWLEN_0),
        .mem_aw_payload_size            (ddr_inst_AWSIZE_0),
        .mem_aw_payload_burst           (ddr_inst_AWBURST_0),
        .mem_aw_payload_lock            (ddr_inst_AWLOCK_0),
        .mem_aw_payload_cache           (ddr_inst_AWCACHE_0),
        .mem_aw_payload_qos             (ddr_inst_AWQOS_0),
        .mem_aw_payload_prot            (),

        .mem_w_valid                    (ddr_inst_WVALID_0),
        .mem_w_ready                    (ddr_inst_WREADY_0),
        .mem_w_payload_data             (ddr_inst_WDATA_0),
        .mem_w_payload_strb             (ddr_inst_WSTRB_0),
        .mem_w_payload_last             (ddr_inst_WLAST_0),

        .mem_b_valid                    (ddr_inst_BVALID_0),
        .mem_b_ready                    (ddr_inst_BREADY_0),
        .mem_b_payload_id               (io_ddrA_b_payload_id_i),
        .mem_b_payload_resp             (ddr_inst_BRESP_0),

        .mem_r_valid                    (ddr_inst_RVALID_0),
        .mem_r_ready                    (ddr_inst_RREADY_0),
        .mem_r_payload_data             (ddr_inst_RDATA_0),
        .mem_r_payload_id               (io_ddrA_r_payload_id_i),
        .mem_r_payload_resp             (ddr_inst_RRESP_0),
        .mem_r_payload_last             (ddr_inst_RLAST_0),

        .mem1_ar_valid                  (mem1_ar_valid),
        .mem1_ar_ready                  (mem1_ar_ready),
        .mem1_ar_payload_addr           (mem1_ar_payload_addr),
        .mem1_ar_payload_id             (mem1_ar_payload_id),
        .mem1_ar_payload_len            (mem1_ar_payload_len),
        .mem1_ar_payload_size           (mem1_ar_payload_size),
        .mem1_ar_payload_burst          (mem1_ar_payload_burst),
        .mem1_ar_payload_lock           (mem1_ar_payload_lock),
        .mem1_ar_payload_qos            (mem1_ar_payload_qos),
        .mem1_r_valid                   (mem1_r_valid),
        .mem1_r_ready                   (mem1_r_ready),
        .mem1_r_payload_data            (mem1_r_payload_data),
        .mem1_r_payload_id              (mem1_r_payload_id),
        .mem1_r_payload_resp            (mem1_r_payload_resp),
        .mem1_r_payload_last            (mem1_r_payload_last),

        .vid_data                       (w_vid_data),
        .vid_valid                      (w_vid_valid),
        .vid_pause                      (w_vid_pause),

        .system_uart_0_io_txd           (system_uart_0_io_txd),
        .system_uart_0_io_rxd           (system_uart_0_io_rxd),

        .system_spi_0_io_sclk_write     (system_spi_0_io_sclk_write),
        .system_spi_0_io_data_0_writeEnable (system_spi_0_io_data_0_writeEnable),
        .system_spi_0_io_data_0_read    (system_spi_0_io_data_0_read),
        .system_spi_0_io_data_0_write   (system_spi_0_io_data_0_write),
        .system_spi_0_io_data_1_writeEnable (system_spi_0_io_data_1_writeEnable),
        .system_spi_0_io_data_1_read    (system_spi_0_io_data_1_read),
        .system_spi_0_io_data_1_write   (system_spi_0_io_data_1_write),
        .system_spi_0_io_ss             (system_spi_0_io_ss),

        .sd_clk_hi                      (sd_clk_hi),
        .sd_cmd_i                       (sd_cmd_i),
        .sd_cmd_o                       (sd_cmd_o),
        .sd_cmd_oe                      (sd_cmd_oe),
        .sd_dat_i                       (sd_dat_i),
        .sd_dat_o                       (sd_dat_o),
        .sd_dat_oe                      (sd_dat_oe),
        .sd_cd_n                        (sd_cd_n),

        // JTAG USER1 (peri jtag_inst1) -> riscv_soc RISC-V debug
        .jtagCtrl_tck                   (jtag_inst1_TCK),
        .jtagCtrl_tdi                   (jtag_inst1_TDI),
        .jtagCtrl_tdo                   (jtag_inst1_TDO),
        .jtagCtrl_enable                (jtag_inst1_SEL),
        .jtagCtrl_capture               (jtag_inst1_CAPTURE),
        .jtagCtrl_shift                 (jtag_inst1_SHIFT)
    );

    // jtag_inst2_* (USER2): owned by Efinity LA debug core, do not route in user RTL.

    // Suppress unused-peri warnings for clocks consumed inside DDR / PLL blocks

    //-------------------------------------------------------------------------
    // MIPI CSI-2 TX pipe (phase C)
    //
    // Clock/reset network identical to ws-e1-mipi-1280x720-yuv reference:
    //   pll_mipi_refclk (TL1): int_fb_clk_27m + mipi_refclk_25m
    //   pll_csi         (BL0): pixel_clk 18.5625MHz + esc_clk
    //   DPHY TX2 hard macro: 4 data lanes + clock lane @ 2.5Gbps
    //
    // LP (escape) data path unused by the CSI-2 TX IP -> tie off.
    //-------------------------------------------------------------------------
    assign dphy_tx2_TX_DATA_ESC   = 8'h0;
    assign dphy_tx2_TX_LPDT_ESC   = 1'b0;
    assign dphy_tx2_TX_VALID_ESC  = 1'b0;
    assign dphy_tx2_TX_TRIGGER_ESC = 4'h0;

`ifdef MIPI_TX_ENABLE
    mipi_tx_top #(
        .HACT         (16'd1280),
        .VACT         (14'd720),
        .HSP          (12'd40),
        .HBP          (12'd220),
        .HFP          (12'd112),
        .VSP          (12'd5),
        .VBP          (12'd20),
        .VFP          (12'd5),
        .NUM_DATA_LANE(4),
        .DATATYPE     (6'h1E)
    ) u_mipi_tx_top (
        // clocks & PLL status
        .sys_clk_125m                 (sys_clk_125m),
        .pixel_clk                    (pixel_clk),
        .pll_mipi_refclk_rstn         (pll_mipi_refclk_rstn),
        .pll_csi_rstn                 (pll_csi_rstn),
        .pll_sys_locked               (pll_sys_locked),
        .pll_csi_locked               (pll_csi_locked),
        .pll_mipi_refclk_locked       (pll_mipi_refclk_locked),
        .i_clk_27m                    (i_clk_27m),

        // DPHY TX2 hard macro
        .dphy_tx2_WORD_CLKOUT_HS      (dphy_tx2_WORD_CLKOUT_HS),
        .esc_clk                      (esc_clk),
        .mipi_refclk_25m              (mipi_refclk_25m),
        .dphy_tx2_PLL_UNLOCK          (dphy_tx2_PLL_UNLOCK),
        .dphy_tx2_RESET_N             (dphy_tx2_RESET_N),
        .dphy_tx2_PLL_SSC_EN          (dphy_tx2_PLL_SSC_EN),

        .dphy_tx2_STOPSTATE_CLK       (dphy_tx2_STOPSTATE_CLK),
        .dphy_tx2_TX_REQUEST_HS       (dphy_tx2_TX_REQUEST_HS),
        .dphy_tx2_TX_ULPS_CLK         (dphy_tx2_TX_ULPS_CLK),
        .dphy_tx2_TX_ULPS_EXIT        (dphy_tx2_TX_ULPS_EXIT),
        .dphy_tx2_TX_ULPS_ACTIVE_CLK_NOT (dphy_tx2_TX_ULPS_ACTIVE_CLK_NOT),

        .dphy_tx2_TX_ULPS_ESC_LAN0    (dphy_tx2_TX_ULPS_ESC_LAN0),
        .dphy_tx2_TX_ULPS_ESC_LAN1    (dphy_tx2_TX_ULPS_ESC_LAN1),
        .dphy_tx2_TX_ULPS_ESC_LAN2    (dphy_tx2_TX_ULPS_ESC_LAN2),
        .dphy_tx2_TX_ULPS_ESC_LAN3    (dphy_tx2_TX_ULPS_ESC_LAN3),
        .dphy_tx2_TX_ULPS_EXIT_LAN0   (dphy_tx2_TX_ULPS_EXIT_LAN0),
        .dphy_tx2_TX_ULPS_EXIT_LAN1   (dphy_tx2_TX_ULPS_EXIT_LAN1),
        .dphy_tx2_TX_ULPS_EXIT_LAN2   (dphy_tx2_TX_ULPS_EXIT_LAN2),
        .dphy_tx2_TX_ULPS_EXIT_LAN3   (dphy_tx2_TX_ULPS_EXIT_LAN3),
        .dphy_tx2_TX_ULPS_ACTIVE_NOT_LAN0 (dphy_tx2_TX_ULPS_ACTIVE_NOT_LAN0),
        .dphy_tx2_TX_ULPS_ACTIVE_NOT_LAN1 (dphy_tx2_TX_ULPS_ACTIVE_NOT_LAN1),
        .dphy_tx2_TX_ULPS_ACTIVE_NOT_LAN2 (dphy_tx2_TX_ULPS_ACTIVE_NOT_LAN2),
        .dphy_tx2_TX_ULPS_ACTIVE_NOT_LAN3 (dphy_tx2_TX_ULPS_ACTIVE_NOT_LAN3),

        .dphy_tx2_TX_REQUEST_ESC_LAN0 (dphy_tx2_TX_REQUEST_ESC_LAN0),
        .dphy_tx2_TX_REQUEST_ESC_LAN1 (dphy_tx2_TX_REQUEST_ESC_LAN1),
        .dphy_tx2_TX_REQUEST_ESC_LAN2 (dphy_tx2_TX_REQUEST_ESC_LAN2),
        .dphy_tx2_TX_REQUEST_ESC_LAN3 (dphy_tx2_TX_REQUEST_ESC_LAN3),
        .dphy_tx2_STOPSTATE_LAN0      (dphy_tx2_STOPSTATE_LAN0),
        .dphy_tx2_STOPSTATE_LAN1      (dphy_tx2_STOPSTATE_LAN1),
        .dphy_tx2_STOPSTATE_LAN2      (dphy_tx2_STOPSTATE_LAN2),
        .dphy_tx2_STOPSTATE_LAN3      (dphy_tx2_STOPSTATE_LAN3),

        .dphy_tx2_TX_SKEW_CAL_HS_LAN0 (dphy_tx2_TX_SKEW_CAL_HS_LAN0),
        .dphy_tx2_TX_SKEW_CAL_HS_LAN1 (dphy_tx2_TX_SKEW_CAL_HS_LAN1),
        .dphy_tx2_TX_SKEW_CAL_HS_LAN2 (dphy_tx2_TX_SKEW_CAL_HS_LAN2),
        .dphy_tx2_TX_SKEW_CAL_HS_LAN3 (dphy_tx2_TX_SKEW_CAL_HS_LAN3),
        .dphy_tx2_TX_READY_HS_LAN0    (dphy_tx2_TX_READY_HS_LAN0),
        .dphy_tx2_TX_READY_HS_LAN1    (dphy_tx2_TX_READY_HS_LAN1),
        .dphy_tx2_TX_READY_HS_LAN2    (dphy_tx2_TX_READY_HS_LAN2),
        .dphy_tx2_TX_READY_HS_LAN3    (dphy_tx2_TX_READY_HS_LAN3),
        .dphy_tx2_TX_REQUEST_HS_LAN0  (dphy_tx2_TX_REQUEST_HS_LAN0),
        .dphy_tx2_TX_REQUEST_HS_LAN1  (dphy_tx2_TX_REQUEST_HS_LAN1),
        .dphy_tx2_TX_REQUEST_HS_LAN2  (dphy_tx2_TX_REQUEST_HS_LAN2),
        .dphy_tx2_TX_REQUEST_HS_LAN3  (dphy_tx2_TX_REQUEST_HS_LAN3),
        .dphy_tx2_TX_DATA_HS_LAN0     (dphy_tx2_TX_DATA_HS_LAN0),
        .dphy_tx2_TX_DATA_HS_LAN1     (dphy_tx2_TX_DATA_HS_LAN1),
        .dphy_tx2_TX_DATA_HS_LAN2     (dphy_tx2_TX_DATA_HS_LAN2),
        .dphy_tx2_TX_DATA_HS_LAN3     (dphy_tx2_TX_DATA_HS_LAN3),
        .dphy_tx2_TX_WORD_VALID_HS_LAN0 (dphy_tx2_TX_WORD_VALID_HS_LAN0),
        .dphy_tx2_TX_WORD_VALID_HS_LAN1 (dphy_tx2_TX_WORD_VALID_HS_LAN1),
        .dphy_tx2_TX_WORD_VALID_HS_LAN2 (dphy_tx2_TX_WORD_VALID_HS_LAN2),
        .dphy_tx2_TX_WORD_VALID_HS_LAN3 (dphy_tx2_TX_WORD_VALID_HS_LAN3),

        // video stream from video_reader (DDR Port 1)
        .i_vid_data                   (w_vid_data),
        .i_vid_valid                  (w_vid_valid),
        .o_vid_pause                  (w_vid_pause)
    );
`else
    //-------------------------------------------------------------------------
    // BISECTION STEP (Bug #2): MIPI TX fabric removed by default.
    //
    // Hard macros (PLL_TL1 pll_mipi_refclk / PLL_BL0 pll_csi / DPHY TX2) stay
    // in peri.xml, but are held in reset and all lane requests are idle, so
    // nothing toggles on the MIPI clock/power domain during the DDR port1 test.
    // Re-enable the whole pipe with define MIPI_TX_ENABLE.
    //-------------------------------------------------------------------------
    assign pll_mipi_refclk_rstn         = 1'b0;   // PLL_TL1 held in reset
    assign pll_csi_rstn                 = 1'b0;   // PLL_BL0 held in reset
    assign dphy_tx2_RESET_N             = 1'b0;   // DPHY TX2 held in reset
    assign dphy_tx2_PLL_SSC_EN          = 1'b0;

    assign dphy_tx2_TX_REQUEST_HS       = 1'b0;
    assign dphy_tx2_TX_REQUEST_HS_LAN0  = 1'b0;
    assign dphy_tx2_TX_REQUEST_HS_LAN1  = 1'b0;
    assign dphy_tx2_TX_REQUEST_HS_LAN2  = 1'b0;
    assign dphy_tx2_TX_REQUEST_HS_LAN3  = 1'b0;
    assign dphy_tx2_TX_REQUEST_ESC_LAN0 = 1'b0;
    assign dphy_tx2_TX_REQUEST_ESC_LAN1 = 1'b0;
    assign dphy_tx2_TX_REQUEST_ESC_LAN2 = 1'b0;
    assign dphy_tx2_TX_REQUEST_ESC_LAN3 = 1'b0;

    assign dphy_tx2_TX_ULPS_CLK         = 1'b0;
    assign dphy_tx2_TX_ULPS_ESC_LAN0    = 1'b0;
    assign dphy_tx2_TX_ULPS_ESC_LAN1    = 1'b0;
    assign dphy_tx2_TX_ULPS_ESC_LAN2    = 1'b0;
    assign dphy_tx2_TX_ULPS_ESC_LAN3    = 1'b0;
    assign dphy_tx2_TX_ULPS_EXIT        = 1'b0;
    assign dphy_tx2_TX_ULPS_EXIT_LAN0   = 1'b0;
    assign dphy_tx2_TX_ULPS_EXIT_LAN1   = 1'b0;
    assign dphy_tx2_TX_ULPS_EXIT_LAN2   = 1'b0;
    assign dphy_tx2_TX_ULPS_EXIT_LAN3   = 1'b0;

    assign dphy_tx2_TX_SKEW_CAL_HS_LAN0 = 1'b0;
    assign dphy_tx2_TX_SKEW_CAL_HS_LAN1 = 1'b0;
    assign dphy_tx2_TX_SKEW_CAL_HS_LAN2 = 1'b0;
    assign dphy_tx2_TX_SKEW_CAL_HS_LAN3 = 1'b0;

    assign dphy_tx2_TX_DATA_HS_LAN0     = 16'h0;
    assign dphy_tx2_TX_DATA_HS_LAN1     = 16'h0;
    assign dphy_tx2_TX_DATA_HS_LAN2     = 16'h0;
    assign dphy_tx2_TX_DATA_HS_LAN3     = 16'h0;
    assign dphy_tx2_TX_WORD_VALID_HS_LAN0 = 1'b0;
    assign dphy_tx2_TX_WORD_VALID_HS_LAN1 = 1'b0;
    assign dphy_tx2_TX_WORD_VALID_HS_LAN2 = 1'b0;
    assign dphy_tx2_TX_WORD_VALID_HS_LAN3 = 1'b0;

    // video_reader runs unconstrained when the MIPI pipe is absent
    assign w_vid_pause                  = 1'b0;
`endif

endmodule
