`ifndef VERILATOR
`define VERILATOR
`endif

`ifdef VERILATOR
`include "include/common.sv"
`include "include/config.sv"
`else

`endif 

module Mux8(
    input logic [63:0] A,B,C,D,E,
    input logic [2:0] select,
    output logic [63:0] out
    );
    always_comb
    begin
        case(select)
            3'b000: out=A;
            3'b001: out=B;
            3'b010: out=C;
            3'b011: out=D;
            default:out=E;
        endcase
    end
    
endmodule
