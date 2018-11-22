// Copyright 2018 ETH Zurich, University of Bologna and Greenwaves Technologies.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.


/*icache_bank_private.sv*/

module icache_bank_private
#(
   parameter FETCH_ADDR_WIDTH = 32,
   parameter FETCH_DATA_WIDTH = 32,

   parameter NB_WAYS          = 4,
   parameter CACHE_SIZE       = 4096, // in Byte
   parameter CACHE_LINE       = 4,    // in word of [FETCH_DATA_WIDTH]

   parameter USE_REDUCED_TAG  = "TRUE",
   parameter TAG_BITS         = 9,

   parameter AXI_ID           = 10,
   parameter AXI_ADDR         = 32,
   parameter AXI_USER         = 1,
   parameter AXI_DATA         = 64
)
(
   input logic                                           clk,
   input logic                                           rst_n,
   input logic                                           test_en_i,

   // interface with processor
   input  logic                                          fetch_req_i,
   input  logic [FETCH_ADDR_WIDTH-1:0]                   fetch_addr_i,
   output logic                                          fetch_gnt_o,
   output logic                                          fetch_rvalid_o,
   output logic [FETCH_DATA_WIDTH-1:0]                   fetch_rdata_o,

   //AXI read address bus -------------------------------------------
   output  logic [AXI_ID-1:0]                            axi_master_arid_o,
   output  logic [AXI_ADDR-1:0]                          axi_master_araddr_o,
   output  logic [ 7:0]                                  axi_master_arlen_o,    //burst length - 1 to 16
   output  logic [ 2:0]                                  axi_master_arsize_o,   //size of each transfer in burst
   output  logic [ 1:0]                                  axi_master_arburst_o,  //for bursts>1, accept only incr burst=01
   output  logic                                         axi_master_arlock_o,   //only normal access supported axs_awlock=00
   output  logic [ 3:0]                                  axi_master_arcache_o,
   output  logic [ 2:0]                                  axi_master_arprot_o,
   output  logic [ 3:0]                                  axi_master_arregion_o, //
   output  logic [ AXI_USER-1:0]                         axi_master_aruser_o,   //
   output  logic [ 3:0]                                  axi_master_arqos_o,    //
   output  logic                                         axi_master_arvalid_o,  //master addr valid
   input logic                                           axi_master_arready_i,  //slave ready to accept
   // ---------------------------------------------------------------


   //AXI BACKWARD read data bus ----------------------------------------------
   input   logic [AXI_ID-1:0]                            axi_master_rid_i,
   input   logic [AXI_DATA-1:0]                          axi_master_rdata_i,
   input   logic [1:0]                                   axi_master_rresp_i,
   input   logic                                         axi_master_rlast_i,    //last transfer in burst
   input   logic [AXI_USER-1:0]                          axi_master_ruser_i,
   input   logic                                         axi_master_rvalid_i,   //slave data valid
   output  logic                                         axi_master_rready_o,    //master ready to accept

   // NOT USED ----------------------------------------------
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

   // NOT USED ----------------------------------------------
   output logic  [AXI_DATA-1:0]                          axi_master_wdata_o,
   output logic  [AXI_DATA/8-1:0]                        axi_master_wstrb_o,
   output logic                                          axi_master_wlast_o,
   output logic  [ AXI_USER-1:0]                         axi_master_wuser_o,
   output logic                                          axi_master_wvalid_o,
   input  logic                                          axi_master_wready_i,
   // ---------------------------------------------------------------

   // NOT USED ----------------------------------------------
   input  logic  [AXI_ID-1:0]                            axi_master_bid_i,
   input  logic  [ 1:0]                                  axi_master_bresp_i,
   input  logic  [ AXI_USER-1:0]                         axi_master_buser_i,
   input  logic                                          axi_master_bvalid_i,
   output logic                                          axi_master_bready_o,
   // ---------------------------------------------------------------

   input  logic                                          bypass_icache_i,
   output logic                                          cache_is_bypassed_o,
   input  logic                                          flush_icache_i,
   output logic                                          cache_is_flushed_o,
   input  logic                                          flush_set_ID_req_i,
   input  logic [FETCH_ADDR_WIDTH-1:0]                   flush_set_ID_addr_i,
   output logic                                          flush_set_ID_ack_o,

   output logic [31:0]                                   ctrl_hit_count_icache_o,
   output logic [31:0]                                   ctrl_trans_count_icache_o,
   output logic [31:0]                                   ctrl_miss_count_icache_o,
   input  logic                                          ctrl_clear_regs_icache_i,
   input  logic                                          ctrl_enable_regs_icache_i
);


   localparam OFFSET             = $clog2(FETCH_DATA_WIDTH)-3;
   localparam WAY_SIZE           = CACHE_SIZE/NB_WAYS;
   localparam SCM_NUM_ROWS       = WAY_SIZE/(CACHE_LINE*FETCH_DATA_WIDTH/8); // TAG
   localparam SCM_TAG_ADDR_WIDTH = (SCM_NUM_ROWS == 1 ) ? 1 : $clog2(SCM_NUM_ROWS);

   localparam TAG_WIDTH          = (USE_REDUCED_TAG == "TRUE") ? (TAG_BITS + 1) : (FETCH_ADDR_WIDTH -  $clog2(SCM_NUM_ROWS) - $clog2(CACHE_LINE) - OFFSET + 1);

   localparam DATA_WIDTH          = FETCH_DATA_WIDTH;
   localparam SCM_DATA_ADDR_WIDTH = $clog2(SCM_NUM_ROWS)+$clog2(CACHE_LINE);  // Because of 32 Access

   localparam SET_ID_LSB = $clog2(DATA_WIDTH*CACHE_LINE)-3;
   localparam SET_ID_MSB = (SCM_NUM_ROWS == 1) ? SET_ID_LSB :  SET_ID_LSB + SCM_TAG_ADDR_WIDTH - 1;
   localparam TAG_LSB    = (SCM_NUM_ROWS == 1) ? SET_ID_LSB :  SET_ID_MSB + 1;
   localparam TAG_MSB    = TAG_LSB + TAG_WIDTH - 2 ; //1 bit is count for valid

   logic [AXI_ID-1:0]                            axi_master_arid_int;
   logic [AXI_ADDR-1:0]                          axi_master_araddr_int;
   logic [ 7:0]                                  axi_master_arlen_int;
   logic [ 2:0]                                  axi_master_arsize_int;
   logic [ 1:0]                                  axi_master_arburst_int;
   logic                                         axi_master_arlock_int;
   logic [ 3:0]                                  axi_master_arcache_int;
   logic [ 2:0]                                  axi_master_arprot_int;
   logic [ 3:0]                                  axi_master_arregion_int;
   logic [ AXI_USER-1:0]                         axi_master_aruser_int;
   logic [ 3:0]                                  axi_master_arqos_int;
   logic                                         axi_master_arvalid_int;
   logic                                         axi_master_arready_int;


   logic [AXI_ID-1:0]                            axi_master_rid_int;
   logic [AXI_DATA-1:0]                          axi_master_rdata_int;
   logic [1:0]                                   axi_master_rresp_int;
   logic                                         axi_master_rlast_int;
   logic [AXI_USER-1:0]                          axi_master_ruser_int;
   logic                                         axi_master_rvalid_int;
   logic                                         axi_master_rready_int;



   // interface with READ PORT --> SCM DATA
   logic [NB_WAYS-1:0]                           DATA_req_int;
   logic                                         DATA_we_int;
   logic [SCM_DATA_ADDR_WIDTH-1:0]               DATA_addr_int;
   logic [NB_WAYS-1:0][DATA_WIDTH-1:0]           DATA_rdata_int;
   logic [DATA_WIDTH-1:0]                        DATA_wdata_int;

   // interface with READ PORT --> SCM TAG
   logic [NB_WAYS-1:0]                           TAG_req_int;
   logic                                         TAG_we_int;
   logic [SCM_TAG_ADDR_WIDTH-1:0]                TAG_addr_int;
   logic [NB_WAYS-1:0][TAG_WIDTH-1:0]            TAG_rdata_int;
   logic [TAG_WIDTH-1:0]                         TAG_wdata_int;


   logic [NB_WAYS-1:0]                           DATA_read_enable;
   logic [NB_WAYS-1:0]                           DATA_write_enable;

   logic [NB_WAYS-1:0]                           TAG_read_enable;
   logic [NB_WAYS-1:0]                           TAG_write_enable;

   // ██╗ ██████╗ █████╗  ██████╗██╗  ██╗███████╗         ██████╗████████╗██████╗ ██╗
   // ██║██╔════╝██╔══██╗██╔════╝██║  ██║██╔════╝        ██╔════╝╚══██╔══╝██╔══██╗██║
   // ██║██║     ███████║██║     ███████║█████╗          ██║        ██║   ██████╔╝██║
   // ██║██║     ██╔══██║██║     ██╔══██║██╔══╝          ██║        ██║   ██╔══██╗██║
   // ██║╚██████╗██║  ██║╚██████╗██║  ██║███████╗███████╗╚██████╗   ██║   ██║  ██║███████╗
   // ╚═╝ ╚═════╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚══════╝╚══════╝ ╚═════╝   ╚═╝   ╚═╝  ╚═╝╚══════╝
   icache_controller_private
   #(
      .FETCH_ADDR_WIDTH      ( FETCH_ADDR_WIDTH     ),
      .FETCH_DATA_WIDTH      ( FETCH_DATA_WIDTH     ),

      .NB_WAYS               ( NB_WAYS              ),
      .CACHE_LINE            ( CACHE_LINE           ),

      .SCM_TAG_ADDR_WIDTH    ( SCM_TAG_ADDR_WIDTH   ),
      .SCM_DATA_ADDR_WIDTH   ( SCM_DATA_ADDR_WIDTH  ),
      .SCM_TAG_WIDTH         ( TAG_WIDTH            ),
      .SCM_DATA_WIDTH        ( DATA_WIDTH           ),
      .SCM_NUM_ROWS          ( SCM_NUM_ROWS         ),

      .SET_ID_LSB            ( SET_ID_LSB           ),
      .SET_ID_MSB            ( SET_ID_MSB           ),
      .TAG_LSB               ( TAG_LSB              ),
      .TAG_MSB               ( TAG_MSB              ),

      .AXI_ID                ( AXI_ID               ),
      .AXI_ADDR              ( AXI_ADDR             ),
      .AXI_USER              ( AXI_USER             ),
      .AXI_DATA              ( AXI_DATA             )
   )
   i_icache_controller_private
   (
      .clk                      ( clk                  ),
      .rst_n                    ( rst_n                ),
      .test_en_i                ( test_en_i            ),

      .bypass_icache_i          ( bypass_icache_i      ),
      .cache_is_bypassed_o      ( cache_is_bypassed_o  ),
      .flush_icache_i           ( flush_icache_i       ),
      .cache_is_flushed_o       ( cache_is_flushed_o   ),
      .flush_set_ID_req_i       ( flush_set_ID_req_i   ),
      .flush_set_ID_addr_i      ( flush_set_ID_addr_i  ),
      .flush_set_ID_ack_o       ( flush_set_ID_ack_o   ),

      // interface with processor
      .fetch_req_i              ( fetch_req_i          ),
      .fetch_addr_i             ( fetch_addr_i         ),
      .fetch_gnt_o              ( fetch_gnt_o          ),
      .fetch_rvalid_o           ( fetch_rvalid_o       ),
      .fetch_rdata_o            ( fetch_rdata_o        ),


      // interface with READ PORT --> SCM DATA
      .DATA_req_o               ( DATA_req_int         ),
      .DATA_we_o                ( DATA_we_int          ),
      .DATA_addr_o              ( DATA_addr_int        ),
      .DATA_rdata_i             ( DATA_rdata_int       ),
      .DATA_wdata_o             ( DATA_wdata_int       ),

      // interface with READ PORT --> SCM TAG
      .TAG_req_o                ( TAG_req_int          ),
      .TAG_addr_o               ( TAG_addr_int         ),
      .TAG_rdata_i              ( TAG_rdata_int        ),
      .TAG_wdata_o              ( TAG_wdata_int        ),
      .TAG_we_o                 ( TAG_we_int           ),

      // Interface to cache_controller_to_axi
      .axi_ar_valid_o           ( axi_master_arvalid_int ),
      .axi_ar_ready_i           ( axi_master_arready_int ),
      .axi_ar_addr_o            ( axi_master_araddr_int  ),
      .axi_ar_len_o             ( axi_master_arlen_int   ),

      .axi_r_valid_i            ( axi_master_rvalid_int  ),
      .axi_r_ready_o            ( axi_master_rready_int  ),
      .axi_r_data_i             ( axi_master_rdata_int   ),
      .axi_r_last_i             ( axi_master_rlast_int   ),

      .ctrl_hit_count_icache_o  (ctrl_hit_count_icache_o   ),
      .ctrl_trans_count_icache_o(ctrl_trans_count_icache_o ),
      .ctrl_miss_count_icache_o (ctrl_miss_count_icache_o  ),
      .ctrl_clear_regs_icache_i (ctrl_clear_regs_icache_i  ),
      .ctrl_enable_regs_icache_i(ctrl_enable_regs_icache_i )
   );



      genvar i;
      generate

      // ████████╗ █████╗  ██████╗         ██████╗  █████╗ ███╗   ██╗██╗  ██╗
      // ╚══██╔══╝██╔══██╗██╔════╝         ██╔══██╗██╔══██╗████╗  ██║██║ ██╔╝
      //    ██║   ███████║██║  ███╗        ██████╔╝███████║██╔██╗ ██║█████╔╝
      //    ██║   ██╔══██║██║   ██║        ██╔══██╗██╔══██║██║╚██╗██║██╔═██╗
      //    ██║   ██║  ██║╚██████╔╝███████╗██████╔╝██║  ██║██║ ╚████║██║  ██╗
      //    ╚═╝   ╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝
      for(i=0; i<NB_WAYS; i++)
      begin : _TAG_WAY_
         assign TAG_read_enable[i]  = TAG_req_int[i] & ~TAG_we_int;
         assign TAG_write_enable[i] = TAG_req_int[i] &  TAG_we_int;


      `ifdef PULP_FPGA_EMUL
         register_file_1r_1w
      `else
           register_file_1r_1w_test_wrap
      `endif
             #(
               .ADDR_WIDTH  ( SCM_TAG_ADDR_WIDTH ),
               .DATA_WIDTH  ( TAG_WIDTH          )
               )
         TAG_BANK
           (
            .clk         ( clk          ),
      `ifdef PULP_FPGA_EMUL
            .rst_n       ( rst_n        ),
      `endif

            // Read port
            .ReadEnable  ( TAG_read_enable[i]  ),
            .ReadAddr    ( TAG_addr_int        ),
            .ReadData    ( TAG_rdata_int[i]    ),

            // Write port
            .WriteEnable ( TAG_write_enable[i] ),
            .WriteAddr   ( TAG_addr_int        ),
            .WriteData   ( TAG_wdata_int       )
      `ifndef PULP_FPGA_EMUL
            ,
            // BIST ENABLE
            .BIST        ( 1'b0                ), // PLEASE CONNECT ME;

            // BIST ports
            .CSN_T       (                     ), // PLEASE CONNECT ME; Synthesis will remove me if unconnected
            .WEN_T       (                     ), // PLEASE CONNECT ME; Synthesis will remove me if unconnected
            .A_T         (                     ), // PLEASE CONNECT ME; Synthesis will remove me if unconnected
            .D_T         (                     ), // PLEASE CONNECT ME; Synthesis will remove me if unconnected
            .Q_T         (                     )
      `endif
            );
      end

      // ██████╗  █████╗ ████████╗ █████╗         ██████╗  █████╗ ███╗   ██╗██╗  ██╗
      // ██╔══██╗██╔══██╗╚══██╔══╝██╔══██╗        ██╔══██╗██╔══██╗████╗  ██║██║ ██╔╝
      // ██║  ██║███████║   ██║   ███████║        ██████╔╝███████║██╔██╗ ██║█████╔╝
      // ██║  ██║██╔══██║   ██║   ██╔══██║        ██╔══██╗██╔══██║██║╚██╗██║██╔═██╗
      // ██████╔╝██║  ██║   ██║   ██║  ██║███████╗██████╔╝██║  ██║██║ ╚████║██║  ██╗
      // ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝╚══════╝╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝


      for(i=0; i<NB_WAYS; i++)
      begin : _DATA_WAY_
         assign DATA_read_enable[i]  = DATA_req_int[i] & ~DATA_we_int;
         assign DATA_write_enable[i] = DATA_req_int[i] & DATA_we_int;

     `ifdef PULP_FPGA_EMUL
         register_file_1r_1w
     `else
         register_file_1r_1w_test_wrap
     `endif
         #(
           .ADDR_WIDTH  ( SCM_DATA_ADDR_WIDTH ),
           .DATA_WIDTH  ( DATA_WIDTH         )
           )
           DATA_BANK
           (
            .clk         ( clk          ),
     `ifdef PULP_FPGA_EMUL
            .rst_n       ( rst_n        ),
     `endif

            // Read port
            .ReadEnable  ( DATA_read_enable[i]   ),
            .ReadAddr    ( DATA_addr_int         ),
            .ReadData    ( DATA_rdata_int[i]     ),

            // Write port
            .WriteEnable ( DATA_write_enable[i]  ),
            .WriteAddr   ( DATA_addr_int         ),
            .WriteData   ( DATA_wdata_int        )
     `ifndef PULP_FPGA_EMUL
            ,
            // BIST ENABLE
            .BIST        ( 1'b0                ), // PLEASE CONNECT ME;

            // BIST ports
            .CSN_T       (                     ), // PLEASE CONNECT ME; Synthesis will remove me if unconnected
            .WEN_T       (                     ), // PLEASE CONNECT ME; Synthesis will remove me if unconnected
            .A_T         (                     ), // PLEASE CONNECT ME; Synthesis will remove me if unconnected
            .D_T         (                     ), // PLEASE CONNECT ME; Synthesis will remove me if unconnected
            .Q_T         (                     )
     `endif
            );
      end
