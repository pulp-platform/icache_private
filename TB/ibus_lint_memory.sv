// Copyright 2018 ETH Zurich, University of Bologna and Greenwaves Technologies.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

module ibus_lint_memory
#(
    parameter addr_width = 16,
    parameter INIT_MEM_FILE = "slm_files/l2_stim.slm"
)
(
    input  logic                                clk,
    input  logic                                rst_n,
    
    // Interface to Instruction Logaritmic interconnect
    input  logic                                lint_req_i,
    output logic                                lint_grant_o,
    input  logic [addr_width-1:0]               lint_addr_i,
    
    output logic [31:0]                         lint_r_rdata_o,
    output logic                                lint_r_valid_o
);

    localparam                          numwords = 2**addr_width;
    integer                             i;
    logic [31:0]                        ARRAY [numwords];
    logic                               r_valid;
    logic [31:0]                        r_rdata;
    logic                               lint_grant_int;
    
    
    

    assign lint_grant_o = 1'b1; //lint_grant_int & lint_req_i;

    always_ff @(posedge clk, negedge rst_n)
    begin
        if(rst_n == 1'b0)
        begin    
          lint_grant_int <= 1'b0;
        end
        else
        begin
          lint_grant_int <= $random() % 2;
        end
    end

    

   
    always_ff @(posedge clk, negedge rst_n)
    begin
      if(rst_n == 1'b0)
      begin
        r_valid <= 1'b0;
        r_rdata <= '0;
      end
      else
      begin
        if(lint_req_i & lint_grant_o)
        begin
            r_valid <= 1'b1;
            r_rdata <= ARRAY [lint_addr_i];
        end
        else
        begin
            r_valid <= 1'b0;
        end
      end
    end

    assign lint_r_valid_o = r_valid;
    assign lint_r_rdata_o = r_rdata;


    logic [31:0] temp0;

    initial
    begin
      
      for(i = 0; i< numwords; i++)
      begin
        temp0 = i*4;
        ARRAY[i] = temp0;
      end
      //$readmemh(INIT_MEM_FILE, ARRAY);
    end

endmodule
