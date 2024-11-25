`ifndef VERILATOR
`define VERILATOR
`endif

`ifdef VERILATOR
`include "include/common.sv"
`include "include/config.sv"
`else

`endif 

module MEM import common::*;(//二合一
    input clk,reset,
    input u64 satp,
    input logic [1:0]mode,
    input u64 PC_in,
    output u64 PC_out,
    output u32 Memory_Data_F,
    output logic flush_out_F,
	output ibus_req_t  ireq,
	input  ibus_resp_t iresp,  
    input logic[6:0] flush_in,
    output logic[3:0] bubble,//是否有气泡

    input logic[6:0] instr2,

    input [4:0] modify_reg[31:0],


    input E,WE,
    input addr_t Address,
    input word_t Data_in,
    input logic [2:0] control,
    output word_t Memory_Data_M,
    output logic skip,
	output dbus_req_t  dreq,
	input  dbus_resp_t dresp,
    output logic flush_out_M
    );
    u32 instruction,delay_instruction;
    u64 current_pc,requested_pc;
    assign Memory_Data_F=instruction;
    assign PC_out=current_pc;
    
    logic [63:0] real_data;
    logic [2:0]  control_lock;
    u64  Address_lock;
    logic [7:0]  strobe_lock;
    u64          data_lock;
    msize_t      size_lock;
    logic CSR_wait;//如果是mret等指令，会先按照控制冒险进行阻塞，这时候比一般的CSR指令少阻塞2次，所以需要补一下
    
    enum logic [4:0] {
        I_IDLE,
        I_BUBBLE3,
        I_PREPARE,
        I_REQUEST_SENT,
        I_GET_PAGE2,
        I_GET_PAGE3,
        I_GET_INSTR,
        I_BUBBLE1,
        I_BUBBLE2,
        I_BUBBLE2a,
        I_RESPONSE_RECEIVED_pre,
        I_RESPONSE_RECEIVED,
        D_IDLE,
        D_PREPARE,
        D_GET_PAGE1,
        D_GET_PAGE2,
        D_GET_PAGE3,
        D_REQUEST_SENT,
        D_RESPONSE_RECEIVED
    } state=D_IDLE, backtoI=I_IDLE;//backtoI：Dmem执行完后回到Imem需要进入哪个状态，一般是IDLE和bubble

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
            flush_out_F <=0;
            bubble <= 0;

            //real_data<=0;
            control_lock<=0;
            Address_lock<=0;
            strobe_lock<=0;
            size_lock<=MSIZE1;
            data_lock<=0;
            //real_data<=0;
            flush_out_M <=0;
            skip<=0;
        end 
        else 
        begin
            unique case (state) //状态机，先让dmem玩再让imem玩
                D_IDLE:
                begin
                    if(flush_in==0)
                    begin
                        //先帮imem初始化一下
                        instruction <= 32'b0; // 初始化
                        current_pc <= requested_pc; // 将当前的 PC 值设置为请求的 PC 值
                        flush_out_F<=1;

                        if(E)//要用dmem
                        begin
                            control_lock<=control;
                            Address_lock<=Address;
                            flush_out_M<=1;
                            skip<=~Address[31];

                            if(WE)
                            begin
                                case(control[1:0])
                                    2'b00:strobe_lock<=8'h01<<(Address[2:0]);
                                    2'b01:strobe_lock<=8'h03<<(Address[2:0]);
                                    2'b10:strobe_lock<=8'h0f<<(Address[2:0]);
                                    2'b11:strobe_lock<=8'hff;
                                endcase
                                case(control[1:0])//修正输入数据
                                    2'b00:data_lock<=Data_in<<(8*Address[2:0]);
                                    2'b01:data_lock<=Data_in<<(8*Address[2:0]);
                                    2'b10:data_lock<=Data_in<<(8*Address[2:0]);
                                    2'b11:data_lock<=Data_in;
                                endcase
                            end
                            else
                            begin
                                strobe_lock<=0;
                                data_lock<=0;
                            end

                            case(control[1:0])
                                2'b00:size_lock<=MSIZE1;
                                2'b01:size_lock<=MSIZE2;
                                2'b10:size_lock<=MSIZE4;
                                2'b11:size_lock<=MSIZE8;
                            endcase
                            
                            if(mode==3||satp[63:60]!=4'h8)//虚拟地址=物理地址
                                state<=D_PREPARE;
                            else //虚拟地址≠物理地址
                                state<=D_GET_PAGE1;
                        end
                        else
                        begin
                            skip<=0;
                            state<=backtoI;//直接交给imem
                        end
                        

                    end
                    else;
                end

                D_PREPARE://发送正式请求
                begin
                    dreq.valid<=1;
                    dreq.addr<=Address_lock;
                    dreq.strobe<=strobe_lock;
                    dreq.data<=data_lock;
                    dreq.size<=size_lock;
                    state<=D_REQUEST_SENT;
                end

                D_GET_PAGE1: //第一页
                begin
                    dreq.valid<=1;
                    dreq.addr<={8'b0,satp[43:0],12'b0};
                    state<=D_GET_PAGE2;
                end

                D_GET_PAGE2: //第二页
                begin
                    if (dresp.data_ok)
                    begin
                        state<= D_GET_PAGE3;
                        dreq.addr<= {7'b0,dresp.data[54:10],12'b0}+{52'b0,Address_lock[20:12],3'b0};
                    end
                end

                D_GET_PAGE3: //第三页
                begin
                    if (dresp.data_ok)
                    begin
                        state<= D_REQUEST_SENT;//发起正式请求
                        dreq.addr<= {7'b0,dresp.data[54:10],12'b0}+{52'b0,Address_lock[11:0]};
                        dreq.strobe<=strobe_lock;
                        dreq.data<=data_lock;
                        dreq.size<=size_lock;
                    end
                end

                D_REQUEST_SENT:
                begin
                    if(dresp.data_ok)//拿到信号了
                    begin
                        dreq.valid<=0;
                        dreq.addr<=0;
                        dreq.strobe<=0;
                        dreq.size<=MSIZE1;
                        dreq.data<=0;

                        //存储数据
                        if(WE||~WE)
                        begin
                            case(control_lock[1:0])//因为dresp.data总是按总线对齐，所以需要修正取出来的数据
                                2'b00:real_data=dresp.data>>(8*Address_lock[2:0]);
                                2'b01:real_data=dresp.data>>(8*Address_lock[2:0]);
                                2'b10:real_data=dresp.data>>(8*Address_lock[2:0]);
                                default:;
                            endcase
                            case(control_lock[1:0])
                                2'b00:Memory_Data_M<={{56{real_data[ 7]&~control_lock[2]}},real_data[ 7:0]};
                                2'b01:Memory_Data_M<={{48{real_data[15]&~control_lock[2]}},real_data[15:0]};
                                2'b10:Memory_Data_M<={{32{real_data[31]&~control_lock[2]}},real_data[31:0]};
                                2'b11:Memory_Data_M<=dresp.data;
                            endcase
                        end

                        state<=D_RESPONSE_RECEIVED;
                    end
                    else;
                end

                D_RESPONSE_RECEIVED:
                begin
                    flush_out_M<=0;
                    state<=backtoI;//玩完后交给imem
                end



                I_IDLE: 
                begin
                    instruction <= 32'b0; // 初始化
                    current_pc <= requested_pc; // 将当前的 PC 值设置为请求的 PC 值
                    if(CSR_wait)//MRET刚结束E模块，还需要继续清空流水线
                    begin
                        state  <=D_IDLE;
                        backtoI<=I_BUBBLE3;
                        bubble <=4'b1000;
                        flush_out_F<=0;
                    end
                    else
                    begin
                        state <= I_PREPARE; // 进入PREPARE状态
                        flush_out_F<=1;
                    end
                end

                I_BUBBLE3://刷新流水线专用
                begin
                    bubble<= bubble>>1;
                    if(bubble>>1 ==0)//气泡放完了
                    begin
                        CSR_wait<=0;
                        flush_out_F<=1;
                        state<=I_PREPARE;//该干正事了
                        backtoI<=I_IDLE;
                    end
                end

                I_PREPARE:
                begin
                    if(mode==3||satp[63:60]!=4'h8)//虚拟地址=物理地址
                    begin
                        ireq.valid<= 1'b1; // 发送请求信号
                        ireq.addr <= current_pc; // 设置请求的地址为当前的 PC 值
                    end
                    else //虚拟地址需要转化成物理地址
                    begin
                        dreq.valid<= 1'b1;
                        dreq.addr <= {8'b0,satp[43:0],12'b0}+{52'b0,current_pc[38:30],3'b0};//第一级页表项
                        dreq.strobe<=0;//写相关的都关掉
                        dreq.size<=MSIZE1;
                        dreq.data<=0;
                    end
                    state <= I_REQUEST_SENT; // 进入 REQUEST_SENT 状态
                    
                end

                I_REQUEST_SENT: //请求已经发送了，在等待指令
                begin
                    if (iresp.data_ok || dresp.data_ok) //指令送来了
                    begin
                        if(iresp.data_ok)//虚拟地址=物理地址
                        begin
                            instruction <= iresp.data;
                            state<= I_GET_INSTR;
                            ireq.valid<=1'b0;
                        end
                        else //虚拟地址需要转化成物理地址
                        begin
                            state<= I_GET_PAGE2;
                            dreq.valid<=1'b1;
                            dreq.addr<= {7'b0,dresp.data[54:10],12'b0}+{52'b0,current_pc[29:21],3'b0};
                        end
                    end
                    else;
                end

                I_GET_PAGE2: //第二页
                begin
                    if (dresp.data_ok)
                    begin
                        //if({{7'b0,dresp.data[54:10],12'b0}+{52'b0,current_pc[20:12],3'b0}}==64'h4044c00008008)
                        //begin
                        //    state<=I_RESPONSE_RECEIVED;
                        //    dreq.valid<=0;
                        //    instruction<=32'h00000093;
                        //end
                        //else
                        //begin
                        state<= I_GET_PAGE3;
                        dreq.valid<=1'b1;
                        dreq.addr<= {7'b0,dresp.data[54:10],12'b0}+{52'b0,current_pc[20:12],3'b0};
                        //end
                    end
                end

                I_GET_PAGE3: //第三页
                begin
                    if (dresp.data_ok)
                    begin
                        state<= I_REQUEST_SENT;
                        dreq.valid<=1'b0;
                        ireq.valid<=1'b1;
                        ireq.addr<= {7'b0,dresp.data[54:10],12'b0}+{52'b0,current_pc[11:0]};
                        end
                end

                I_GET_INSTR:
                begin
                    if(modify_reg[instruction[24:20]]>5'b1 || modify_reg[instruction[19:15]]>5'b1)//数据冒险
                    begin
                        state<= D_IDLE;
                        backtoI<= I_BUBBLE1;
                        delay_instruction<=instruction;
                        bubble<=4'b1000;
                        flush_out_F<=0;
                        instruction<=0;
                    end
                    else if(instruction[6:0]==7'b1101111||instruction[6:0]==7'b1100111||instruction[6:0]==7'b1100011)//控制冒险
                    begin
                        state<= I_BUBBLE2a;
                        bubble<=4'b10;
                    end
                    else if(instruction[6:0]==7'b1110011)//CSR相关指令，要刷新流水线
                    begin
                        state<= I_BUBBLE2a;
                        if(instruction==32'h30200073||instruction==32'h00000073)
                        begin
                            bubble<=4'b10;
                            CSR_wait<=1;
                        end
                        else
                            bubble<=4'b1000;
                    end
                    else
                        state <= I_RESPONSE_RECEIVED; // 进入 RESPONSE_RECEIVED 状态
                end

                I_BUBBLE1: //保持当前指令，向后吐气泡
                begin
                    bubble<= bubble>>1;
                    if(bubble>>1 ==0)//气泡放完了
                    begin
                        flush_out_F<=1;
                        instruction<=delay_instruction;
                        state<=I_GET_INSTR;
                        backtoI<=I_IDLE;
                    end
                    else
                    begin
                        flush_out_F<=0;
                        state<=D_IDLE;//先回去dmem
                        backtoI<=I_BUBBLE1;//记下来，下次dmem执行完后回到这个状态
                    end
                end

                I_BUBBLE2a: //先把当前指令传下去，再进入气泡状态
                begin
                    ireq.valid <= 1'b0; // 取完指令后，将 ireq.valid 设为 0
                    state<=D_IDLE;//先回去dmem
                    backtoI<=I_BUBBLE2;//记下来，下次dmem执行完后回到吐气泡状态
                    flush_out_F<=0;
                end

                I_BUBBLE2: //向后吐气泡
                begin
                    instruction<=0;//气泡
                    bubble<= bubble>>1;
                    if(bubble>>1 ==0)//气泡放完了
                    begin
                        flush_out_F<=1;
                        state<=I_RESPONSE_RECEIVED;
                        backtoI<=I_IDLE;
                    end
                    else
                    begin
                        flush_out_F<=0;
                        state<=D_IDLE;//先回去dmem
                        backtoI<=I_BUBBLE2;//记下来，下次dmem执行完后回到这个状态
                    end
                end

                I_RESPONSE_RECEIVED_pre:
                    state <= I_RESPONSE_RECEIVED;

                I_RESPONSE_RECEIVED: 
                begin
                    requested_pc <= PC_in; // 每次取完指令后，更新请求的 PC 值
                    ireq.valid <= 1'b0; // 取完指令后，将 ireq.valid 设为 0
                    state <= D_IDLE; // 返回 IDLE 状态
                    flush_out_F<=0;
                end

                default: begin
                    instruction <= 32'h00000000; // 默认情况下，指令为 0
                    ireq.valid <= 1'b0; // 默认情况下，ireq.valid 为 0
                    state <= D_IDLE; // 默认情况下，返回 IDLE 状态
                end
                
            endcase
        end
    end

    
endmodule