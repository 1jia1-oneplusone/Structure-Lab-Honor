`ifndef VERILATOR
`define VERILATOR
`endif

`ifdef VERILATOR
`include "include/common.sv"
`include "include/config.sv"
`else

`endif 

module Control_Unit import common::*;(
    input logic clk,reset,
    input logic [31:0] instr,
    input [6:0] opcode,funct7,
    input [2:0] funct3,
    /*
    output logic WREG,ALU_B,BRANCH,OFFSET,
    output logic [1:0]REG_DATA_INPUT,
    output logic [11:0] ALUC,
    output logic WMEM,DMenable,
    output logic [2:0] DmemC,
//    output skip,
    output logic ERROR,
    */
    output logic [23:0] control_signal, //所有信号打包起来发出去
    output logic [63:0]Ext_out,
    input logic[6:0] flush_in,
    output logic flush_out,
    
    input [REG_SIZE_BIT-1:0] modify_reg[REG_SIZE-1:0],
    output logic [REG_SIZE_BIT-1:0] mod_reg_inc
    );
    logic WREG,ALU_B,OFFSET;
    logic [2:0]REG_DATA_INPUT;
    logic [11:0] ALUC;
    logic WMEM,DMenable;
    logic [2:0] DmemC;
    logic ERROR;
    assign control_signal={WREG,ALU_B,OFFSET,REG_DATA_INPUT,ALUC,WMEM,DMenable,DmemC,ERROR};//打包带走
    
    parameter OPI=7'b0010011,OP=7'b0110011,JAL=7'b1101111,JALR=7'b1100111,
                B__=7'b1100011,AUIPC=7'b0010111,LUI=7'b0110111,
                SD=7'b0100011,LD=7'b0000011,
                OPIW=7'b0011011,OPW=7'b0111011,
                CSRR=7'b1110011;

    logic valid,ok;
    assign ok=valid;//CU单周期，所以一valid马上就ok了
    assign flush_out= valid & (~ok);
    always_ff @(posedge clk)//设置valid
    begin
        if(flush_in[6:0]==0)//后面模块的阻塞解除了
        begin
            valid<=1'b1;
        end
        else if(ok)//已经译码1条指令了，就下线
            valid<=1'b0;
        else;
    end

    always_comb
    begin
        case(opcode)
            OPIW:   begin
                if((funct3[1:0]==2'b01) && instr[25]==1'b1)//shift left/right特有的指令无效
                          {WREG,ALU_B,OFFSET,REG_DATA_INPUT,ALUC,WMEM,DMenable,ERROR}=21'b1;
                else
                          {WREG,ALU_B,OFFSET,REG_DATA_INPUT,ALUC,WMEM,DMenable,ERROR}={6'b110_001,              {1'b1,opcode[3],funct3[1:0]==2'b01 ?funct7:7'b0,funct3},2'b00,1'b0}; end
            OPI:    begin {WREG,ALU_B,OFFSET,REG_DATA_INPUT,ALUC,WMEM,DMenable,ERROR}={6'b110_001,              {1'b1,opcode[3],funct3[1:0]==2'b01 ?funct7:7'b0,funct3},2'b00,1'b0}; end
            OP,OPW: begin {WREG,ALU_B,OFFSET,REG_DATA_INPUT,ALUC,WMEM,DMenable,ERROR}={6'b100_001,              {1'b0,opcode[3],funct7,funct3},                         2'b00,1'b0}; end
            JAL:    begin {WREG,ALU_B,OFFSET,REG_DATA_INPUT,ALUC,WMEM,DMenable,ERROR}={6'b100_000,              12'b0,                                                  2'b00,1'b0}; end
            JALR:   begin {WREG,ALU_B,OFFSET,REG_DATA_INPUT,ALUC,WMEM,DMenable,ERROR}={6'b111_000,              12'b0,                                                  2'b00,1'b0}; end
            B__:    begin {WREG,ALU_B,OFFSET,REG_DATA_INPUT,ALUC,WMEM,DMenable,ERROR}={2'b00,4'b0_000,          12'b0100000_000,                                        2'b00,1'b0}; end
            AUIPC:  begin {WREG,ALU_B,OFFSET,REG_DATA_INPUT,ALUC,WMEM,DMenable,ERROR}={6'b100_011,              12'b0,                                                  2'b00,1'b0}; end
            LUI:    begin {WREG,ALU_B,OFFSET,REG_DATA_INPUT,ALUC,WMEM,DMenable,ERROR}={6'b110_001,              12'b0100000_111,                                        2'b00,1'b0}; end
            SD:     begin {WREG,ALU_B,OFFSET,REG_DATA_INPUT,ALUC,WMEM,DMenable,ERROR}={6'b010_000,              12'b0,                                                  2'b11,1'b0}; end
            LD:     begin {WREG,ALU_B,OFFSET,REG_DATA_INPUT,ALUC,WMEM,DMenable,ERROR}={6'b110_010,              12'b0,                                                  2'b01,1'b0}; end
            CSRR:    
                if(instr!=32'h30200073&&instr!=32'h00000073)//不是mret或ecall
                          {WREG,ALU_B,OFFSET,REG_DATA_INPUT,ALUC,WMEM,DMenable,ERROR}={1'b1,funct3[2],4'b0_100, {9'b1111111,funct3},                                     2'b00,1'b0};
                else      {WREG,ALU_B,OFFSET,REG_DATA_INPUT,ALUC,WMEM,DMenable,ERROR}={6'b101_000,              12'b0100000_111,                                        2'b00,1'b0};
            default:      {WREG,ALU_B,OFFSET,REG_DATA_INPUT,ALUC,WMEM,DMenable,ERROR}=21'b1;
        endcase

        case(opcode) //设置dmem的控制信号
            LD,SD:   DmemC=funct3;
            default: DmemC=3'b0;
        endcase

        case(opcode) //计算符号扩展立即数
            OPI,OPIW:begin
                if(instr[13:12]==2'b01)//shift l/r
                     Ext_out={58'b0,instr[25:20]};
                else
                     Ext_out={{52{instr[31]}},instr[31:20]};
            end
            OP,OPW:  Ext_out=0;
            JAL:     Ext_out={{44{instr[31]}},instr[19:13],instr[12],instr[20],instr[30:21],1'b0};
            JALR:    Ext_out={{52{instr[31]}},instr[31:20]};
            B__:     Ext_out={{52{instr[31]}},instr[7],instr[30:25],instr[11:8],1'b0};
            AUIPC:   Ext_out={{32{instr[31]}},instr[31:12],{12'b0}};
            LUI:     Ext_out={{32{instr[31]}},instr[31:12],{12'b0}};
            SD:      Ext_out={{52{instr[31]}},instr[31:25],instr[11:7]};
            LD:      Ext_out={{52{instr[31]}},instr[31:20]};
            CSRR:    
                if(funct3[2])
                     Ext_out={59'b0,instr[19:15]};
                else
                     Ext_out=0;
            default: Ext_out=0;
        endcase

    end

    //设置写寄存器脉冲
    always_ff @(posedge clk)
    begin
        if(WREG && ok)//如果这个指令需要写寄存器
        begin
            mod_reg_inc<=instr[11:7];
        end
        else
        begin 
            if(mod_reg_inc>0)//重置，防止多次记录
                mod_reg_inc<=0;
            else;
        end
    end
    
endmodule
