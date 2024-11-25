`ifndef VERILATOR
`define VERILATOR
`endif

`ifdef VERILATOR
`include "include/common.sv"
`include "include/config.sv"
`else

`endif 

module Ereg import common::*;(
    input logic clk, reset,
    input u64 Ext_in,
    input logic [23:0] control_in,
    input u32 instr_in,
    input u64 PC_in,

    output u64 Ext_out,
    output logic [23:0] control_out,
    output u32 instr_out,
    output u64 PC_out,

    input logic [6:0] flush_in
);
    always_ff @(posedge clk)
        if (reset)
        begin
            Ext_out<=64'b0;
            control_out<=0;
            instr_out<=32'b0;
            PC_out<=64'b0;
        end
        else if (flush_in[6:0]==0)//后续模块都做完了，更新
        begin
            Ext_out<=Ext_in;
            control_out<=control_in;
            instr_out<=instr_in;
            PC_out<=PC_in;
        end
        else//否则就阻塞   
            ;
    
endmodule