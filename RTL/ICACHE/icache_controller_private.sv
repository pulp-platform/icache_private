// Copyright 2018 ETH Zurich, University of Bologna and Greenwaves Technologies.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.


/*icache_controller_private.sv */



`define USE_REQ_BUFFER
`define log2_non_zero(VALUE) ((VALUE) < ( 1 ) ? 1 : (VALUE) < ( 2 ) ? 1 : (VALUE) < ( 4 ) ? 2 : (VALUE)< (8) ? 3:(VALUE) < ( 16 )  ? 4 : (VALUE) < ( 32 )  ? 5 : (VALUE) < ( 64 )  ? 6 : (VALUE) < ( 128 ) ? 7 : (VALUE) < ( 256 ) ? 8 : (VALUE) < ( 512 ) ? 9 : 10)

module icache_controller_private
#(
   parameter FETCH_ADDR_WIDTH = 32,
   parameter FETCH_DATA_WIDTH = 32,

   parameter NB_WAYS         = 4,
   parameter CACHE_LINE      = 4,

   parameter SCM_TAG_ADDR_WIDTH   = 4,
   parameter SCM_DATA_ADDR_WIDTH  = 6,
   parameter SCM_TAG_WIDTH        = 8,
   parameter SCM_DATA_WIDTH       = 128,
   parameter SCM_NUM_ROWS         = 2**SCM_TAG_ADDR_WIDTH,


   parameter SET_ID_LSB      = $clog2(SCM_DATA_WIDTH*CACHE_LINE)-3,
   parameter SET_ID_MSB      = SET_ID_LSB + SCM_TAG_ADDR_WIDTH - 1,
   parameter TAG_LSB         = SET_ID_MSB + 1,
   parameter TAG_MSB         = TAG_LSB + SCM_TAG_WIDTH - 2,

   parameter AXI_ID          = 4,
   parameter AXI_ADDR        = FETCH_ADDR_WIDTH,
   parameter AXI_USER        = 6,
   parameter AXI_DATA        = 64
)
(
   input logic                                              clk,
   input logic                                              rst_n,
   input logic                                              test_en_i,

   input  logic                                             bypass_icache_i,
   output logic                                             cache_is_bypassed_o,
   input  logic                                             flush_icache_i,
   output logic                                             cache_is_flushed_o,
   input  logic                                             flush_set_ID_req_i,
   input  logic [FETCH_ADDR_WIDTH-1:0]                      flush_set_ID_addr_i,
   output logic                                             flush_set_ID_ack_o,

   // interface with processor
   input  logic                                             fetch_req_i,
   input  logic [FETCH_ADDR_WIDTH-1:0]                      fetch_addr_i,
   output logic                                             fetch_gnt_o,
   output logic                                             fetch_rvalid_o,
   output logic [FETCH_DATA_WIDTH-1:0]                      fetch_rdata_o,


   // interface with READ PORT --> SCM DATA
   output logic [NB_WAYS-1:0]                               DATA_req_o,
   output logic                                             DATA_we_o,
   output logic [SCM_DATA_ADDR_WIDTH-1:0]                   DATA_addr_o,
   input  logic [NB_WAYS-1:0][SCM_DATA_WIDTH-1:0]           DATA_rdata_i,
   output logic [FETCH_DATA_WIDTH-1:0]                      DATA_wdata_o,

   // interface with READ PORT --> SCM TAG
   output logic [NB_WAYS-1:0]                               TAG_req_o,
   output logic [SCM_TAG_ADDR_WIDTH-1:0]                    TAG_addr_o,
   input  logic [NB_WAYS-1:0][SCM_TAG_WIDTH-1:0]            TAG_rdata_i,
   output logic [SCM_TAG_WIDTH-1:0]                         TAG_wdata_o,
   output logic                                             TAG_we_o,



   // Interface to cache_controller_to_axi
   output logic                                             axi_ar_valid_o,
   input  logic                                             axi_ar_ready_i,
   output logic [AXI_ADDR-1:0]                              axi_ar_addr_o,
   output logic [7:0]                                       axi_ar_len_o,

   input  logic                                             axi_r_valid_i,
   output logic                                             axi_r_ready_o,
   input  logic [AXI_DATA-1:0]                              axi_r_data_i,
   input  logic                                             axi_r_last_i,

   output logic [31:0]                                      ctrl_hit_count_icache_o,
   output logic [31:0]                                      ctrl_trans_count_icache_o,
   output logic [31:0]                                      ctrl_miss_count_icache_o,
   input  logic                                             ctrl_clear_regs_icache_i,
   input  logic                                             ctrl_enable_regs_icache_i
);


   localparam OFFSET     = $clog2(SCM_DATA_WIDTH*CACHE_LINE)-3;


   logic [FETCH_ADDR_WIDTH-1:0]                    fetch_addr_Q;
   logic                                           fetch_req_Q;
   logic [NB_WAYS-1:0]                             fetch_way_Q;

   logic                                           save_pipe_status;
   logic                                           clear_pipe;
   logic                                           enable_pipe;
   logic                                           save_fetch_way;


   logic [SCM_TAG_ADDR_WIDTH-1:0] counter_FLUSH_NS, counter_FLUSH_CS;

   logic [NB_WAYS-1:0]                    way_match;
   logic [NB_WAYS-1:0]                    way_valid;
   logic [NB_WAYS-1:0]                    way_match_bin;

   logic [NB_WAYS-1:0]                    way_valid_Q;

   logic [NB_WAYS-1:0]                    random_way;
   logic [$clog2(NB_WAYS)-1:0]            first_available_way;
   logic [NB_WAYS-1:0]                    first_available_way_OH;

   logic [$clog2(NB_WAYS)-1:0]            HIT_WAY;
   logic                                  pending_trans_dis_cache;

   logic [FETCH_DATA_WIDTH-1:0]    axi_r_data_int;
   logic [AXI_DATA-1:0]            axi_r_data_i_delay;

   assign first_available_way_OH = 1 << first_available_way;

   // Wait two 64 bits to combine 128 data//
   always_comb
     begin
        case(FETCH_DATA_WIDTH)
          32:
            begin
               axi_r_data_int = axi_r_data_i[fetch_addr_Q[2]];
            end
          64:
            begin
               axi_r_data_int = axi_r_data_i;
            end
          128:
            begin
                 begin
                    axi_r_data_int[127:64] = axi_r_data_i;
                    axi_r_data_int[63:0] = axi_r_data_i_delay;
                 end
            end
        endcase
     end // always_comb

   always_ff @(posedge clk, negedge rst_n)
   begin
      if(~rst_n)
      begin
         axi_r_data_i_delay <= '0;
      end
      else
        begin
           if(axi_r_valid_i & axi_r_ready_o)
             axi_r_data_i_delay <= axi_r_data_i;
        end
   end

   enum logic [2:0] { DISABLED_ICACHE, WAIT_REFILL_DONE, OPERATIVE, REQ_REFILL , WAIT_PENDING_TRANS, FLUSH_ICACHE, FLUSH_SET_ID } CS, NS;

   int unsigned i,j,index;


   logic      update_lfsr;


   logic [NB_WAYS-1:0]                               fetch_way_int;

   always_ff @(posedge clk, negedge rst_n)
   begin
      if(~rst_n)
      begin
          CS                       <= DISABLED_ICACHE;
          fetch_addr_Q             <= '0;
          fetch_req_Q              <= 1'b0;

          way_valid_Q              <= '0;

          fetch_way_Q              <= '0;

          pending_trans_dis_cache  <= '0;
          counter_FLUSH_CS         <= '0;

          ctrl_hit_count_icache_o   <= '0;
          ctrl_trans_count_icache_o <= '0;
          ctrl_miss_count_icache_o  <= '0;
      end
      else  // else
      begin
          CS <= NS;
          counter_FLUSH_CS         <= counter_FLUSH_NS;

          if(save_fetch_way)
            fetch_way_Q              <= fetch_way_int;

          if(ctrl_clear_regs_icache_i)
          begin
              ctrl_hit_count_icache_o   <= '0;
              ctrl_trans_count_icache_o <= '0;
              ctrl_miss_count_icache_o  <= '0;
          end
          else
            if(ctrl_enable_regs_icache_i)
            begin
              // Count incoming transactions
              if(fetch_req_i & fetch_gnt_o)
                  ctrl_trans_count_icache_o <= ctrl_trans_count_icache_o + 1'b1;

              if( (CS == OPERATIVE) & fetch_req_Q & (|way_match))
                ctrl_hit_count_icache_o <= ctrl_hit_count_icache_o + 1'b1;

              if(axi_ar_valid_o & axi_ar_ready_i)
                ctrl_miss_count_icache_o <= ctrl_miss_count_icache_o + 1'b1;
            end

          //Use this code to be sure thhat there is not apending transaction when enable cache request is asserted
          if( (CS == DISABLED_ICACHE ) || (CS == WAIT_PENDING_TRANS))
          begin
            case({(axi_ar_valid_o & axi_ar_ready_i), (axi_r_last_i & axi_r_valid_i & axi_r_ready_o)})
            2'b00: begin pending_trans_dis_cache <= pending_trans_dis_cache; end
            2'b10: begin pending_trans_dis_cache <= 1'b1; end
            2'b01: begin pending_trans_dis_cache <= 1'b0; end
            2'b11: begin pending_trans_dis_cache <= 1'b1; end
            endcase // {(axi_ar_valid_o & axi_ar_ready_i), (axi_r_last_i & axi_r_valid_i & axi_r_ready_o)}
          end
          else
          begin
            pending_trans_dis_cache <= 1'b0;
          end


          if(save_pipe_status)
          begin
            way_valid_Q <= way_valid;
          end


          if(enable_pipe)
          begin
               fetch_req_Q    <= 1'b1;
               fetch_addr_Q   <= fetch_addr_i;
          end
          else  if(clear_pipe)
                begin
                     fetch_req_Q <= '0;
                end

      end
   end

