////////////////////////////////////////////////////////////////////////////

//  TJ180A484S - Minimal Sapphire SOC wrapper with SD Host only

//

//  Peri / pin binding (TJ180A484S.peri.xml, vs official J484 OOB GPIOR_58-63):

//    clk_50M        @ GPIOL_26  -> pll_sys ref 25 MHz (x4/2, out_div 27)

//    i_soc_clk      @ PLL_TL0   -> SOC / APB / SPI

//    i_axi0_mem_clk @ PLL_TL0   -> SOC io_ddrA + SD ADMA (via SOC master 1)

//    i_sd_clk       @ PLL_TL0   -> SD base clock (~50 MHz)

//    sd_clk_hi      @ GPIOL_30  (peri maps sd_clk pin to sd_clk_hi)

//    sd_cmd         @ GPIOL_03

//    sd_dat[0]      @ GPIOL_05, sd_dat[1] @ GPIOL_49, sd_dat[2] @ GPIOL_04,

//                    sd_dat[3] @ GPIOL_31

//    system_uart_0  @ GPIOR_72/70, system_spi_0 @ GPIOB (1.8 V)

//    sd_wp          - not on board, tied low inside

//    sd_cd_n        - optional; tie in board top when GPIO is added in peri

//

//  Integrates:

//    soc_ti180               - RISC-V SOC (APB slave 2 + DDR master 1 + userInt B)

//    apb3_2_axi4_lite_sdhost  - APB3 to AXI4-Lite bridge for SDHC registers

//    tj180a484s_sdhost       - SD Host controller (SDIO + ADMA)

////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps



