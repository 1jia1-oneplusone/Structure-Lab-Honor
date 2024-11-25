`ifndef VERILATOR
`define VERILATOR
`endif

`ifdef VERILATOR
`include "include/common.sv"
`include "include/config.sv"
`else

`endif 

parameter REG_SIZE=32,REG_SIZE_BIT=5,CSR_SIZE=16,CSR_SIZE_BIT=4;

module Reg_File import common::*;(
    input [4:0] N1,N2,ND,
    input [11:0] CSR_N2,
    input [11:0] CSR_ND,
    input word_t DI, CSR_DI,
    input clk,WE,reset,
    input logic error, //error为1表示这是个有问题的指令，不应该提交
    input [31:0] instr_in, //传入到W模块然后要提交的指令，对应于DI、ND
    input [63:0] PC_in,
    input [31:0] instr_out, //对应于N1、N2的指令

    output word_t Reg_[REG_SIZE-1:0],Reg_next[REG_SIZE-1:0],CSR[CSR_SIZE-1:0],
    output word_t Q1,Q2,

    input logic [6:0] flush_in,
    output logic flush_out,
    output logic commit,
    
    input [REG_SIZE_BIT-1:0] modify_reg[REG_SIZE-1:0],
    output logic [REG_SIZE_BIT-1:0] mod_reg_dec
    );

    parameter mstatus=0,mtvec=1,mip=2,mie=3,mscratch=4,
        mcause=5,mtval=6,mepc=7,mcyclesatp=8,satp=9,medeleg=10,mode=11;

    word_t CSR_next[CSR_SIZE-1:0];
    logic valid,ok;
    integer i,ii,j,jj,k,kk;
    enum logic [1:0] {
        RESET,
        IDLE,
        DOING,
        WAIT
    } state=RESET;

    
    assign Q1=Reg_[N1];
    //assign Q2=Reg_[N2];
    always_comb //组合逻辑计算Q2
    begin
        Q2=Reg_[N2];//非csr
        if(instr_out[6:0]==7'b1110011)//是csr
        begin
            if (instr_out==32'h30200073) //Mret
                Q2=CSR[mepc];
            else if(instr_out==32'h00000073) //ecall
                Q2=CSR[mtvec];
            else
                case(CSR_N2)
                    12'h300: Q2=CSR[0];
                    12'h305: Q2=CSR[1];
                    12'h344: Q2=CSR[2];
                    12'h304: Q2=CSR[3];
                    12'h340: Q2=CSR[4];
                    12'h342: Q2=CSR[5];
                    12'h343: Q2=CSR[6];
                    12'h341: Q2=CSR[7];
                    12'hB00: Q2=CSR[8];
                    12'h180: Q2=CSR[9];
                    12'h302: Q2=CSR[10];
                    default: ;
                endcase
        end
    end
    
    always_comb //组合逻辑更新Reg_next
    begin
        for(i=0;i<REG_SIZE;i+=1)
            Reg_next[i]=Reg_[i];
        for(ii=0;ii<CSR_SIZE;ii+=1)
            CSR_next[ii]=CSR[ii];

        if (WE == 1'b1 && ND != 5'b0)//更新普通寄存器
            Reg_next[ND]=DI;
        if (instr_in[6:0]==7'b1110011)//更新csr
        begin
            if (instr_in==32'h30200073) //Mret
            begin
                CSR_next[mstatus]={CSR[0][63:13],2'b0,CSR[0][10:8],1'b1,CSR[0][6:4],CSR[0][7],CSR[0][2:0]};
                CSR_next[mode]=0;
            end
            else if(instr_in==32'h00000073) //ecall
            begin
                CSR_next[mepc]=PC_in;
                CSR_next[mcause]={1'b0,63'b1000+{61'b0,CSR_next[mode][1:0]}};
                CSR_next[mstatus][7]=CSR[mstatus][3];
                CSR_next[mstatus][3]=0;
                CSR_next[mstatus][12:11]=CSR[mode][1:0];
                CSR_next[mode]=3;
            end
            else
                case(CSR_ND)
                    12'h300: CSR_next[0] =CSR_DI;
                    12'h305: CSR_next[1] =CSR_DI;
                    12'h344: CSR_next[2] =CSR_DI;
                    12'h304: CSR_next[3] =CSR_DI;
                    12'h340: CSR_next[4] =CSR_DI;
                    12'h342: CSR_next[5] =CSR_DI;
                    12'h343: CSR_next[6] =CSR_DI;
                    12'h341: CSR_next[7] =CSR_DI;
                    12'hB00: CSR_next[8] =CSR_DI;
                    12'h180: CSR_next[9] =CSR_DI;
                    12'h302: CSR_next[10]=CSR_DI;
                    default: ;
                endcase
        end
    end

    always_ff @(posedge clk)
    begin
        unique case(state)
            RESET:
            begin
                for(j=0;j<REG_SIZE;j+=1)
                    Reg_[j]<=64'b0;
                for(jj=0;jj<CSR_SIZE;jj+=1)
                    if(jj!=11)CSR[jj]<=64'b0;
                CSR[11]<=64'b11;//mode初始值为3
                state<=IDLE;
            end

            IDLE:
            begin
                if(flush_in==0)
                begin
                    commit<=0;
                    flush_out<=1;
                    state<=DOING;
                end
            end

            DOING:
            begin
                if(~error && instr_in!=32'b0)//不是气泡
                begin
                    commit<=1;

                    if(WE)//WE==1，才需要启动
                    begin
                        for(k=0;k<REG_SIZE;k+=1)
                        begin
                            Reg_[k]<=Reg_next[k];
                        end
                        for(kk=0;kk<CSR_SIZE;kk+=1)
                        begin
                            CSR[kk]<=CSR_next[kk];
                        end
                        mod_reg_dec<=ND[4:0];//标记该寄存器写好了

                        flush_out<=1;
                        state<=WAIT;
                    end
                    else
                    begin
                        flush_out<=0;
                        state<=IDLE;
                    end
                end

                else//是气泡
                begin
                    commit<=0;
                    flush_out<=0;
                    state<=IDLE;
                end
            end

            WAIT:
            begin
                mod_reg_dec<=0;//标记维持一个周期后就清零
                flush_out<=0;

                state<=IDLE;
            end

            default:;
        endcase
    end
    
    
endmodule