// --------------------- //
// TAG CHECK MULTI WAY   //
// --------------------- //
genvar k;
generate

   for(k=0; k<NB_WAYS; k++)
   begin
      assign way_match[k]  = ((TAG_rdata_i[k][SCM_TAG_WIDTH-1] == 1'b1) && (TAG_rdata_i[k][SCM_TAG_WIDTH-2:0] == fetch_addr_Q[TAG_MSB:TAG_LSB]));
      assign way_valid[k]  = (TAG_rdata_i[k][SCM_TAG_WIDTH-1] == 1'b1);
   end

   always_comb
   begin

      flush_set_ID_ack_o = 1'b0;
      axi_ar_len_o       = (CACHE_LINE*FETCH_DATA_WIDTH)/AXI_DATA-1;


      TAG_req_o          = '0;
      TAG_we_o           = 1'b0;
      TAG_addr_o         = fetch_addr_i[SET_ID_MSB:SET_ID_LSB];
      TAG_wdata_o        = {1'b1,fetch_addr_Q[TAG_MSB:TAG_LSB]};

      DATA_req_o         = '0;
      DATA_addr_o        = fetch_addr_i[SET_ID_MSB:SET_ID_LSB];
      DATA_wdata_o       = axi_r_data_int;
      DATA_we_o          = 1'b0;


      fetch_gnt_o             = 1'b0;
      fetch_rvalid_o          = 1'b0;
      fetch_rdata_o           = axi_r_data_int; //FIXME ok for AXI 64 and 32bit INSTR

      axi_ar_valid_o            = 1'b0;
      axi_r_ready_o             = 1'b1;
      axi_ar_addr_o             = fetch_addr_i;
      fetch_way_int             = '0;



      save_pipe_status        = 1'b0;
      save_fetch_way          = '0;

      enable_pipe             = 1'b0;
      clear_pipe              = 1'b0;

      NS                      = CS;
      update_lfsr             = 1'b0;

      cache_is_bypassed_o     = 1'b0;
      cache_is_flushed_o      = 1'b0;

      counter_FLUSH_NS        = counter_FLUSH_CS;

      flush_set_ID_ack_o      = 1'b0;

      case(CS)

         DISABLED_ICACHE:
         begin
            axi_ar_len_o        = 1; // Single beat trans
            counter_FLUSH_NS    = '0;
            flush_set_ID_ack_o  = 1'b1;
            clear_pipe          = 1'b1;
            cache_is_bypassed_o = 1'b1;
            cache_is_flushed_o  = 1'b1;
            fetch_rdata_o       = axi_r_data_int;
            fetch_rvalid_o      = axi_r_valid_i & axi_r_last_i; // Must a single beat transaction

            if(bypass_icache_i == 1'b1) // Already Bypassed
            begin
               NS = DISABLED_ICACHE;
               axi_ar_valid_o  = fetch_req_i;
               fetch_gnt_o     = axi_ar_ready_i & fetch_req_i;
               axi_ar_addr_o   = fetch_addr_i;
            end
            else
            begin // Enable ICache
               fetch_gnt_o         = 1'b0;
               axi_ar_valid_o      = 1'b0;
               NS                  = WAIT_PENDING_TRANS;
            end
         end


         WAIT_PENDING_TRANS:
         begin
            flush_set_ID_ack_o    = 1'b1;
            clear_pipe            = 1'b1;
            cache_is_bypassed_o   = 1'b1;
            cache_is_flushed_o    = 1'b1;

            fetch_rdata_o         = axi_r_data_int;
            fetch_rvalid_o        = axi_r_valid_i & axi_r_last_i; // Must a single beat transaction

            fetch_gnt_o           = 1'b0;
            axi_ar_valid_o        = 1'b0;

            if(pending_trans_dis_cache == 1'b0)
            begin
                  NS = FLUSH_ICACHE; // Flushing is made in the central controller
            end
            else
            begin
                  NS = WAIT_PENDING_TRANS;
            end
         end

         FLUSH_ICACHE:
         begin
            fetch_gnt_o           = 1'b0;
            flush_set_ID_ack_o    = 1'b1;

            if(counter_FLUSH_CS < 2**SCM_TAG_ADDR_WIDTH-1)
            begin
               NS = FLUSH_ICACHE;
               counter_FLUSH_NS = counter_FLUSH_CS + 1'b1;
            end
            else
            begin
               NS = OPERATIVE;
               cache_is_flushed_o  = 1'b1;
               counter_FLUSH_NS = '0;
            end

            TAG_req_o   = '1;
            TAG_we_o    = 1'b1;
            TAG_addr_o  = counter_FLUSH_CS;
            TAG_wdata_o = '0;
         end //~FLUSH_ICACHE

         FLUSH_SET_ID:
         begin
            fetch_gnt_o           = 1'b0;
            flush_set_ID_ack_o    = 1'b1;

            NS = OPERATIVE;

            TAG_req_o   = '1;
            TAG_we_o    = 1'b1;
            TAG_addr_o  = flush_set_ID_addr_i[SET_ID_MSB:SET_ID_LSB];
            TAG_wdata_o = '0;
         end //~FLUSH_SET_ID


         OPERATIVE:
         begin
            cache_is_bypassed_o  = 1'b0;
            cache_is_flushed_o   = 1'b0;
            flush_set_ID_ack_o   = 1'b0;

            fetch_gnt_o          = fetch_req_i & ~(bypass_icache_i | flush_icache_i | flush_set_ID_req_i );


            if(bypass_icache_i | flush_icache_i | flush_set_ID_req_i ) // first check if the previous fetch has a miss or HIT
            begin
               if(fetch_req_Q)
               begin
                   if(|way_match)
                   begin : HIT_BYP

                      if(bypass_icache_i)
                      begin
                         NS = DISABLED_ICACHE;
                      end
                      else if (flush_icache_i)
                         begin
                            NS = FLUSH_ICACHE;
                         end
                         else
                         begin
                            NS = FLUSH_SET_ID;
                         end

                      if(fetch_req_i == 1'b0)
                         clear_pipe = 1'b1;


                      fetch_rvalid_o  = 1'b1;
                      fetch_rdata_o   = DATA_rdata_i[HIT_WAY];

                   end
                   else
                   begin : MISS_BYP
                      // asks for the last refill, then goes into DISABLED state
                      NS               = REQ_REFILL;
                      save_pipe_status = 1'b1;
                   end
               end //~if(fetch_req_Q == 1'b1)
               else
               begin

                   if(bypass_icache_i)
                   begin
                      NS = DISABLED_ICACHE;
                   end
                   else if (flush_icache_i)
                        begin
                            NS = FLUSH_ICACHE;
                        end
                        else
                        begin
                            NS = FLUSH_SET_ID;
                        end

                  clear_pipe = 1'b1;
               end//~else(fetch_req_Q)
            end
            else // NO Bypass request
            begin
               enable_pipe          = fetch_req_i;

               //Read the DATA nd TAG
               TAG_req_o   = {NB_WAYS{fetch_req_i}};
               TAG_we_o    = 1'b0;
               TAG_addr_o  = fetch_addr_i[SET_ID_MSB:SET_ID_LSB];

               DATA_req_o  = {NB_WAYS{fetch_req_i}};
               DATA_we_o   = 1'b0;
               DATA_addr_o = fetch_addr_i[SET_ID_MSB:SET_ID_LSB];

               if(fetch_req_Q)
               begin
                   if(|way_match)
                   begin : HIT
                      NS = OPERATIVE;

                      if(fetch_req_i == 1'b0)
                         clear_pipe = 1'b1;

                      fetch_rvalid_o  = 1'b1;
                      fetch_rdata_o   = DATA_rdata_i[HIT_WAY];
                   end
                   else
                   begin : MISS
                      save_pipe_status = 1'b1;
                      enable_pipe      = 1'b0;
                      NS               = REQ_REFILL;
                   end
               end
               else
               begin
                   NS = OPERATIVE;
               end

            end

         end


         REQ_REFILL:
         begin
            cache_is_bypassed_o  = 1'b0;
            cache_is_flushed_o   = 1'b0;
            flush_set_ID_ack_o   = 1'b0;

            enable_pipe      = 1'b0;
            axi_ar_valid_o   = 1'b1;
            axi_ar_addr_o    = fetch_addr_Q;

            save_fetch_way   = 1'b1;
            // This check is postponed because thag Check is complex. better to do
            // one cycle later;
            if(|way_valid_Q) // all the lines are valid, invalidate one random line
            begin
                  fetch_way_int = random_way;
                  update_lfsr = 1'b1;
            end
            else
            begin
                  fetch_way_int = first_available_way_OH;
                  update_lfsr = 1'b0;
            end


            if(axi_ar_ready_i)
            begin
               NS = WAIT_REFILL_DONE;
            end
            else
            begin
               NS = REQ_REFILL;
            end

         end


         WAIT_REFILL_DONE:
         begin
            cache_is_bypassed_o  = 1'b0;
            cache_is_flushed_o   = 1'b0;
            flush_set_ID_ack_o   = 1'b0;

            fetch_rdata_o   = axi_r_data_int;
            fetch_rvalid_o  = axi_r_valid_i & axi_r_last_i;

            DATA_req_o      = fetch_way_Q & {NB_WAYS{axi_r_valid_i & axi_r_last_i}};
            DATA_addr_o     = fetch_addr_Q[SET_ID_MSB:SET_ID_LSB];
            DATA_wdata_o    = axi_r_data_int;
            DATA_we_o       = 1'b1;

            TAG_req_o       = fetch_way_Q & {NB_WAYS{axi_r_valid_i & axi_r_last_i}};
            TAG_we_o        = 1'b1;
            TAG_addr_o      = fetch_addr_Q[SET_ID_MSB:SET_ID_LSB];
            TAG_wdata_o     = {1'b1,fetch_addr_Q[TAG_MSB:TAG_LSB]};


            if(axi_r_valid_i & axi_r_last_i)
               begin
                 clear_pipe        = 1'b1;
                 NS = OPERATIVE;
               end
               else
               begin
                  NS = WAIT_REFILL_DONE;
               end
         end // case: WAIT_REFILL_DONE

         default:
         begin
            NS = DISABLED_ICACHE;
         end


      endcase // CS
   end


   if(NB_WAYS == 1)
   begin : DIRECT_MAPPED
      assign random_way = 1'b1;
   end
   else
   begin : MULTI_WAY_SET_ASSOCIATIVE
      generic_LFSR_8bit
      #(
         .OH_WIDTH(NB_WAYS),
         .SEED(0)
      )
      i_LFSR_Way_Repl
      (
         .data_OH_o      ( random_way  ),
         .data_BIN_o     (             ),
         .enable_i       ( update_lfsr ),
         .clk            ( clk         ),
         .rst_n          ( rst_n       )
      );
   end
endgenerate

   always_comb
   begin
      first_available_way = 0;

      for(index=0;index<NB_WAYS;index++)
      begin
         if(way_valid_Q[index]==0)
            first_available_way=index;
      end

      HIT_WAY = 0;

      for(index=0;index<NB_WAYS;index++)
      begin
         if(way_match[index]==1)
            HIT_WAY=index;
      end
   end

generate
   if (NB_WAYS != 1)
   begin
      onehot_to_bin #( .ONEHOT_WIDTH(NB_WAYS) ) WAY_MATCH_BIN (.onehot(way_match), .bin(way_match_bin[ $clog2(NB_WAYS)-1:0]) );
      assign way_match_bin[NB_WAYS-1:$clog2(NB_WAYS)] = 0;
   end
   else
   begin
      assign way_match_bin = '0;
   end
endgenerate

endmodule // icache_top
