`ifndef VERILATOR
`define VERILATOR
`endif

`ifdef VERILATOR
`include "include/common.sv"
`include "include/config.sv"
`else

`endif 

module IMEM import common::*;(
    input clk,reset,
    input u64 satp,
    input u64 PC_in,
    output u64 PC_out,
    output u32 Memory_Data,
    output logic flush_out,
	output ibus_req_t  ireq,
	input  ibus_resp_t iresp,
	output dbus_req_t  dreq,
	input  dbus_resp_t dresp,    
    input logic[6:0] flush_in,
    output logic[3:0] bubble,//是否有气泡

    input logic[6:0] instr2,

    input [4:0] modify_reg[31:0]
    );
    u32 instruction,delay_instruction;
    u64 current_pc,requested_pc;
    assign Memory_Data=instruction;
    assign PC_out=current_pc;
    
    
    enum logic [3:0] {
        IDLE,
        PREPARE,
        REQUEST_SENT,
        GET_PAGE1,
        GET_PAGE2,
        GET_PAGE3,
        GET_INSTR,
        BUBBLE1,
        BUBBLE2,
        BUBBLE2a,
        RESPONSE_RECEIVED_pre,
        RESPONSE_RECEIVED
    } state=IDLE;

    always_ff @(posedge clk or posedge reset) 
    begin
        if (reset) 
        begin
            delay_instruction <= 32'b0;
            instruction <= 32'b0; // 重置指令为 0
            current_pc <= PCINIT; // 重置 PC 值为 0
            requested_pc <= PCINIT; // 初始化请求的 PC 值为 0
            ireq.valid <= 1'b0; // 初始化 ireq.valid 为 0
            ireq.addr <= 0;
            state <= IDLE; // 初始化状态为 IDLE
            flush_out <=0;
            bubble <= 0;
        end 
        else 
        begin
            unique case (state) //状态机
                IDLE: 
                begin
                    if (flush_in==0) 
                    begin
                        instruction <= 32'b0; // 初始化
                        current_pc <= requested_pc; // 将当前的 PC 值设置为请求的 PC 值
                        state <= PREPARE; // 进入PREPARE状态，侦测M是否在忙
                        flush_out<=1;
                    end
                    else;
                end

                PREPARE:
                begin
                    if(flush_in[3]==0)//等M玩完
                    begin
                        if(satp[63:60]!=8)//虚拟地址=物理地址
                        begin
                            ireq.valid<= 1'b1; // 发送请求信号
                            ireq.addr <= current_pc; // 设置请求的地址为当前的 PC 值
                        end
                        else //虚拟地址需要转化成物理地址
                        begin
                            //dreq.valid<= 1'b1;
                            //dreq.addr <= {8'b0,satp[43:0],12'b0}+{52'b0,current_pc[38:30],3'b0};//第一级页表项
                        end
                        state <= REQUEST_SENT; // 进入 REQUEST_SENT 状态
                    end
                    else;
                end

                REQUEST_SENT: //请求已经发送了，在等待指令
                begin
                    if (iresp.data_ok || dresp.data_ok) //指令送来了
                    begin
                        if(satp[63:60]!=8)//虚拟地址=物理地址
                        begin
                            instruction <= iresp.data;
                            state<=GET_INSTR;
                            ireq.valid<=1'b0;
                        end
                        else //虚拟地址需要转化成物理地址
                        begin
                            state<=GET_PAGE2;
                            //dreq.valid<=1'b0;
                            //dreq.addr<= {7'b0,dresp.data[54:10],12'b0}+{52'b0,current_pc[29:21],3'b0};
                        end
                    end
                    else;
                end

                GET_PAGE2: //第二页
                begin
                end

                GET_INSTR:
                begin
                    if(modify_reg[instruction[24:20]]>5'b1 || modify_reg[instruction[19:15]]>5'b1)//数据冒险
                        //|| instruction[6:0]==7'b1110011)//CSRR指令
                    begin
                        state<=BUBBLE1;
                        delay_instruction<=instruction;
                        bubble<=4'b1000;
                        flush_out<=0;
                        instruction<=0;
                    end
                    else if(instruction[6:0]==7'b1101111||instruction[6:0]==7'b1100111||instruction[6:0]==7'b1100011||instruction==32'h30200073)//控制冒险
                    begin
                        state<=BUBBLE2a;
                        bubble<=4'b10;
                    end
                    else if(instruction[6:0]==7'b1110011)//CSR相关指令，要刷新流水线
                    begin
                        state<=BUBBLE2a;
                        bubble<=4'b1000;
                    end
                    else
                        state <= RESPONSE_RECEIVED; // 进入 RESPONSE_RECEIVED 状态
                end

                BUBBLE1: //保持当前指令，向后吐气泡
                begin
                    if(flush_in==0)
                    begin
                        bubble<= bubble>>1;
                        if(bubble>>1 ==0)//气泡放完了
                        begin
                            flush_out<=1;
                            instruction<=delay_instruction;
                            state<=GET_INSTR;
                        end
                    end
                    else;
                end

                BUBBLE2a: //先把当前指令传下去，再进入气泡状态
                begin
                    ireq.valid <= 1'b0; // 取完指令后，将 ireq.valid 设为 0
                    state <= BUBBLE2; // 进入吐气泡状态
                    flush_out<=0;
                end

                BUBBLE2: //吐出当前指令，再向后吐气泡
                begin
                    if(flush_in==0)
                    begin
                        instruction<=0;//气泡
                        bubble<= bubble>>1;
                        if(bubble>>1 ==0)//气泡放完了
                        begin
                            flush_out<=1;
                            state<=RESPONSE_RECEIVED;
                        end
                    end
                    else;
                end

                RESPONSE_RECEIVED_pre:
                    state <= RESPONSE_RECEIVED;

                RESPONSE_RECEIVED: 
                begin
                    requested_pc <= PC_in; // 每次取完指令后，更新请求的 PC 值
                    ireq.valid <= 1'b0; // 取完指令后，将 ireq.valid 设为 0
                    state <= IDLE; // 返回 IDLE 状态
                    flush_out<=0;
                end

                default: begin
                    instruction <= 32'h00000000; // 默认情况下，指令为 0
                    ireq.valid <= 1'b0; // 默认情况下，ireq.valid 为 0
                    state <= IDLE; // 默认情况下，返回 IDLE 状态
                end
                
            endcase
        end
    end

    
endmodule