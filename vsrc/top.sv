`ifndef VERILATOR
`define VERILATOR
`endif

`ifdef VERILATOR
`include "include/common.sv"
`include "include/config.sv"
`else

`endif 


module top import common::*;(
    input clk,reset,
    input word_t PCINIT,
    output word_t Reg5[31:0],
    output word_t CSR5[CSR_SIZE-1:0],
    output word_t reg_DI,
    //output [31:0] writedata,dataadr,
    //output memwrite,
    output logic WREG,//ALU_B,BRANCH,OFFSET,
//    output [1:0] REG_DATA_INPUT,
//    output [6:0] SEXT,
//    output [3:0] ALUC,
//    output [31:0] Ext,ALU_result,
//    output WMEM,
    output logic skip5,
    output u32 instr5,
    output u64 PC5,PC_in,
    output logic ERROR,BLOCK,
	output ibus_req_t  ireq,
	input  ibus_resp_t iresp,
	output dbus_req_t  dreq,
	input  dbus_resp_t dresp,
	input  logic       trint, swint, exint,
    output logic commit5
    );
    //assign ERROR=control4[0];
    
    //大部分信号有xxx、xxx1、xxx2、...多个版本，分别为各个阶段用的信号

    logic [6:0] all_flush;

    logic [REG_SIZE_BIT-1:0] modify_reg[REG_SIZE-1:0];//数据冒险：对于每个寄存器，当前有几个指令准备写它
    logic [REG_SIZE_BIT-1:0] mod_reg_inc,mod_reg_dec;//D和W分别的修改请求
    integer i;
    always @(posedge clk)//在每个周期都看看要不要更新
    begin
        if(reset)
        begin
            for(i=1;i<REG_SIZE;i+=1)
                modify_reg[i]<=1;
            //mod_reg_inc<=0;
            //mod_reg_dec<=0;
        end
        else 
        begin
            if(mod_reg_dec!=mod_reg_inc)
            begin
                if(mod_reg_dec!=0)
                    modify_reg[mod_reg_dec]<= modify_reg[mod_reg_dec]>>1;
                if(mod_reg_inc!=0)
                    modify_reg[mod_reg_inc]<= modify_reg[mod_reg_inc]<<1;
            end
        end
    end

    //F-0 IMEM
    u64 PC0;
    word_t extor4;
    u32 instr0;
    logic [3:0]F_bubble;
    
    //D-1 Control Unit
    u64 PC1;
    u32 instr1;
    u64 Ext1;
    logic [23:0] control1;
    logic BRANCH;
        
    //E-2 ALU
    u64 PC2;
    u32 instr2;
    u64 Ext2;
    logic [23:0] control2;
    //u64 reg_Q12,reg_Q22;
    word_t ALU_Bin;
    logic [63:0] ALU_Ain2,ALU_Bin2,ALU_result2;
    logic ZF,SF,OF,CF,block_ALU;

    //M-3 DMEM
    u64 PC3;
    u32 instr3;
    u64 Ext3;
    logic [23:0] control3;
    logic [63:0] reg_Q23;
    logic [63:0] ALU_result3;
    word_t Memory_Data3;
    logic skip3;

    //W-4 reg file
    u64 PC4;
    u32 instr4;
    u64 Ext4;
    logic [23:0] control4;
    logic [63:0] ALU_result4;
    word_t Memory_Data4;
    logic skip4;
    u64 reg_Q24;
    u64 reg_Q1out,reg_Q2out;
    u64 reg_DI4;
    logic commit4;
    word_t Reg4[REG_SIZE-1:0], Reg4_next[REG_SIZE-1:0], CSR4[CSR_SIZE-1:0];

    
    //Freg freg(clk,reset, PC_in,PC0, F_bubble,F_buffer, instr2[6:0], all_flush);//原PC模块
    //IMEM imem(clk,reset,CSR4[10],PC_in,PC0,instr0,all_flush[0],ireq,iresp,dreq,dresp,all_flush,F_bubble, instr2[6:0], modify_reg);
    MEM mem(clk,reset,CSR4[9],CSR4[11][1:0],PC_in,PC0,instr0,all_flush[0],ireq,iresp,all_flush,F_bubble, instr2[6:0], modify_reg, control2[4],control2[5], ALU_result2,reg_Q2out,control2[3:1], Memory_Data3,skip3,dreq,dresp, all_flush[3]);
    
    Dreg dreg(clk,reset, instr0,PC0 ,instr1,PC1 ,all_flush,1'b1);
    Control_Unit control_unit(clk,reset,instr1,instr1[6:0],instr1[31:25],instr1[14:12],control1,Ext1,all_flush,all_flush[1], modify_reg,mod_reg_inc);
    
    Ereg ereg(clk,reset, Ext1,control1,instr1,PC1, Ext2,control2,instr2,PC2, all_flush);
    Mux2 mxALU_B(reg_Q2out,Ext2,control2[22],ALU_Bin);
    ALU ALU(clk,reset, instr2,reg_Q1out,ALU_Bin,control2[17:6], BRANCH,ALU_result2, all_flush,all_flush[2]);
    Mux2 mxBRANCH(PC0+64'b100,PC2+Ext2,BRANCH,extor4);
    Mux2 mxOFFSET(extor4,ALU_result2&(~64'b1),control2[21],PC_in);
    
    Mreg mreg(clk,reset, reg_Q2out,Ext2,control2,instr2,PC2,ALU_result2, reg_Q23,Ext3,control3,instr3,PC3,ALU_result3, all_flush);
    //DMEM dmem(control2[4],control2[5],clk,CSR4[10], ALU_result2,reg_Q2out,control2[3:1], Memory_Data3,skip3,dreq,dresp, all_flush,all_flush[3]);
    
    Wreg wreg(clk,reset, reg_Q23,Ext3,control3,instr3,PC3,ALU_result3,Memory_Data3,skip3, reg_Q24,Ext4,control4,instr4,PC4,ALU_result4,Memory_Data4,skip4, all_flush);
    Mux8 mxReg_DATA_INPUT(PC4+64'b100,ALU_result4,Memory_Data4,PC4+Ext4,reg_Q24,control4[20:18],reg_DI4);
    Reg_File regfile(instr2[19:15],instr2[24:20],instr4[11:7],instr2[31:20],instr4[31:20],reg_DI4,ALU_result4, //N1,N2和ND分别用D模块和M模块传来的指令
        clk,control4[23],reset,control4[0],instr4,PC4, 
        instr2, Reg4,Reg4_next,CSR4,reg_Q1out,reg_Q2out,
        all_flush,all_flush[4],commit4, modify_reg,mod_reg_dec);
    
    integer j,jj;
    always_ff @(posedge clk)//处理一些需要提交的信号
        if (reset)
        begin
            instr5<=32'b0;
            PC5<=64'b0;
            WREG<=0;
            ERROR<=0;
            reg_DI<=0;
            skip5<=0;
            commit5<=0;
            for(j=0;j<REG_SIZE;j+=1)
                Reg5[j]<=0;
            for(jj=0;jj<CSR_SIZE;jj+=1)
                CSR5[jj]<=0;
        end
        else if (all_flush[6:0]==7'b0)//后续模块都做完了，更新
        begin
            instr5<=instr4;
            PC5<=PC4;
            WREG<=control4[23];
            ERROR<=control4[0];
            reg_DI<=reg_DI4;
            skip5<=skip4;
            commit5<=commit4;
            for(j=0;j<REG_SIZE;j+=1)
                Reg5[j]<=Reg4[j];
            for(jj=0;jj<CSR_SIZE;jj+=1)
                CSR5[jj]<=CSR4[jj];
        end
        else//否则就阻塞   
            ;

    
    assign BLOCK= (all_flush!=7'b0);

endmodule
