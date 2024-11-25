`ifndef VERILATOR
`define VERILATOR
`endif

`ifdef VERILATOR
`include "include/common.sv"
`include "include/config.sv"
`else

`endif 

module Mux2(
    input [63:0] A,B,
    input select,
    output logic [63:0] out
    );

    always_comb
    begin
        case(select)
            1'b0: out=A;
            1'b1: out=B;
        endcase
    end
    
    
endmodule
