// Copyright 2018 ETH Zurich, University of Bologna and Greenwaves Technologies.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.





`timescale  1ns/1ps

module testbench();
   parameter AXI_DATA         = 64;
   parameter AXI_ADDR         = 32;
   parameter AXI_ID           = 7;
   parameter AXI_USER         = 4;

   parameter FETCH_ADDR_WIDTH = 32;
   parameter FETCH_DATA_WIDTH = 32;

   parameter NB_WAYS          = 1;
   parameter NB_BANKS         = 1;
   parameter CACHE_SIZE       = 128*1024;
   parameter CACHE_LINE       = 2;

   parameter L2_ADDR_WIDTH    = 20;


   logic                           clk;
   logic                           rst_n;
   logic                           test_en_i;

   logic                          fetch_req_int;
   logic [FETCH_ADDR_WIDTH-1:0]   fetch_addr_int;
   logic                          fetch_gnt_int;
   logic                          fetch_rvalid_int;
   logic [FETCH_DATA_WIDTH-1:0]   fetch_rdata_int;


   // Signals from fc_icache to L2 memory (just a memory with random grant)
   logic                           bypass_icache;
   logic                           cache_is_bypassed;
   logic                           flush_icache;
   logic                           icache_is_flushed;
   logic                           flush_address_req;
   logic                           flush_address_ack;
  
   logic                           flush_set_ID_req;
   logic [31:0]                    flush_set_ID_addr;
   logic                           flush_set_ID_ack;

   logic [31:0]                    ctrl_hit_count_icache;
   logic [31:0]                    ctrl_trans_count_icache;
   logic                           ctrl_clear_regs_icache;
   logic                           ctrl_enable_regs_icache;



   logic [AXI_ID-1:0]          axi_master_arid_int     ;
   logic [AXI_ADDR-1:0]        axi_master_araddr_int   ;
   logic [ 7:0]                axi_master_arlen_int    ;
   logic [ 2:0]                axi_master_arsize_int   ;
   logic [ 1:0]                axi_master_arburst_int  ;
   logic                       axi_master_arlock_int   ;
   logic [ 3:0]                axi_master_arcache_int  ;
   logic [ 2:0]                axi_master_arprot_int   ;
   logic [ 3:0]                axi_master_arregion_int ;
   logic [ AXI_USER-1:0]       axi_master_aruser_int   ;
   logic [ 3:0]                axi_master_arqos_int    ;
   logic                       axi_master_arvalid_int  ;
   logic                       axi_master_arready_int  ;

   logic [AXI_ID-1:0]          axi_master_rid_int      ;
   logic [AXI_DATA-1:0]        axi_master_rdata_int    ;
   logic [1:0]                 axi_master_rresp_int    ;
   logic                       axi_master_rlast_int    ;
   logic [AXI_USER-1:0]        axi_master_ruser_int    ;
   logic                       axi_master_rvalid_int   ;
   logic                       axi_master_rready_int   ;

   logic [AXI_ID-1:0]          axi_master_awid_int    ; 
   logic [AXI_ADDR-1:0]        axi_master_awaddr_int  ; 
   logic [ 7:0]                axi_master_awlen_int   ; 
   logic [ 2:0]                axi_master_awsize_int  ; 
   logic [ 1:0]                axi_master_awburst_int ; 
   logic                       axi_master_awlock_int  ; 
   logic [ 3:0]                axi_master_awcache_int ; 
   logic [ 2:0]                axi_master_awprot_int  ; 
   logic [ 3:0]                axi_master_awregion_int; 
   logic [ AXI_USER-1:0]       axi_master_awuser_int  ; 
   logic [ 3:0]                axi_master_awqos_int   ; 
   logic                       axi_master_awvalid_int ; 
   logic                       axi_master_awready_int ;

   logic  [AXI_DATA-1:0]       axi_master_wdata_int  ;                  
   logic  [AXI_DATA/8-1:0]     axi_master_wstrb_int  ;                  
   logic                       axi_master_wlast_int  ;                  
   logic  [ AXI_USER-1:0]      axi_master_wuser_int  ;                  
   logic                       axi_master_wvalid_int ;                  
   logic                       axi_master_wready_int ;  

   logic  [AXI_ID-1:0]         axi_master_bid_int    ;                  
   logic  [ 1:0]               axi_master_bresp_int  ;                  
   logic  [ AXI_USER-1:0]      axi_master_buser_int  ;                  
   logic                       axi_master_bvalid_int ;                  
   logic                       axi_master_bready_int ;                  

   logic                       mem_csn;  
   logic                       mem_wen;  
   logic [L2_ADDR_WIDTH-1:0]   mem_add;
   logic [63:0]                mem_wdata;
   logic [7:0]                 mem_be;   
   logic [63:0]                mem_rdata;


   logic [FETCH_DATA_WIDTH-1:0]  instr_r_rdata_L2_to_check;

   always
   begin
      #1.0;
      clk <= ~clk;
   end

   initial
   begin
      bypass_icache <= 1;
      flush_icache  <= 0;
      flush_set_ID_req  <= '0;
      flush_set_ID_addr <= '0;
      
      ctrl_enable_regs_icache <= 1'b0;
      clk       <= '0;
      rst_n     <= 1'b1;
      test_en_i <= 1'b0;
      ctrl_clear_regs_icache <= 1'b0;
      @(negedge clk);
      @(negedge clk);
      rst_n     <= 1'b0;
      ctrl_clear_regs_icache <= 1'b1;
      @(negedge clk);
      @(negedge clk);
      @(negedge clk);
      @(negedge clk);
      rst_n     <= 1'b1;
      ctrl_clear_regs_icache <= 1'b0;

      
      
      #(100000);
      @(negedge clk);
      bypass_icache <= ~bypass_icache;
      ctrl_enable_regs_icache <= 1'b1;
      #(100000);
      @(negedge clk);
      ctrl_enable_regs_icache <= 1'b0;
      
      $display("NUMBER TOTAL TRANS = %d", ctrl_trans_count_icache );
      $display("NUMBER HIT   TRANS = %d", ctrl_hit_count_icache );

      $stop();
   end


   // ████████╗ ██████╗ ███████╗███╗   ██╗
   // ╚══██╔══╝██╔════╝ ██╔════╝████╗  ██║
   //    ██║   ██║  ███╗█████╗  ██╔██╗ ██║
   //    ██║   ██║   ██║██╔══╝  ██║╚██╗██║
   //    ██║   ╚██████╔╝███████╗██║ ╚████║
   //    ╚═╝    ╚═════╝ ╚══════╝╚═╝  ╚═══╝
   tgen_emu
   #(
      .FETCH_ADDR_WIDTH (FETCH_ADDR_WIDTH),
      .FETCH_DATA_WIDTH (FETCH_DATA_WIDTH)
   )
   CORE
   (
      .clk            (clk               ),
      .rst_n          (rst_n             ),

      .fetch_req_o    (fetch_req_int     ),
      .fetch_addr_o   (fetch_addr_int    ),
      .fetch_gnt_i    (fetch_gnt_int     ),
      .fetch_rvalid_i (fetch_rvalid_int  ),
      .fetch_rdata_i  (fetch_rdata_int   )
   );

   // application code is loaded in this dummy L2_MEMORY
   ibus_lint_memory
   #(
      .addr_width      ( L2_ADDR_WIDTH                      )
   )
   L2_MEMORY_CHECK
   (
      .clk             ( clk                                ),
      .rst_n           ( rst_n                              ),

      .lint_req_i      ( fetch_req_int &  fetch_gnt_int     ),
      .lint_grant_o    (                                    ),
      .lint_addr_i     ( fetch_addr_int[L2_ADDR_WIDTH+1:2]  ), 

      .lint_r_rdata_o  ( instr_r_rdata_L2_to_check          ),
      .lint_r_valid_o  (                                    )
   );


   // assertion to check fetch correctness
   always @(posedge clk)
   begin
      if(fetch_rvalid_int)
      begin
         if(fetch_rdata_int !== instr_r_rdata_L2_to_check)
         begin
            $error("Error on CORE FETCH INTERFACE: Expected %h, Got %h", instr_r_rdata_L2_to_check, fetch_rdata_int );
            $stop();
         end
      end
   end



   // ███████╗ ██████╗        ██╗ ██████╗ █████╗  ██████╗██╗  ██╗███████╗
   // ██╔════╝██╔════╝        ██║██╔════╝██╔══██╗██╔════╝██║  ██║██╔════╝
   // █████╗  ██║             ██║██║     ███████║██║     ███████║█████╗  
   // ██╔══╝  ██║             ██║██║     ██╔══██║██║     ██╔══██║██╔══╝  
   // ██║     ╚██████╗███████╗██║╚██████╗██║  ██║╚██████╗██║  ██║███████╗
   // ╚═╝      ╚═════╝╚══════╝╚═╝ ╚═════╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚══════╝                                                                 
   icache_bank_private
   #(
      .FETCH_ADDR_WIDTH      ( FETCH_ADDR_WIDTH      ), //32,
      .FETCH_DATA_WIDTH      ( FETCH_DATA_WIDTH      ), //128,

      .NB_BANKS              ( NB_BANKS              ),
      .NB_WAYS               ( NB_WAYS               ), //4,
      .CACHE_SIZE            ( CACHE_SIZE            ), //4096, // in Byte
      .CACHE_LINE            ( CACHE_LINE            ), //1     // in word of [FETCH_DATA_WIDTH]

      .AXI_ID                ( AXI_ID                ), // 10,
      .AXI_ADDR              ( AXI_ADDR              ), // 32,
      .AXI_USER              ( AXI_USER              ), // 1,
      .AXI_DATA              ( AXI_DATA              )  // 64
   )
   icache_bank_private_i
   (
      .clk                   ( clk                     ),
      .rst_n                 ( rst_n                   ),
      .test_en_i             ( test_en_i               ),

      // interface with processors
      .fetch_req_i           ( fetch_req_int           ),
      .fetch_addr_i          ( fetch_addr_int          ),
      .fetch_gnt_o           ( fetch_gnt_int           ),
      .fetch_rvalid_o        ( fetch_rvalid_int        ),
      .fetch_rdata_o         ( fetch_rdata_int         ),

      .axi_master_arid_o     ( axi_master_arid_int     ),
      .axi_master_araddr_o   ( axi_master_araddr_int   ),
      .axi_master_arlen_o    ( axi_master_arlen_int    ),
      .axi_master_arsize_o   ( axi_master_arsize_int   ),
      .axi_master_arburst_o  ( axi_master_arburst_int  ),
      .axi_master_arlock_o   ( axi_master_arlock_int   ),
      .axi_master_arcache_o  ( axi_master_arcache_int  ),
      .axi_master_arprot_o   ( axi_master_arprot_int   ),
      .axi_master_arregion_o ( axi_master_arregion_int ),
      .axi_master_aruser_o   ( axi_master_aruser_int   ),
      .axi_master_arqos_o    ( axi_master_arqos_int    ),
      .axi_master_arvalid_o  ( axi_master_arvalid_int  ),
      .axi_master_arready_i  ( axi_master_arready_int  ),

      .axi_master_rid_i      ( axi_master_rid_int      ),
      .axi_master_rdata_i    ( axi_master_rdata_int    ),
      .axi_master_rresp_i    ( axi_master_rresp_int    ),
      .axi_master_rlast_i    ( axi_master_rlast_int    ),
      .axi_master_ruser_i    ( axi_master_ruser_int    ),
      .axi_master_rvalid_i   ( axi_master_rvalid_int   ),
      .axi_master_rready_o   ( axi_master_rready_int   ),

      .axi_master_awid_o     ( axi_master_awid_int     ),
      .axi_master_awaddr_o   ( axi_master_awaddr_int   ),
      .axi_master_awlen_o    ( axi_master_awlen_int    ),
      .axi_master_awsize_o   ( axi_master_awsize_int   ),
      .axi_master_awburst_o  ( axi_master_awburst_int  ),
      .axi_master_awlock_o   ( axi_master_awlock_int   ),
      .axi_master_awcache_o  ( axi_master_awcache_int  ),
      .axi_master_awprot_o   ( axi_master_awprot_int   ),
      .axi_master_awregion_o ( axi_master_awregion_int ),
      .axi_master_awuser_o   ( axi_master_awuser_int   ),
      .axi_master_awqos_o    ( axi_master_awqos_int    ),
      .axi_master_awvalid_o  ( axi_master_awvalid_int  ),
      .axi_master_awready_i  ( axi_master_awready_int  ),

      .axi_master_wdata_o    ( axi_master_wdata_int    ),
      .axi_master_wstrb_o    ( axi_master_wstrb_int    ),
      .axi_master_wlast_o    ( axi_master_wlast_int    ),
      .axi_master_wuser_o    ( axi_master_wuser_int    ),
      .axi_master_wvalid_o   ( axi_master_wvalid_int   ),
      .axi_master_wready_i   ( axi_master_wready_int   ),

      .axi_master_bid_i      (  axi_master_bid_int     ),
      .axi_master_bresp_i    (  axi_master_bresp_int   ),
      .axi_master_buser_i    (  axi_master_buser_int   ),
      .axi_master_bvalid_i   (  axi_master_bvalid_int  ),
      .axi_master_bready_o   (  axi_master_bready_int  ),

      .bypass_icache_i       ( bypass_icache           ),
      .cache_is_bypassed_o   ( cache_is_bypassed       ),
      .flush_icache_i        ( flush_icache            ),
      .cache_is_flushed_o    ( icache_is_flushed       ),
      .flush_set_ID_req_i    ( flush_set_ID_req        ),
      .flush_set_ID_addr_i   ( flush_set_ID_addr       ),
      .flush_set_ID_ack_o    ( flush_set_ID_ack        ),

      .ctrl_hit_count_icache_o    (ctrl_hit_count_icache   ),
      .ctrl_trans_count_icache_o  (ctrl_trans_count_icache ),
      .ctrl_clear_regs_icache_i   (ctrl_clear_regs_icache  ),
      .ctrl_enable_regs_icache_i  (ctrl_enable_regs_icache )
   );

   axi_mem_if
   #(
       .AXI4_ADDRESS_WIDTH ( AXI_ADDR   ),
       .AXI4_RDATA_WIDTH   ( AXI_DATA      ),
       .AXI4_WDATA_WIDTH   ( AXI_DATA      ),
       .AXI4_ID_WIDTH      ( AXI_ID        ),
       .AXI4_USER_WIDTH    ( AXI_USER      ),
       .MEM_ADDR_WIDTH     ( L2_ADDR_WIDTH       ),
       .BUFF_DEPTH_SLAVE   ( 2    )
   )
   axi_mem_if_i
   (
       .ACLK               ( clk                 ),
       .ARESETn            ( rst_n               ),
       .test_en_i          ( test_en_i           ),

       .AWVALID_i          ( axi_master_awvalid_int  ),
       .AWADDR_i           ( axi_master_awaddr_int   ),
       .AWPROT_i           ( axi_master_awprot_int   ),
       .AWREGION_i         ( axi_master_awregion_int ),
       .AWLEN_i            ( axi_master_awlen_int    ),
       .AWSIZE_i           ( axi_master_awsize_int   ),
       .AWBURST_i          ( axi_master_awburst_int  ),
       .AWLOCK_i           ( axi_master_awlock_int   ),
       .AWCACHE_i          ( axi_master_awcache_int  ),
       .AWQOS_i            ( axi_master_awqos_int    ),
       .AWID_i             ( axi_master_awid_int     ),
       .AWUSER_i           ( axi_master_awuser_int   ),
       .AWREADY_o          ( axi_master_awready_int  ),

       .ARVALID_i          ( axi_master_arvalid_int  ),
       .ARADDR_i           ( axi_master_araddr_int   ),
       .ARPROT_i           ( axi_master_arprot_int   ),
       .ARREGION_i         ( axi_master_arregion_int ),
       .ARLEN_i            ( axi_master_arlen_int    ),
       .ARSIZE_i           ( axi_master_arsize_int   ),
       .ARBURST_i          ( axi_master_arburst_int  ),
       .ARLOCK_i           ( axi_master_arlock_int   ),
       .ARCACHE_i          ( axi_master_arcache_int  ),
       .ARQOS_i            ( axi_master_arqos_int    ),
       .ARID_i             ( axi_master_arid_int     ),
       .ARUSER_i           ( axi_master_aruser_int   ),
       .ARREADY_o          ( axi_master_arready_int  ),

       .RVALID_o           ( axi_master_rvalid_int   ),
       .RDATA_o            ( axi_master_rdata_int    ),
       .RRESP_o            ( axi_master_rresp_int    ),
       .RLAST_o            ( axi_master_rlast_int    ),
       .RID_o              ( axi_master_rid_int      ),
       .RUSER_o            ( axi_master_ruser_int    ),
       .RREADY_i           ( axi_master_rready_int   ),

       .WVALID_i           ( axi_master_wvalid_int   ),
       .WDATA_i            ( axi_master_wdata_int    ),
       .WSTRB_i            ( axi_master_wstrb_int    ),
       .WLAST_i            ( axi_master_wlast_int    ),
       .WUSER_i            ( axi_master_wuser_int    ),
       .WREADY_o           ( axi_master_wready_int   ),

       .BVALID_o           ( axi_master_bvalid_int   ),
       .BRESP_o            ( axi_master_bresp_int    ),
       .BID_o              ( axi_master_bid_int      ),
       .BUSER_o            ( axi_master_buser_int    ),
       .BREADY_i           ( axi_master_bready_int   ),

       .CEN                ( mem_csn      ),
       .WEN                ( mem_wen      ),
       .A                  ( mem_add[L2_ADDR_WIDTH-1:0]),
       .D                  ( mem_wdata    ),
       .BE                 ( mem_be       ),
       .Q                  ( mem_rdata    )
   );


   l2_generic 
   #(
      .ADDR_WIDTH (L2_ADDR_WIDTH)
   )
   l2_mem_i
   (
      .CLK   ( clk                        ),
      .RSTN  ( rst_n                      ),
      .D     ( mem_wdata                  ),
      .A     ( mem_add[L2_ADDR_WIDTH-1:0] ),
      .CEN   ( mem_csn                    ),
      .WEN   ( mem_wen                    ),
      .BE    ( mem_be                     ),
      .Q     ( mem_rdata                  )
   );


endmodule // testbench
