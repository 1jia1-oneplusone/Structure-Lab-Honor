`ifndef VERILATOR
`define VERILATOR
`endif

`ifdef VERILATOR
`include "include/common.sv"
`include "include/config.sv"
`else

`endif 

module DMEMM import common::*;(
    input E,WE,clk,
    input u64 satp,
    input addr_t Address,
    input word_t Data_in,
    input logic [2:0] control,
    output word_t Memory_Data,
    output logic skip,
	output dbus_req_t  dreq,
	input  dbus_resp_t dresp,
    input logic [6:0] flush_in,
    output logic flush_out//是否正在等待数据
    );
    
    logic [63:0] real_data;
    logic [2:0]  control_lock;
    logic [2:0] Address_lock;

    enum logic [3:0] {
        IDLE,
        REQUEST_SENT,
        RESPONSE_RECEIVED
    } state=IDLE;

    //assign flush_out= dreq.valid && ~dresp.data_ok;//是否在等待数据送来，主要用这个0    

    always_ff @(posedge clk)
    begin
        unique case(state)
        
            IDLE:
            begin
                if(flush_in==0 && ~E)
                    skip<=0;
                else;

                if(flush_in==0 && E)
                begin
                    dreq.valid<=1;
                    dreq.addr<=Address;
                    control_lock<=control;
                    Address_lock<=Address[2:0];
                    flush_out<=1;
                    skip<=~Address[31];

                    if(WE)
                    begin
                        case(control[1:0])
                            2'b00:dreq.strobe<=8'h01<<(Address[2:0]);
                            2'b01:dreq.strobe<=8'h03<<(Address[2:0]);
                            2'b10:dreq.strobe<=8'h0f<<(Address[2:0]);
                            2'b11:dreq.strobe<=8'hff;
                        endcase
                        case(control[1:0])//修正输入数据
                            2'b00:dreq.data<=Data_in<<(8*Address[2:0]);
                            2'b01:dreq.data<=Data_in<<(8*Address[2:0]);
                            2'b10:dreq.data<=Data_in<<(8*Address[2:0]);
                            2'b11:dreq.data<=Data_in;
                        endcase
                    end
                    else
                        dreq.strobe<=8'h00;

                    case(control[1:0])
                        2'b00:dreq.size<=MSIZE1;
                        2'b01:dreq.size<=MSIZE2;
                        2'b10:dreq.size<=MSIZE4;
                        2'b11:dreq.size<=MSIZE8;
                    endcase
                    

                    state<=REQUEST_SENT;
                end
                else;
            end

            REQUEST_SENT:
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
                            2'b00:real_data=dresp.data>>(8*Address_lock);
                            2'b01:real_data=dresp.data>>(8*Address_lock);
                            2'b10:real_data=dresp.data>>(8*Address_lock);
                            default:;
                        endcase
                        case(control_lock[1:0])
                            2'b00:Memory_Data<={{56{real_data[ 7]&~control_lock[2]}},real_data[ 7:0]};
                            2'b01:Memory_Data<={{48{real_data[15]&~control_lock[2]}},real_data[15:0]};
                            2'b10:Memory_Data<={{32{real_data[31]&~control_lock[2]}},real_data[31:0]};
                            2'b11:Memory_Data<=dresp.data;
                        endcase
                    end

                    state<=RESPONSE_RECEIVED;
                end
                else;
            end

            RESPONSE_RECEIVED:
            begin
                flush_out<=0;
                state<=IDLE;
            end

            default:;

        endcase
    end


endmodule