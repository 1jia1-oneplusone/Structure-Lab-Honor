`ifndef VERILATOR
`define VERILATOR
`endif

`ifdef VERILATOR
`include "include/common.sv"
`include "include/config.sv"
`else

`endif 

module Freg import common::*;(
    input logic clk,reset,
    input logic [63:0] New,
    output logic [63:0]PC,
    input logic [3:0]bubble,//需要塞几个气泡
    input logic [3:0]buffer_init,

    input logic [6:0]instr,

    input logic [6:0]flush_in
    );

    logic [3:0] buffer;

    always_ff @(posedge clk) //更新PC值
    begin
        if(reset)
            PC<=PCINIT;
        else if(flush_in[6:0]==0 && (bubble==4'b0 || instr[6:0]==7'b1101111||instr[6:0]==7'b1100111||instr[6:0]==7'b1100011))//后续模块都做完了，而且目前不需要生成气泡
            PC<=New;
        else //否则就阻塞
            ;
    end
endmodule
