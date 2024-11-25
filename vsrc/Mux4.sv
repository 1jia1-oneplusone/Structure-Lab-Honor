`ifndef VERILATOR
`define VERILATOR
`endif

`ifdef VERILATOR
`include "include/common.sv"
`include "include/config.sv"
`else

`endif 

module Mux4(
    input logic [63:0] A,B,C,D,
    input logic [1:0] select,
    output logic [63:0] out
    );
    always_comb
    begin
        case(select)
            2'b00: out=A;
            2'b01: out=B;
            2'b10: out=C;
            2'b11: out=D;
        endcase
    end
    
endmodule