module top_soc_sd (

    // Clock / reset: use peri PLL net names; io_asyncReset is chip-top generated
    input  wire        i_soc_clk,
    input  wire        io_asyncReset,
    input  wire        i_axi0_mem_clk,
    output wire        io_memoryReset,
    output wire        io_systemReset,

    input  wire        i_sd_clk,

    // SOC io_ddrA (chip top ties mem_* to ddr_inst AXI port 0, same as ti180_oob_top)

    output wire        mem_ar_valid,

    input  wire        mem_ar_ready,

    output wire [31:0] mem_ar_payload_addr,

    output wire [7:0]  mem_ar_payload_id,

    output wire [3:0]  mem_ar_payload_region,

    output wire [7:0]  mem_ar_payload_len,

    output wire [2:0]  mem_ar_payload_size,

    output wire [1:0]  mem_ar_payload_burst,

    output wire        mem_ar_payload_lock,

    output wire [3:0]  mem_ar_payload_cache,

    output wire [3:0]  mem_ar_payload_qos,

    output wire [2:0]  mem_ar_payload_prot,



    output wire        mem_aw_valid,

    input  wire        mem_aw_ready,

    output wire [31:0] mem_aw_payload_addr,

    output wire [7:0]  mem_aw_payload_id,

    output wire [3:0]  mem_aw_payload_region,

    output wire [7:0]  mem_aw_payload_len,

    output wire [2:0]  mem_aw_payload_size,

    output wire [1:0]  mem_aw_payload_burst,

    output wire        mem_aw_payload_lock,

    output wire [3:0]  mem_aw_payload_cache,

    output wire [3:0]  mem_aw_payload_qos,

    output wire [2:0]  mem_aw_payload_prot,



    output wire        mem_w_valid,

    input  wire        mem_w_ready,

    output wire [511:0] mem_w_payload_data,

    output wire [63:0]  mem_w_payload_strb,

    output wire        mem_w_payload_last,



    input  wire        mem_b_valid,

    output wire        mem_b_ready,

    input  wire [7:0]  mem_b_payload_id,

    input  wire [1:0]  mem_b_payload_resp,



    input  wire        mem_r_valid,

    output wire        mem_r_ready,

    input  wire [511:0] mem_r_payload_data,

    input  wire [7:0]  mem_r_payload_id,

    input  wire [1:0]  mem_r_payload_resp,

    input  wire        mem_r_payload_last,



    // SOC peripherals (names match peri.xml / Interface Designer)

    output wire        system_uart_0_io_txd,

    input  wire        system_uart_0_io_rxd,



    output wire        system_spi_0_io_sclk_write,

    output wire        system_spi_0_io_data_0_writeEnable,

    input  wire        system_spi_0_io_data_0_read,

    output wire        system_spi_0_io_data_0_write,

    output wire        system_spi_0_io_data_1_writeEnable,

    input  wire        system_spi_0_io_data_1_read,

    output wire        system_spi_0_io_data_1_write,

    output wire        system_spi_0_io_ss,



    // SD card interface (names match peri.xml)

    output wire        sd_clk_hi,

    input  wire        sd_cmd_i,

    output wire        sd_cmd_o,

    output wire        sd_cmd_oe,

    input  wire [3:0]  sd_dat_i,

    output wire [3:0]  sd_dat_o,

    output wire [3:0]  sd_dat_oe,



    // Card detect: active-low (0 = inserted). Bind GPIO in peri when ready.
    input  wire        sd_cd_n,

    // JTAG USER1 -> soc_ti180 RISC-V debug (same as ti180_oob_top)
    input  wire        jtagCtrl_tck,
    input  wire        jtagCtrl_tdi,
    input  wire        jtagCtrl_enable,
    input  wire        jtagCtrl_capture,
    input  wire        jtagCtrl_shift,
    output wire        jtagCtrl_tdo

);



    //-------------------------------------------------------------------------

    // SD card sideband (official OOB leaves sd_wp floating; board has no WP)

    //-------------------------------------------------------------------------

    wire        sd_clk_lo;

    wire        sd_wp = 1'b0;



    //-------------------------------------------------------------------------

    // APB slave 2 (SD host register port)

    //-------------------------------------------------------------------------

    wire [15:0] apb2_paddr;

    wire        apb2_psel;

    wire        apb2_penable;

    wire        apb2_pready;

    wire        apb2_pwrite;

    wire [31:0] apb2_pwdata;

    wire [31:0] apb2_prdata;

    wire        apb2_pslverror;



    //-------------------------------------------------------------------------

    // SD host signals

    //-------------------------------------------------------------------------

    wire        sd_int;

    wire        sd_dat_oe_w;



    wire [9:0]  sd_axil_awaddr;

    wire        sd_axil_awvalid;

    wire        sd_axil_awready;

    wire [31:0] sd_axil_wdata;

    wire        sd_axil_wvalid;

    wire        sd_axil_wready;

    wire [9:0]  sd_axil_araddr;

    wire        sd_axil_arvalid;

    wire        sd_axil_arready;

    wire [31:0] sd_axil_rdata;

    wire        sd_axil_rvalid;

    wire        sd_axil_rready;



    wire        sd_axi_awvalid;

    wire [31:0] sd_axi_awaddr;

    wire [7:0]  sd_axi_awlen;

    wire [2:0]  sd_axi_awsize;

    wire [1:0]  sd_axi_awburst;

    wire        sd_axi_awlock;

    wire [3:0]  sd_axi_awcache;

    wire        sd_axi_awready;

    wire [31:0] sd_axi_wdata;

    wire [3:0]  sd_axi_wstrb;

    wire        sd_axi_wlast;

    wire        sd_axi_wvalid;

    wire        sd_axi_wready;

    wire [1:0]  sd_axi_bresp;

    wire        sd_axi_bvalid;

    wire        sd_axi_bready;

    wire        sd_axi_arvalid;

    wire [31:0] sd_axi_araddr;

    wire [7:0]  sd_axi_arlen;

    wire [2:0]  sd_axi_arsize;

    wire [1:0]  sd_axi_arburst;

    wire        sd_axi_arlock;

    wire [3:0]  sd_axi_arcache;

    wire        sd_axi_arready;

    wire        sd_axi_rvalid;

    wire [31:0] sd_axi_rdata;

    wire        sd_axi_rlast;

    wire [1:0]  sd_axi_rresp;

    wire        sd_axi_rready;



    //-------------------------------------------------------------------------
    // I2C open-drain enable (not routed on this board)

    //-------------------------------------------------------------------------

    wire i2c_sda_write;

    wire i2c_scl_write;



    assign sd_dat_oe = {4{sd_dat_oe_w}};



    //-------------------------------------------------------------------------

    // APB3 -> AXI4-Lite (SDHC CSR)

    //-------------------------------------------------------------------------

    apb3_2_axi4_lite_sdhost u_apb_sd (

        .clk            (i_soc_clk),

        .rstn           (~io_systemReset),

        .s_apb3_paddr   (apb2_paddr),

        .s_apb3_psel    (apb2_psel),

        .s_apb3_penable (apb2_penable),

        .s_apb3_pready  (apb2_pready),

        .s_apb3_pwrite  (apb2_pwrite),

        .s_apb3_pwdata  (apb2_pwdata),

        .s_apb3_prdata  (apb2_prdata),

        .s_apb3_pslverror(apb2_pslverror),

        .m_axi_awaddr   (sd_axil_awaddr),

        .m_axi_awvalid  (sd_axil_awvalid),

        .m_axi_awready  (sd_axil_awready),

        .m_axi_wdata    (sd_axil_wdata),

        .m_axi_wvalid   (sd_axil_wvalid),

        .m_axi_wready   (sd_axil_wready),

        .m_axi_araddr   (sd_axil_araddr),

        .m_axi_arvalid  (sd_axil_arvalid),

        .m_axi_arready  (sd_axil_arready),

        .m_axi_rdata    (sd_axil_rdata),

        .m_axi_rvalid   (sd_axil_rvalid),

        .m_axi_rready   (sd_axil_rready)

    );



    //-------------------------------------------------------------------------

    // SD Host IP

    //-------------------------------------------------------------------------

    tj180a484s_sdhost u_sdhost (

        .sd_rst         (io_systemReset),

        .sd_base_clk    (i_sd_clk),

        .sd_int         (sd_int),

        .sd_wp          (sd_wp),

        .sd_cd_n        (sd_cd_n),



        .s_axi_aclk     (i_soc_clk),

        .s_axi_awaddr   (sd_axil_awaddr),

        .s_axi_awvalid  (sd_axil_awvalid),

        .s_axi_awready  (sd_axil_awready),

        .s_axi_wdata    (sd_axil_wdata),

        .s_axi_wstrb    (4'hF),

        .s_axi_wvalid   (sd_axil_wvalid),

        .s_axi_wready   (sd_axil_wready),

        .s_axi_bresp    (),

        .s_axi_bvalid   (),

        .s_axi_bready   (1'b1),

        .s_axi_araddr   (sd_axil_araddr),

        .s_axi_arvalid  (sd_axil_arvalid),

        .s_axi_arready  (sd_axil_arready),

        .s_axi_rresp    (),

        .s_axi_rdata    (sd_axil_rdata),

        .s_axi_rvalid   (sd_axil_rvalid),

        .s_axi_rready   (sd_axil_rready),



        .m_axi_clk      (i_axi0_mem_clk),

        .m_axi_awvalid  (sd_axi_awvalid),

        .m_axi_awaddr   (sd_axi_awaddr),

        .m_axi_awlen    (sd_axi_awlen),

        .m_axi_awsize   (sd_axi_awsize),

        .m_axi_awburst  (sd_axi_awburst),

        .m_axi_awprot   (),

        .m_axi_awlock   (sd_axi_awlock),

        .m_axi_awcache  (sd_axi_awcache),

        .m_axi_awready  (sd_axi_awready),

        .m_axi_wdata    (sd_axi_wdata),

        .m_axi_wstrb    (sd_axi_wstrb),

        .m_axi_wlast    (sd_axi_wlast),

        .m_axi_wvalid   (sd_axi_wvalid),

        .m_axi_wready   (sd_axi_wready),

        .m_axi_bresp    (sd_axi_bresp),

        .m_axi_bvalid   (sd_axi_bvalid),

        .m_axi_bready   (sd_axi_bready),

        .m_axi_arvalid  (sd_axi_arvalid),

        .m_axi_araddr   (sd_axi_araddr),

        .m_axi_arlen    (sd_axi_arlen),

        .m_axi_arsize   (sd_axi_arsize),

        .m_axi_arburst  (sd_axi_arburst),

        .m_axi_arprot   (),

        .m_axi_arlock   (sd_axi_arlock),

        .m_axi_arcache  (sd_axi_arcache),

        .m_axi_arready  (sd_axi_arready),

        .m_axi_rvalid   (sd_axi_rvalid),

        .m_axi_rdata    (sd_axi_rdata),

        .m_axi_rlast    (sd_axi_rlast),

        .m_axi_rresp    (sd_axi_rresp),

        .m_axi_rready   (sd_axi_rready),



        .sd_clk_hi      (sd_clk_hi),

        .sd_clk_lo      (sd_clk_lo),

        .sd_cmd_i       (sd_cmd_i),

        .sd_cmd_o       (sd_cmd_o),

        .sd_cmd_oe      (sd_cmd_oe),

        .sd_dat_i       (sd_dat_i),

        .sd_dat_o       (sd_dat_o),

        .sd_dat_oe      (sd_dat_oe_w)

    );



    //-------------------------------------------------------------------------

    // Sapphire SOC

    //-------------------------------------------------------------------------

    soc_ti180 u_soc (

        .io_systemClk               (i_soc_clk),
        .io_asyncReset              (io_asyncReset),
        .io_memoryClk               (i_axi0_mem_clk),

        .io_memoryReset             (io_memoryReset),

        .io_systemReset             (io_systemReset),



        .system_uart_0_io_txd       (system_uart_0_io_txd),

        .system_uart_0_io_rxd       (system_uart_0_io_rxd),



        .system_i2c_0_io_sda_write  (i2c_sda_write),

        .system_i2c_0_io_sda_read   (1'b1),

        .system_i2c_0_io_scl_write  (i2c_scl_write),

        .system_i2c_0_io_scl_read   (1'b1),



        .system_gpio_0_io_read      (4'h0),

        .system_gpio_0_io_write     (),

        .system_gpio_0_io_writeEnable(),



        .system_spi_0_io_sclk_write       (system_spi_0_io_sclk_write),

        .system_spi_0_io_data_0_writeEnable(system_spi_0_io_data_0_writeEnable),

        .system_spi_0_io_data_0_read      (system_spi_0_io_data_0_read),

        .system_spi_0_io_data_0_write     (system_spi_0_io_data_0_write),

        .system_spi_0_io_data_1_writeEnable(system_spi_0_io_data_1_writeEnable),

        .system_spi_0_io_data_1_read      (system_spi_0_io_data_1_read),

        .system_spi_0_io_data_1_write     (system_spi_0_io_data_1_write),

        .system_spi_0_io_data_2_writeEnable(),

        .system_spi_0_io_data_2_read      (),

        .system_spi_0_io_data_2_write     (),

        .system_spi_0_io_data_3_writeEnable(),

        .system_spi_0_io_data_3_read      (),

        .system_spi_0_io_data_3_write     (),

        .system_spi_0_io_ss               (system_spi_0_io_ss),



        // SPI1 not used on this board

        .system_spi_1_io_sclk_write       (),

        .system_spi_1_io_data_0_writeEnable(),

        .system_spi_1_io_data_0_read      (1'b0),

        .system_spi_1_io_data_0_write     (),

        .system_spi_1_io_data_1_writeEnable(),

        .system_spi_1_io_data_1_read      (1'b0),

        .system_spi_1_io_data_1_write     (),

        .system_spi_1_io_data_2_writeEnable(),

        .system_spi_1_io_data_2_read      (),

        .system_spi_1_io_data_2_write     (),

        .system_spi_1_io_data_3_writeEnable(),

        .system_spi_1_io_data_3_read      (),

        .system_spi_1_io_data_3_write     (),

        .system_spi_1_io_ss               (),



        // APB slave 0/1/3: stub (not used)

        .io_apbSlave_0_PADDR    (),

        .io_apbSlave_0_PSEL     (),

        .io_apbSlave_0_PENABLE  (),

        .io_apbSlave_0_PWRITE   (),

        .io_apbSlave_0_PWDATA   (),

        .io_apbSlave_0_PREADY   (1'b1),

        .io_apbSlave_0_PRDATA   (32'h0),

        .io_apbSlave_0_PSLVERROR(1'b0),



        .io_apbSlave_1_PADDR    (),

        .io_apbSlave_1_PSEL     (),

        .io_apbSlave_1_PENABLE  (),

        .io_apbSlave_1_PWRITE   (),

        .io_apbSlave_1_PWDATA   (),

        .io_apbSlave_1_PREADY   (1'b1),

        .io_apbSlave_1_PRDATA   (32'h0),

        .io_apbSlave_1_PSLVERROR(1'b0),



        .io_apbSlave_2_PADDR    (apb2_paddr),

        .io_apbSlave_2_PSEL     (apb2_psel),

        .io_apbSlave_2_PENABLE  (apb2_penable),

        .io_apbSlave_2_PWRITE   (apb2_pwrite),

        .io_apbSlave_2_PWDATA   (apb2_pwdata),

        .io_apbSlave_2_PREADY   (apb2_pready),

        .io_apbSlave_2_PRDATA   (apb2_prdata),

        .io_apbSlave_2_PSLVERROR(apb2_pslverror),



        .io_apbSlave_3_PADDR    (),

        .io_apbSlave_3_PSEL     (),

        .io_apbSlave_3_PENABLE  (),

        .io_apbSlave_3_PWRITE   (),

        .io_apbSlave_3_PWDATA   (),

        .io_apbSlave_3_PREADY   (1'b1),

        .io_apbSlave_3_PRDATA   (32'h0),

        .io_apbSlave_3_PSLVERROR(1'b0),



        .userInterruptA         (1'b0),

        .userInterruptB         (sd_int),

        .userInterruptC         (1'b0),



        // DDR slave

        .io_ddrA_ar_valid           (mem_ar_valid),

        .io_ddrA_ar_ready           (mem_ar_ready),

        .io_ddrA_ar_payload_addr    (mem_ar_payload_addr),

        .io_ddrA_ar_payload_id      (mem_ar_payload_id),

        .io_ddrA_ar_payload_region  (mem_ar_payload_region),

        .io_ddrA_ar_payload_len     (mem_ar_payload_len),

        .io_ddrA_ar_payload_size    (mem_ar_payload_size),

        .io_ddrA_ar_payload_burst   (mem_ar_payload_burst),

        .io_ddrA_ar_payload_lock    (mem_ar_payload_lock),

        .io_ddrA_ar_payload_cache   (mem_ar_payload_cache),

        .io_ddrA_ar_payload_qos     (mem_ar_payload_qos),

        .io_ddrA_ar_payload_prot    (mem_ar_payload_prot),



        .io_ddrA_aw_valid           (mem_aw_valid),

        .io_ddrA_aw_ready           (mem_aw_ready),

        .io_ddrA_aw_payload_addr    (mem_aw_payload_addr),

        .io_ddrA_aw_payload_id      (mem_aw_payload_id),

        .io_ddrA_aw_payload_region  (mem_aw_payload_region),

        .io_ddrA_aw_payload_len     (mem_aw_payload_len),

        .io_ddrA_aw_payload_size    (mem_aw_payload_size),

        .io_ddrA_aw_payload_burst   (mem_aw_payload_burst),

        .io_ddrA_aw_payload_lock    (mem_aw_payload_lock),

        .io_ddrA_aw_payload_cache   (mem_aw_payload_cache),

        .io_ddrA_aw_payload_qos     (mem_aw_payload_qos),

        .io_ddrA_aw_payload_prot    (mem_aw_payload_prot),



        .io_ddrA_w_valid            (mem_w_valid),

        .io_ddrA_w_ready            (mem_w_ready),

        .io_ddrA_w_payload_data     (mem_w_payload_data),

        .io_ddrA_w_payload_strb     (mem_w_payload_strb),

        .io_ddrA_w_payload_last     (mem_w_payload_last),



        .io_ddrA_b_valid            (mem_b_valid),

        .io_ddrA_b_ready            (mem_b_ready),

        .io_ddrA_b_payload_id       (mem_b_payload_id),

        .io_ddrA_b_payload_resp     (mem_b_payload_resp),



        .io_ddrA_r_valid            (mem_r_valid),

        .io_ddrA_r_ready            (mem_r_ready),

        .io_ddrA_r_payload_data     (mem_r_payload_data),

        .io_ddrA_r_payload_id       (mem_r_payload_id),

        .io_ddrA_r_payload_resp     (mem_r_payload_resp),

        .io_ddrA_r_payload_last     (mem_r_payload_last),



        // DDR master 0: unused

        .io_ddrMasters_0_clk                (i_axi0_mem_clk),

        .io_ddrMasters_0_reset              (),

        .io_ddrMasters_0_aw_valid           (1'b0),

        .io_ddrMasters_0_aw_payload_addr    (32'h0),

        .io_ddrMasters_0_aw_payload_id      (4'h0),

        .io_ddrMasters_0_aw_payload_region  (4'h0),

        .io_ddrMasters_0_aw_payload_len     (8'h0),

        .io_ddrMasters_0_aw_payload_size    (3'h0),

        .io_ddrMasters_0_aw_payload_burst   (2'h0),

        .io_ddrMasters_0_aw_payload_lock    (1'b0),

        .io_ddrMasters_0_aw_payload_cache   (4'h0),

        .io_ddrMasters_0_aw_payload_qos     (4'h0),

        .io_ddrMasters_0_aw_payload_prot    (3'h0),

        .io_ddrMasters_0_aw_ready           (),

        .io_ddrMasters_0_w_valid            (1'b0),

        .io_ddrMasters_0_w_payload_data     (512'h0),

        .io_ddrMasters_0_w_payload_strb     (64'h0),

        .io_ddrMasters_0_w_payload_last     (1'b0),

        .io_ddrMasters_0_w_ready            (),

        .io_ddrMasters_0_b_valid            (),

        .io_ddrMasters_0_b_payload_id       (),

        .io_ddrMasters_0_b_payload_resp     (),

        .io_ddrMasters_0_b_ready            (1'b1),

        .io_ddrMasters_0_ar_valid           (1'b0),

        .io_ddrMasters_0_ar_payload_addr    (32'h0),

        .io_ddrMasters_0_ar_payload_id      (4'h0),

        .io_ddrMasters_0_ar_payload_region  (4'h0),

        .io_ddrMasters_0_ar_payload_len     (8'h0),

        .io_ddrMasters_0_ar_payload_size    (3'h0),

        .io_ddrMasters_0_ar_payload_burst   (2'h0),

        .io_ddrMasters_0_ar_payload_lock    (1'b0),

        .io_ddrMasters_0_ar_payload_cache   (4'h0),

        .io_ddrMasters_0_ar_payload_qos     (4'h0),

        .io_ddrMasters_0_ar_payload_prot    (3'h0),

        .io_ddrMasters_0_ar_ready           (),

        .io_ddrMasters_0_r_valid            (),

        .io_ddrMasters_0_r_payload_data     (),

        .io_ddrMasters_0_r_payload_id       (),

        .io_ddrMasters_0_r_payload_resp     (),

        .io_ddrMasters_0_r_payload_last     (),

        .io_ddrMasters_0_r_ready            (1'b1),



        // DDR master 1: SD ADMA (same path as official top_soc_oob)

        .io_ddrMasters_1_clk                (i_axi0_mem_clk),

        .io_ddrMasters_1_reset              (),

        .io_ddrMasters_1_aw_valid           (sd_axi_awvalid),

        .io_ddrMasters_1_aw_ready           (sd_axi_awready),

        .io_ddrMasters_1_aw_payload_addr    (sd_axi_awaddr),

        .io_ddrMasters_1_aw_payload_id      (4'hE),

        .io_ddrMasters_1_aw_payload_region  (),

        .io_ddrMasters_1_aw_payload_len     (sd_axi_awlen),

        .io_ddrMasters_1_aw_payload_size    (sd_axi_awsize),

        .io_ddrMasters_1_aw_payload_burst   (sd_axi_awburst),

        .io_ddrMasters_1_aw_payload_lock    (sd_axi_awlock),

        .io_ddrMasters_1_aw_payload_cache   (sd_axi_awcache),

        .io_ddrMasters_1_aw_payload_qos     (),

        .io_ddrMasters_1_aw_payload_prot    (),

        .io_ddrMasters_1_w_valid            (sd_axi_wvalid),

        .io_ddrMasters_1_w_ready            (sd_axi_wready),

        .io_ddrMasters_1_w_payload_data     (sd_axi_wdata),

        .io_ddrMasters_1_w_payload_strb     (sd_axi_wstrb),

        .io_ddrMasters_1_w_payload_last     (sd_axi_wlast),

        .io_ddrMasters_1_b_valid            (sd_axi_bvalid),

        .io_ddrMasters_1_b_ready            (sd_axi_bready),

        .io_ddrMasters_1_b_payload_id       (),

        .io_ddrMasters_1_b_payload_resp     (sd_axi_bresp),

        .io_ddrMasters_1_ar_valid           (sd_axi_arvalid),

        .io_ddrMasters_1_ar_ready           (sd_axi_arready),

        .io_ddrMasters_1_ar_payload_addr    (sd_axi_araddr),

        .io_ddrMasters_1_ar_payload_id      (4'hE),

        .io_ddrMasters_1_ar_payload_region  (),

        .io_ddrMasters_1_ar_payload_len     (sd_axi_arlen),

        .io_ddrMasters_1_ar_payload_size    (sd_axi_arsize),

        .io_ddrMasters_1_ar_payload_burst   (sd_axi_arburst),

        .io_ddrMasters_1_ar_payload_lock    (sd_axi_arlock),

        .io_ddrMasters_1_ar_payload_cache   (sd_axi_arcache),

        .io_ddrMasters_1_ar_payload_qos     (),

        .io_ddrMasters_1_ar_payload_prot    (),

        .io_ddrMasters_1_r_valid            (sd_axi_rvalid),

        .io_ddrMasters_1_r_ready            (sd_axi_rready),

        .io_ddrMasters_1_r_payload_data     (sd_axi_rdata),

        .io_ddrMasters_1_r_payload_id       (),

        .io_ddrMasters_1_r_payload_resp     (sd_axi_rresp),

        .io_ddrMasters_1_r_payload_last     (sd_axi_rlast),



        // AXI-A master port (unused; soc_ti180 drives AW/W/AR, tie slave ready/deassert responses)
        .axiA_awvalid               (),
        .axiA_awaddr                (),
        .axiA_awid                  (),
        .axiA_awregion              (),
        .axiA_awlen                 (),
        .axiA_awsize                (),
        .axiA_awburst               (),
        .axiA_awlock                (),
        .axiA_awcache               (),
        .axiA_awqos                 (),
        .axiA_awprot                (),
        .axiA_awready               (1'b1),
        .axiA_wvalid                (),
        .axiA_wdata                 (),
        .axiA_wstrb                 (),
        .axiA_wlast                 (),
        .axiA_wready                (1'b1),
        .axiA_bvalid                (1'b0),
        .axiA_bready                (),
        .axiA_bid                   (8'h0),
        .axiA_bresp                 (2'h0),
        .axiA_arvalid               (),
        .axiA_araddr                (),
        .axiA_arid                  (),
        .axiA_arregion              (),
        .axiA_arlen                 (),
        .axiA_arsize                (),
        .axiA_arburst               (),
        .axiA_arlock                (),
        .axiA_arcache               (),
        .axiA_arqos                 (),
        .axiA_arprot                (),
        .axiA_arready               (1'b1),
        .axiA_rvalid                (1'b0),
        .axiA_rready                (),
        .axiA_rdata                 (32'h0),
        .axiA_rid                   (8'h0),
        .axiA_rresp                 (2'h0),
        .axiA_rlast                 (1'b0),
        .axiAInterrupt              (1'b0),



        // JTAG USER1 -> RISC-V hard debug bridge (OOB style: update/reset open)
        .jtagCtrl_tck               (jtagCtrl_tck),
        .jtagCtrl_tdi               (jtagCtrl_tdi),
        .jtagCtrl_tdo               (jtagCtrl_tdo),
        .jtagCtrl_enable            (jtagCtrl_enable),
        .jtagCtrl_capture           (jtagCtrl_capture),
        .jtagCtrl_shift             (jtagCtrl_shift),
        .jtagCtrl_update            (1'b0),
        .jtagCtrl_reset             (1'b0)

    );



endmodule

