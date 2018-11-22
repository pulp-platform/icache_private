// Copyright 2018 ETH Zurich, University of Bologna and Greenwaves Technologies.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

/*icache_top_private.sv*/


module icache_top_private
#(
    // Parameter for MULTIBANK CACHE
    parameter   NB_CORES                = 4,        // Number of  Processor:     -->  2  |  4  | 8  | 16 | 32
    parameter   NB_REFILL_PORT          = 1,        // DO NOT EDIT --> 1 refill port

    parameter   NB_WAYS                 = 4,        // 1: DIRECT MAPPED;   2 | 4 | 8    --> Set Associative ICACHE
    parameter   CACHE_LINE              = 1,        // WORDS in each cache line allowed value are 1 - 2 - 4 - 8
    parameter   CACHE_SIZE              = 4096,     // In Byte
    parameter   FIFO_DEPTH              = 2,

    parameter   FETCH_ADDR_WIDTH        = 32,
    parameter   FETCH_DATA_WIDTH        = 32,

    parameter   AXI_ID                  = 10,
    parameter   AXI_USER                = 6,
    parameter   AXI_DATA                = 64,
    parameter   AXI_ADDR                = 32,

    parameter   L2_SIZE                 = 256*1024,
    parameter   USE_REDUCED_TAG         = "TRUE"
)
(
    // CORES I$ PLUG ----------------------------------------------------------
    // ------------------------------------------------------------------------
    input logic                                           clk,
    input logic                                           rst_n,
    input logic                                           test_en_i,

    input  logic [NB_CORES-1:0]                           fetch_req_i,
    input  logic [NB_CORES-1:0][FETCH_ADDR_WIDTH-1:0]     fetch_addr_i,
    output logic [NB_CORES-1:0]                           fetch_gnt_o,

    output logic [NB_CORES-1:0]                           fetch_rvalid_o,
    output logic [NB_CORES-1:0][FETCH_DATA_WIDTH-1:0]     fetch_rdata_o,
    // ---------------------------------------------------------------
    // Refill BUS I$ -----------------------------------------
    // ---------------------------------------------------------------
    output logic [AXI_ID-1:0]                             axi_master_awid_o,
    output logic [AXI_ADDR-1:0]                           axi_master_awaddr_o,
    output logic [ 7:0]                                   axi_master_awlen_o,
    output logic [ 2:0]                                   axi_master_awsize_o,
    output logic [ 1:0]                                   axi_master_awburst_o,
    output logic                                          axi_master_awlock_o,
    output logic [ 3:0]                                   axi_master_awcache_o,
    output logic [ 2:0]                                   axi_master_awprot_o,
    output logic [ 3:0]                                   axi_master_awregion_o,
    output logic [ AXI_USER-1:0]                          axi_master_awuser_o,
    output logic [ 3:0]                                   axi_master_awqos_o,
    output logic                                          axi_master_awvalid_o,
    input  logic                                          axi_master_awready_i,

    //AXI write data bus -------------- // // --------------
    output logic  [AXI_DATA-1:0]                          axi_master_wdata_o,
    output logic  [AXI_DATA/8-1:0]                        axi_master_wstrb_o,
    output logic                                          axi_master_wlast_o,
    output logic  [ AXI_USER-1:0]                         axi_master_wuser_o,
    output logic                                          axi_master_wvalid_o,
    input  logic                                          axi_master_wready_i,
    // ---------------------------------------------------------------

    //AXI BACKWARD write response bus -------------- // // --------------
    input  logic [AXI_ID-1:0]                            axi_master_bid_i,
    input  logic [ 1:0]                                  axi_master_bresp_i,
    input  logic [ AXI_USER-1:0]                         axi_master_buser_i,
    input  logic                                         axi_master_bvalid_i,
    output logic                                         axi_master_bready_o,
    // ---------------------------------------------------------------

    //AXI read address bus -------------------------------------------
    output  logic [AXI_ID-1:0]                            axi_master_arid_o,       //
    output  logic [AXI_ADDR-1:0]                          axi_master_araddr_o,     //
    output  logic [ 7:0]                                  axi_master_arlen_o,      // burst length - 1 to 256
    output  logic [ 2:0]                                  axi_master_arsize_o,     // size of each transfer in burst
    output  logic [ 1:0]                                  axi_master_arburst_o,    // for bursts>1, accept only incr burst=01
    output  logic                                         axi_master_arlock_o,     // only normal access supported axs_awlock=00
    output  logic [ 3:0]                                  axi_master_arcache_o,    //
    output  logic [ 2:0]                                  axi_master_arprot_o,     //
    output  logic [ 3:0]                                  axi_master_arregion_o,   //
    output  logic [ AXI_USER-1:0]                         axi_master_aruser_o,     //
    output  logic [ 3:0]                                  axi_master_arqos_o,      //
    output  logic                                         axi_master_arvalid_o,    // master addr valid
    input   logic                                         axi_master_arready_i,    // slave ready to accept
    // --------------------------------------------------------------------------------

    //AXI BACKWARD read data bus ----------------------------------------------
    input  logic [AXI_ID-1:0]                             axi_master_rid_i,        //
    input  logic [AXI_DATA-1:0]                           axi_master_rdata_i,      //
    input  logic [ 1:0]                                   axi_master_rresp_i,      //
    input  logic                                          axi_master_rlast_i,      // last transfer in burst
    input  logic [ AXI_USER-1:0]                          axi_master_ruser_i,      //
    input  logic                                          axi_master_rvalid_i,     // slave data valid
    output logic                                          axi_master_rready_o,     //,     // master ready to accept
    // Control ports
    PRI_ICACHE_CTRL_UNIT_BUS.Slave                        IC_ctrl_unit_slave_if[NB_CORES]

);

   // NEW_ICACHE_CTRL_UNIT_BUS                         IC_ctrl_unit_slave_if[NB_CORES]();

   localparam  AXI_ID_INT  =  1;
   localparam  AXI_ID_OUT  =  $clog2(NB_CORES) + AXI_ID_INT;
   localparam  TAG_BITS    =  $clog2(L2_SIZE/CACHE_SIZE)+$clog2(NB_WAYS)+1;
   genvar i;

   logic [NB_CORES-1:0][AXI_ID_INT-1:0]                         axi_master_awid_int;
   logic [NB_CORES-1:0][AXI_ADDR-1:0]                           axi_master_awaddr_int;
   logic [NB_CORES-1:0][ 7:0]                                   axi_master_awlen_int;
   logic [NB_CORES-1:0][ 2:0]                                   axi_master_awsize_int;
   logic [NB_CORES-1:0][ 1:0]                                   axi_master_awburst_int;
   logic [NB_CORES-1:0]                                         axi_master_awlock_int;
   logic [NB_CORES-1:0][ 3:0]                                   axi_master_awcache_int;
   logic [NB_CORES-1:0][ 2:0]                                   axi_master_awprot_int;
   logic [NB_CORES-1:0][ 3:0]                                   axi_master_awregion_int;
   logic [NB_CORES-1:0][ AXI_USER-1:0]                          axi_master_awuser_int;
   logic [NB_CORES-1:0][ 3:0]                                   axi_master_awqos_int;
   logic [NB_CORES-1:0]                                         axi_master_awvalid_int;
   logic [NB_CORES-1:0]                                         axi_master_awready_int;

    //AXI write data bus -------------- // // --------------
   logic [NB_CORES-1:0] [AXI_DATA-1:0]                          axi_master_wdata_int;
   logic [NB_CORES-1:0] [AXI_DATA/8-1:0]                        axi_master_wstrb_int;
   logic [NB_CORES-1:0]                                         axi_master_wlast_int;
   logic [NB_CORES-1:0] [ AXI_USER-1:0]                         axi_master_wuser_int;
   logic [NB_CORES-1:0]                                         axi_master_wvalid_int;
   logic [NB_CORES-1:0]                                         axi_master_wready_int;
    // ---------------------------------------------------------------

    //AXI BACKWARD write response bus -------------- // // --------------
   logic [NB_CORES-1:0] [AXI_ID_INT-1:0]                        axi_master_bid_int;
   logic [NB_CORES-1:0] [ 1:0]                                  axi_master_bresp_int;
   logic [NB_CORES-1:0] [ AXI_USER-1:0]                         axi_master_buser_int;
   logic [NB_CORES-1:0]                                         axi_master_bvalid_int;
   logic [NB_CORES-1:0]                                         axi_master_bready_int;
    // ---------------------------------------------------------------

    //AXI read address bus -------------------------------------------
   logic [NB_CORES-1:0][AXI_ID_INT-1:0]                        axi_master_arid_int;       //
   logic [NB_CORES-1:0][AXI_ADDR-1:0]                          axi_master_araddr_int;     //
   logic [NB_CORES-1:0][ 7:0]                                  axi_master_arlen_int;      // burst length - 1 to 256
   logic [NB_CORES-1:0][ 2:0]                                  axi_master_arsize_int;     // size of each transfer in burst
   logic [NB_CORES-1:0][ 1:0]                                  axi_master_arburst_int;    // for bursts>1, accept only incr burst=01
   logic [NB_CORES-1:0]                                        axi_master_arlock_int;     // only normal access supported axs_awlock=00
   logic [NB_CORES-1:0][ 3:0]                                  axi_master_arcache_int;    //
   logic [NB_CORES-1:0][ 2:0]                                  axi_master_arprot_int;     //
   logic [NB_CORES-1:0][ 3:0]                                  axi_master_arregion_int;   //
   logic [NB_CORES-1:0][ AXI_USER-1:0]                         axi_master_aruser_int;     //
   logic [NB_CORES-1:0][ 3:0]                                  axi_master_arqos_int;      //
   logic [NB_CORES-1:0]                                        axi_master_arvalid_int;    // master addr valid
   logic [NB_CORES-1:0]                                        axi_master_arready_int;    // slave ready to accept
    // --------------------------------------------------------------------------------

    //AXI BACKWARD read data bus ----------------------------------------------
   logic [NB_CORES-1:0][AXI_ID_INT-1:0]                         axi_master_rid_int;        //
   logic [NB_CORES-1:0][AXI_DATA-1:0]                           axi_master_rdata_int;      //
   logic [NB_CORES-1:0][ 1:0]                                   axi_master_rresp_int;      //
   logic [NB_CORES-1:0]                                         axi_master_rlast_int;      // last transfer in burst
   logic [NB_CORES-1:0][ AXI_USER-1:0]                          axi_master_ruser_int;      //
   logic [NB_CORES-1:0]                                         axi_master_rvalid_int;     // slave data valid
   logic [NB_CORES-1:0]                                         axi_master_rready_int;     // master ready to accept

   generate
   for(i=0; i<NB_CORES; i++)
   begin : CACHE_BANK_
      icache_bank_private
      #(
         .FETCH_ADDR_WIDTH ( FETCH_ADDR_WIDTH ),
         .FETCH_DATA_WIDTH ( FETCH_DATA_WIDTH ),

         .NB_WAYS          ( NB_WAYS          ),
         .CACHE_SIZE       ( CACHE_SIZE       ),
         .CACHE_LINE       ( CACHE_LINE       ),

         .AXI_ID           ( AXI_ID_INT       ),
         .AXI_ADDR         ( AXI_ADDR         ),
         .AXI_USER         ( AXI_USER         ),
         .AXI_DATA         ( AXI_DATA         ),
         .USE_REDUCED_TAG  ( USE_REDUCED_TAG  ),
         .TAG_BITS         ( TAG_BITS         )
      )
      i_icache_bank_priavte
      (
         .clk                    (clk                      ),
         .rst_n                  (rst_n                    ),
         .test_en_i              (test_en_i                ),

         // interface with processor
         .fetch_req_i            (fetch_req_i[i]            ),
         .fetch_addr_i           (fetch_addr_i[i]           ),
         .fetch_gnt_o            (fetch_gnt_o[i]            ),
         .fetch_rvalid_o         (fetch_rvalid_o[i]         ),
         .fetch_rdata_o          (fetch_rdata_o[i]          ),

         //AXI read address bus -------------------------------------------
         .axi_master_arid_o      (axi_master_arid_int[i]    ),
         .axi_master_araddr_o    (axi_master_araddr_int[i]  ),
         .axi_master_arlen_o     (axi_master_arlen_int[i]   ),    
         .axi_master_arsize_o    (axi_master_arsize_int[i]  ),   
         .axi_master_arburst_o   (axi_master_arburst_int[i] ),  
         .axi_master_arlock_o    (axi_master_arlock_int[i]  ),   
         .axi_master_arcache_o   (axi_master_arcache_int[i] ), 
         .axi_master_arprot_o    (axi_master_arprot_int[i]  ),
         .axi_master_arregion_o  (axi_master_arregion_int[i]), 
         .axi_master_aruser_o    (axi_master_aruser_int[i]  ),   
         .axi_master_arqos_o     (axi_master_arqos_int[i]   ),    
         .axi_master_arvalid_o   (axi_master_arvalid_int[i] ),  
         .axi_master_arready_i   (axi_master_arready_int[i] ),  
         // ---------------------------------------------------------------


         //AXI BACKWARD read data bus ----------------------------------------------
         .axi_master_rid_i       (axi_master_rid_int[i]       ),
         .axi_master_rdata_i     (axi_master_rdata_int[i]     ),
         .axi_master_rresp_i     (axi_master_rresp_int[i]     ),
         .axi_master_rlast_i     (axi_master_rlast_int[i]     ),    //last transfer in burst
         .axi_master_ruser_i     (axi_master_ruser_int[i]     ),
         .axi_master_rvalid_i    (axi_master_rvalid_int[i]    ),   //slave data valid
         .axi_master_rready_o    (axi_master_rready_int[i]    ),    //master ready to accept

         // NOT USED ----------------------------------------------
         .axi_master_awid_o      (axi_master_awid_int[i]     ),
         .axi_master_awaddr_o    (axi_master_awaddr_int[i]   ),
         .axi_master_awlen_o     (axi_master_awlen_int[i]    ),
         .axi_master_awsize_o    (axi_master_awsize_int[i]   ),
         .axi_master_awburst_o   (axi_master_awburst_int[i]  ),
         .axi_master_awlock_o    (axi_master_awlock_int[i]   ),
         .axi_master_awcache_o   (axi_master_awcache_int[i]  ),
         .axi_master_awprot_o    (axi_master_awprot_int[i]   ),
         .axi_master_awregion_o  (axi_master_awregion_int[i] ),
         .axi_master_awuser_o    (axi_master_awuser_int[i]   ),
         .axi_master_awqos_o     (axi_master_awqos_int[i]    ),
         .axi_master_awvalid_o   (axi_master_awvalid_int[i]  ),
         .axi_master_awready_i   (axi_master_awready_int[i]  ),

         // NOT USED ----------------------------------------------
         .axi_master_wdata_o     (axi_master_wdata_int[i]     ),
         .axi_master_wstrb_o     (axi_master_wstrb_int[i]     ),
         .axi_master_wlast_o     (axi_master_wlast_int[i]     ),
         .axi_master_wuser_o     (axi_master_wuser_int[i]     ),
         .axi_master_wvalid_o    (axi_master_wvalid_int[i]    ),
         .axi_master_wready_i    (axi_master_wready_int[i]    ),
         // ---------------------------------------------------------------

         // NOT USED ----------------------------------------------
         .axi_master_bid_i       (axi_master_bid_int[i]       ),
         .axi_master_bresp_i     (axi_master_bresp_int[i]     ),
         .axi_master_buser_i     (axi_master_buser_int[i]     ),
         .axi_master_bvalid_i    (axi_master_bvalid_int[i]    ),
         .axi_master_bready_o    (axi_master_bready_int[i]    ),
         // ---------------------------------------------------------------

         .bypass_icache_i           ( IC_ctrl_unit_slave_if[i].bypass_req ),
         .cache_is_bypassed_o       ( IC_ctrl_unit_slave_if[i].bypass_ack ),
         .flush_icache_i            ( IC_ctrl_unit_slave_if[i].flush_req  ),
         .cache_is_flushed_o        ( IC_ctrl_unit_slave_if[i].flush_ack  ),
         .flush_set_ID_req_i        ( 1'b0                                ),
         .flush_set_ID_addr_i       ( 32'h0000_0000                       ),
         .flush_set_ID_ack_o        (                                     ),

         .ctrl_hit_count_icache_o   ( IC_ctrl_unit_slave_if[i].ctrl_hit_count    ),
         .ctrl_trans_count_icache_o ( IC_ctrl_unit_slave_if[i].ctrl_trans_count  ),
         .ctrl_miss_count_icache_o  ( IC_ctrl_unit_slave_if[i].ctrl_miss_count   ),
         .ctrl_clear_regs_icache_i  ( IC_ctrl_unit_slave_if[i].ctrl_clear_regs   ),
         .ctrl_enable_regs_icache_i ( IC_ctrl_unit_slave_if[i].ctrl_enable_regs  ) 
      );
      //assign IC_ctrl_unit_slave_if[i].ctrl_miss_count = '0;
   end

        
 
   endgenerate



      localparam N_MASTER_PORT = 1;
      localparam N_REGION      = 1;
      
      logic [N_REGION-1:0][N_MASTER_PORT-1:0][31:0]                      cfg_START_ADDR_int;
      logic [N_REGION-1:0][N_MASTER_PORT-1:0][31:0]                      cfg_END_ADDR_int;
      logic [N_REGION-1:0][N_MASTER_PORT-1:0]                            cfg_valid_rule_int;
      logic [NB_CORES-1:0][N_MASTER_PORT-1:0]                            cfg_connectivity_map_int;
      
      assign cfg_START_ADDR_int[0][0]       = 32'h1C00_0000;
      assign cfg_END_ADDR_int[0][0]         = 32'h1CFF_FFFF;
      assign cfg_valid_rule_int[0][0]       = 1'b1;
      

      generate
      for(i=0; i<NB_CORES; i++)
         assign cfg_connectivity_map_int[i][0]       = 1'b1;
      endgenerate



/////////////////////////////////////////////////////////////////
//  █████╗ ██╗  ██╗██╗    ███╗   ██╗ ██████╗ ██████╗ ███████╗  //
// ██╔══██╗╚██╗██╔╝██║    ████╗  ██║██╔═══██╗██╔══██╗██╔════╝  //
// ███████║ ╚███╔╝ ██║    ██╔██╗ ██║██║   ██║██║  ██║█████╗    //
// ██╔══██║ ██╔██╗ ██║    ██║╚██╗██║██║   ██║██║  ██║██╔══╝    //
// ██║  ██║██╔╝ ██╗██║    ██║ ╚████║╚██████╔╝██████╔╝███████╗  //
// ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝    ╚═╝  ╚═══╝ ╚═════╝ ╚═════╝ ╚══════╝  //
/////////////////////////////////////////////////////////////////
axi_node
#(

    .AXI_ADDRESS_W      ( AXI_ADDR                 ),
    .AXI_DATA_W         ( AXI_DATA                 ),
    .AXI_NUMBYTES       ( AXI_DATA/8               ),

    .AXI_USER_W         ( AXI_USER                 ),
    .AXI_ID_IN          ( AXI_ID_INT               ),
    .AXI_ID_OUT         ( AXI_ID_OUT               ),

    .N_MASTER_PORT      ( NB_REFILL_PORT           ),
    .N_SLAVE_PORT       ( NB_CORES                 ),


    .FIFO_DEPTH_DW      ( 2                        ),
    .N_REGION           ( 1                        )
)
AXI_INTRUCTION_BUS
(
  .clk                  (  clk                    ),
  .rst_n                (  rst_n                  ),
  .test_en_i            (  test_en_i              ),

  // ---------------------------------------------------------------
  // AXI TARG Port Declarations -----------------------------------------
  // ---------------------------------------------------------------
  .slave_awid_i          ( axi_master_awid_int      ),
  .slave_awaddr_i        ( axi_master_awaddr_int    ),
  .slave_awlen_i         ( axi_master_awlen_int     ),
  .slave_awsize_i        ( axi_master_awsize_int    ),
  .slave_awburst_i       ( axi_master_awburst_int   ),
  .slave_awlock_i        ( axi_master_awlock_int    ),
  .slave_awcache_i       ( axi_master_awcache_int   ),
  .slave_awprot_i        ( axi_master_awprot_int    ),
  .slave_awregion_i      ( axi_master_awregion_int  ),
  .slave_awuser_i        ( axi_master_awuser_int    ),
  .slave_awqos_i         ( axi_master_awqos_int     ),
  .slave_awvalid_i       ( axi_master_awvalid_int   ),
  .slave_awready_o       ( axi_master_awready_int   ),

  .slave_wdata_i         ( axi_master_wdata_int     ),
  .slave_wstrb_i         ( axi_master_wstrb_int     ),
  .slave_wlast_i         ( axi_master_wlast_int     ),
  .slave_wuser_i         ( axi_master_wuser_int     ),
  .slave_wvalid_i        ( axi_master_wvalid_int    ),
  .slave_wready_o        ( axi_master_wready_int    ),


  .slave_bid_o           ( axi_master_bid_int       ),
  .slave_bresp_o         ( axi_master_bresp_int     ),
  .slave_bvalid_o        ( axi_master_bvalid_int    ),
  .slave_buser_o         ( axi_master_buser_int     ),
  .slave_bready_i        ( axi_master_bready_int    ),


  .slave_arid_i          ( axi_master_arid_int      ),
  .slave_araddr_i        ( axi_master_araddr_int    ),
  .slave_arlen_i         ( axi_master_arlen_int     ),
  .slave_arsize_i        ( axi_master_arsize_int    ),
  .slave_arburst_i       ( axi_master_arburst_int   ),
  .slave_arlock_i        ( axi_master_arlock_int    ),
  .slave_arcache_i       ( axi_master_arcache_int   ),
  .slave_arprot_i        ( axi_master_arprot_int    ),
  .slave_arregion_i      ( axi_master_arregion_int  ),
  .slave_aruser_i        ( axi_master_aruser_int    ),
  .slave_arqos_i         ( axi_master_arqos_int     ),
  .slave_arvalid_i       ( axi_master_arvalid_int   ),
  .slave_arready_o       ( axi_master_arready_int   ),
  // -----------------------------------------------

  .slave_rid_o           ( axi_master_rid_int       ),
  .slave_rdata_o         ( axi_master_rdata_int     ),
  .slave_rresp_o         ( axi_master_rresp_int     ),
  .slave_rlast_o         ( axi_master_rlast_int     ),
  .slave_ruser_o         ( axi_master_ruser_int     ),
  .slave_rvalid_o        ( axi_master_rvalid_int    ),
  .slave_rready_i        ( axi_master_rready_int    ),
  // -----------------------------------------------

  // -----------------------------------------------
  // AXI INIT Port Declarations --------------------
  // -----------------------------------------------
  .master_awid_o          ( axi_master_awid_o[AXI_ID_OUT-1:0] ),
  .master_awaddr_o        ( axi_master_awaddr_o               ),
  .master_awlen_o         ( axi_master_awlen_o                ),
  .master_awsize_o        ( axi_master_awsize_o               ),
  .master_awburst_o       ( axi_master_awburst_o              ),
  .master_awlock_o        ( axi_master_awlock_o               ),
  .master_awcache_o       ( axi_master_awcache_o              ),
  .master_awprot_o        ( axi_master_awprot_o               ),
  .master_awregion_o      ( axi_master_awregion_o             ),
  .master_awuser_o        ( axi_master_awuser_o               ),
  .master_awqos_o         ( axi_master_awqos_o                ),
  .master_awvalid_o       ( axi_master_awvalid_o              ),
  .master_awready_i       ( axi_master_awready_i              ),

  .master_wdata_o         ( axi_master_wdata_o                ),
  .master_wstrb_o         ( axi_master_wstrb_o                ),
  .master_wlast_o         ( axi_master_wlast_o                ),
  .master_wuser_o         ( axi_master_wuser_o                ),
  .master_wvalid_o        ( axi_master_wvalid_o               ),
  .master_wready_i        ( axi_master_wready_i               ),

  .master_bid_i           ( axi_master_bid_i[AXI_ID_OUT-1:0]  ),
  .master_bresp_i         ( axi_master_bresp_i                ),
  .master_buser_i         ( axi_master_buser_i                ),
  .master_bvalid_i        ( axi_master_bvalid_i               ),
  .master_bready_o        ( axi_master_bready_o               ),

  .master_arid_o          ( axi_master_arid_o[AXI_ID_OUT-1:0] ),
  .master_araddr_o        ( axi_master_araddr_o               ),
  .master_arlen_o         ( axi_master_arlen_o                ),
  .master_arsize_o        ( axi_master_arsize_o               ),
  .master_arburst_o       ( axi_master_arburst_o              ),
  .master_arlock_o        ( axi_master_arlock_o               ),
  .master_arcache_o       ( axi_master_arcache_o              ),
  .master_arprot_o        ( axi_master_arprot_o               ),
  .master_arregion_o      ( axi_master_arregion_o             ),
  .master_aruser_o        ( axi_master_aruser_o               ),
  .master_arqos_o         ( axi_master_arqos_o                ),
  .master_arvalid_o       ( axi_master_arvalid_o              ),
  .master_arready_i       ( axi_master_arready_i              ),

  .master_rid_i           ( axi_master_rid_i[AXI_ID_OUT-1:0]  ),
  .master_rdata_i         ( axi_master_rdata_i                ),
  .master_rresp_i         ( axi_master_rresp_i                ),
  .master_rlast_i         ( axi_master_rlast_i                ),
  .master_ruser_i         ( axi_master_ruser_i                ),
  .master_rvalid_i        ( axi_master_rvalid_i               ),
  .master_rready_o        ( axi_master_rready_o               ),

  .cfg_START_ADDR_i       ( cfg_START_ADDR_int                ),
  .cfg_END_ADDR_i         ( cfg_END_ADDR_int                  ),
  .cfg_valid_rule_i       ( cfg_valid_rule_int                ),
  .cfg_connectivity_map_i ( cfg_connectivity_map_int          )

);

assign     axi_master_awid_o[AXI_ID-1:AXI_ID_OUT] = {(AXI_ID-AXI_ID_OUT){1'b0}};
assign     axi_master_arid_o[AXI_ID-1:AXI_ID_OUT] = {(AXI_ID-AXI_ID_OUT){1'b0}};

endmodule
