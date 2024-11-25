`ifndef VERILATOR
`define VERILATOR
`endif

`ifdef VERILATOR
`include "include/common.sv"
`include "include/config.sv"
`else

`endif 

module Dreg import common::*;(
    input logic clk, reset,
    input u32 instr_in,
    input u64 PC_in,

    output u32 instr_out,
    output u64 PC_out,

    input logic [6:0] flush_in,
    input logic enable
);
    //logic en,enclk;//enclk用于在flush期间保持en
    //assign en=enable|enclk;

    always_ff @(posedge clk)
    begin
        if (reset) 
            {instr_out,PC_out} <= 96'b0;
        else if(flush_in[6:0]==0)//后续模块都做完了
        begin
            instr_out<=instr_in;
            PC_out<=PC_in;
        end
        else //否则就阻塞
            ;

    end
    


endmodule