endgenerate



   assign axi_master_arid_int     = {AXI_ID{1'b0}};
   assign axi_master_arsize_int   = 3'b011;   //64 bits -> 8 bytes
   assign axi_master_arburst_int  = 2'b01;    //INCR
   assign axi_master_arlock_int   = 1'b0;
   assign axi_master_arcache_int  = 4'b0000;
   assign axi_master_arprot_int   = 3'b000;
   assign axi_master_arregion_int = 4'b0000;
   assign axi_master_aruser_int   = {AXI_USER{1'b0}};
   assign axi_master_arqos_int    = 4'b0000;


   //  █████╗ ██╗  ██╗██╗         █████╗ ██████╗         ██████╗ ██╗   ██╗███████╗███████╗
   // ██╔══██╗╚██╗██╔╝██║        ██╔══██╗██╔══██╗        ██╔══██╗██║   ██║██╔════╝██╔════╝
   // ███████║ ╚███╔╝ ██║        ███████║██████╔╝        ██████╔╝██║   ██║█████╗  █████╗
   // ██╔══██║ ██╔██╗ ██║        ██╔══██║██╔══██╗        ██╔══██╗██║   ██║██╔══╝  ██╔══╝
   // ██║  ██║██╔╝ ██╗██║███████╗██║  ██║██║  ██║███████╗██████╔╝╚██████╔╝██║     ██║
   // ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═════╝  ╚═════╝ ╚═╝     ╚═╝
   axi_ar_buffer
   #(
      .ID_WIDTH     ( AXI_ID      ),
      .ADDR_WIDTH   ( AXI_ADDR    ),
      .USER_WIDTH   ( AXI_USER    ),
      .BUFFER_DEPTH ( 2           )
   )
   i_AXI_AR_BUFFER
   (
      .clk_i           ( clk                                 ),
      .rst_ni          ( rst_n                               ),
      .test_en_i       ( test_en_i                           ),

      .slave_valid_i   ( axi_master_arvalid_int              ),
      .slave_addr_i    ( axi_master_araddr_int               ),
      .slave_prot_i    ( axi_master_arprot_int               ),
      .slave_region_i  ( axi_master_arregion_int             ),
      .slave_len_i     ( axi_master_arlen_int                ),
      .slave_size_i    ( axi_master_arsize_int               ),
      .slave_burst_i   ( axi_master_arburst_int              ),
      .slave_lock_i    ( axi_master_arlock_int               ),
      .slave_cache_i   ( axi_master_arcache_int              ),
      .slave_qos_i     ( axi_master_arqos_int                ),
      .slave_id_i      ( axi_master_arid_int[AXI_ID-1:0]     ),
      .slave_user_i    ( axi_master_aruser_int               ),
      .slave_ready_o   ( axi_master_arready_int              ),

      .master_valid_o  ( axi_master_arvalid_o                ),
      .master_addr_o   ( axi_master_araddr_o                 ),
      .master_prot_o   ( axi_master_arprot_o                 ),
      .master_region_o ( axi_master_arregion_o               ),
      .master_len_o    ( axi_master_arlen_o                  ),
      .master_size_o   ( axi_master_arsize_o                 ),
      .master_burst_o  ( axi_master_arburst_o                ),
      .master_lock_o   ( axi_master_arlock_o                 ),
      .master_cache_o  ( axi_master_arcache_o                ),
      .master_qos_o    ( axi_master_arqos_o                  ),
      .master_id_o     ( axi_master_arid_o[AXI_ID-1:0]       ),
      .master_user_o   ( axi_master_aruser_o                 ),
      .master_ready_i  ( axi_master_arready_i                )
   );

   //  █████╗ ██╗  ██╗██╗        ██████╗         ██████╗ ██╗   ██╗███████╗███████╗
   // ██╔══██╗╚██╗██╔╝██║        ██╔══██╗        ██╔══██╗██║   ██║██╔════╝██╔════╝
   // ███████║ ╚███╔╝ ██║        ██████╔╝        ██████╔╝██║   ██║█████╗  █████╗
   // ██╔══██║ ██╔██╗ ██║        ██╔══██╗        ██╔══██╗██║   ██║██╔══╝  ██╔══╝
   // ██║  ██║██╔╝ ██╗██║███████╗██║  ██║███████╗██████╔╝╚██████╔╝██║     ██║
   // ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝╚══════╝╚═╝  ╚═╝╚══════╝╚═════╝  ╚═════╝ ╚═╝     ╚═╝
   axi_r_buffer
      #(
      .ID_WIDTH       ( AXI_ID                             ),
      .DATA_WIDTH     ( AXI_DATA                           ),
      .USER_WIDTH     ( AXI_USER                           ),
      .BUFFER_DEPTH   ( 2                                  )
   )
   i_AXI_R_BUFFER
   (
      .clk_i          ( clk                                ),
      .rst_ni         ( rst_n                              ),
      .test_en_i      ( test_en_i                          ),

      .slave_valid_i  ( axi_master_rvalid_i                ),
      .slave_data_i   ( axi_master_rdata_i                 ),
      .slave_resp_i   ( axi_master_rresp_i                 ),
      .slave_user_i   ( axi_master_ruser_i                 ),
      .slave_id_i     ( axi_master_rid_i[AXI_ID-1:0]       ),
      .slave_last_i   ( axi_master_rlast_i                 ),
      .slave_ready_o  ( axi_master_rready_o                ),

      .master_valid_o ( axi_master_rvalid_int              ),
      .master_data_o  ( axi_master_rdata_int               ),
      .master_resp_o  ( axi_master_rresp_int               ),
      .master_user_o  ( axi_master_ruser_int               ),
      .master_id_o    ( axi_master_rid_int[AXI_ID-1:0]     ),
      .master_last_o  ( axi_master_rlast_int               ),
      .master_ready_i ( axi_master_rready_int              )
   );


   assign axi_master_awid_o     = {AXI_ID{1'b0}};
   assign axi_master_awaddr_o   = {AXI_ADDR{1'b0}};
   assign axi_master_awlen_o    = 8'b0000_0000;
   assign axi_master_awsize_o   = 3'b000;
   assign axi_master_awburst_o  = 2'b00;
   assign axi_master_awlock_o   = 1'b0;
   assign axi_master_awcache_o  = 4'b0000;
   assign axi_master_awprot_o   = 3'b000;
   assign axi_master_awregion_o = 4'b0000;
   assign axi_master_awuser_o   = {AXI_USER{1'b0}};
   assign axi_master_awqos_o    = 4'b0000;
   assign axi_master_awvalid_o  = 1'b0;

   assign axi_master_wdata_o    = {AXI_DATA{1'b0}};
   assign axi_master_wstrb_o    = {AXI_DATA/8{1'b0}};;
   assign axi_master_wlast_o    = 1'b0;
   assign axi_master_wuser_o    =  {AXI_USER{1'b0}};
   assign axi_master_wvalid_o   = 1'b0;

   assign axi_master_bready_o   = 1'b0;
endmodule // top_icache_bank
