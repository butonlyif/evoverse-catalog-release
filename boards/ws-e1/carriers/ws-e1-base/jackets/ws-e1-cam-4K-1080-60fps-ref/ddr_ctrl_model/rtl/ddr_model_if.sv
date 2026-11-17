// Testbench-side AXI4 interface wrapper. The DUT itself exposes flat ports.
interface ddr_model_if #(
  parameter int ADDR_W = 33,
  parameter int DATA_W = 512,
  parameter int ID_W   = 6,
  parameter int STRB_W = DATA_W/8
);
  logic             ARSTN;

  logic [ADDR_W-1:0] AWADDR;
  logic [1:0]        AWBURST;
  logic [ID_W-1:0]   AWID;
  logic [7:0]        AWLEN;
  logic              AWREADY;
  logic [2:0]        AWSIZE;
  logic              AWVALID;
  logic              AWLOCK;
  logic              AWAPCMD;
  logic [3:0]        AWQOS;
  logic [3:0]        AWCACHE;
  logic              AWALLSTRB;
  logic              AWCOBUF;

  logic [DATA_W-1:0] WDATA;
  logic              WLAST;
  logic              WREADY;
  logic [STRB_W-1:0] WSTRB;
  logic              WVALID;

  logic [ID_W-1:0]   BID;
  logic              BREADY;
  logic [1:0]        BRESP;
  logic              BVALID;

  logic [ADDR_W-1:0] ARADDR;
  logic [1:0]        ARBURST;
  logic [ID_W-1:0]   ARID;
  logic [7:0]        ARLEN;
  logic              ARREADY;
  logic [2:0]        ARSIZE;
  logic              ARVALID;
  logic              ARLOCK;
  logic              ARAPCMD;
  logic [3:0]        ARQOS;

  logic [DATA_W-1:0] RDATA;
  logic [ID_W-1:0]   RID;
  logic              RLAST;
  logic              RREADY;
  logic [1:0]        RRESP;
  logic              RVALID;

  modport master (
    output AWADDR, AWBURST, AWID, AWLEN, AWSIZE, AWVALID, AWLOCK, AWAPCMD,
           AWQOS, AWCACHE, AWALLSTRB, AWCOBUF, WDATA, WLAST, WSTRB, WVALID,
           BREADY, ARADDR, ARBURST, ARID, ARLEN, ARSIZE, ARVALID, ARLOCK,
           ARAPCMD, ARQOS, RREADY,
    input  AWREADY, WREADY, BID, BRESP, BVALID, ARREADY, RDATA, RID, RLAST,
           RRESP, RVALID
  );

  modport slave (
    input  AWADDR, AWBURST, AWID, AWLEN, AWSIZE, AWVALID, AWLOCK, AWAPCMD,
           AWQOS, AWCACHE, AWALLSTRB, AWCOBUF, WDATA, WLAST, WSTRB, WVALID,
           BREADY, ARADDR, ARBURST, ARID, ARLEN, ARSIZE, ARVALID, ARLOCK,
           ARAPCMD, ARQOS, RREADY,
    output AWREADY, WREADY, BID, BRESP, BVALID, ARREADY, RDATA, RID, RLAST,
           RRESP, RVALID
  );
endinterface
