`ifndef VERILATOR
`define VERILATOR
`endif

`ifdef VERILATOR
`include "include/common.sv"
`include "include/config.sv"
`else

`endif 

module ALU(
    input logic clk,reset,
    input [31:0] instr,
    input [63:0] A,B,
    input [11:0] control,//(noimm(1) or imm(1)) _ (q(0) or w(1)) _ funct7[6:0] _ funct3[2:0]
    output logic BRANCH,
    output logic [63:0] Result,

    input logic[6:0] flush_in,
    output logic flush_out
    );
    parameter ADD=4'b0000,SUB=4'b1000,SLL=4'b0001,SLT=4'b0010,
                SLTU=4'b0011,XOR=4'b0100,SRL=4'b0101,SRA=4'b1101,
                OR=4'b0110,AND=4'b0111,ALUB=4'b1111;
    parameter JAL=7'b1101111,JALR=7'b1100111,B__=7'b1100011,
                BEQ=3'b000,BNE=3'b001,BLT=3'b100,BGE=3'b101,BLTU=3'b110,BGEU=3'b111;
    
    logic signed [63:0] sA,sB;
    logic signed [31:0] sAw;
    logic [63:0]out,out2,out3,out4;//取余、除法、乘法分别用out2~4，一人一双筷子
    logic [63:0]outw;
    logic ZF,SF,CF,OF;
    logic [11:0]control_lock;
    logic [6:0]opcode_lock;
    
    assign sA=A;
    assign sB=B;
    assign sAw=A[31:0];

    logic valid_mul,valid_div, ok_mul,ok_div, error_mul,error_div, valid,ok;

    enum logic [3:0] {
        IDLE,
        WAIT,
        REQUEST_SENT,
        RESPONSE_RECEIVED
    } state;

    always @(posedge clk)
    begin
        case(state)
        
            IDLE:
            begin
                if(flush_in==0)
                begin
                    flush_out<=1;
                    state=WAIT;
                    BRANCH=0;
                end
                else;
            end

            WAIT:
            begin
                control_lock<=control;

                casez(control)
                    /*ADD  */ 12'b??0000000_000: out=A+B; 
                    /*SUB  */ 12'b??0100000_000: out=A-B; 
                    /*XOR  */ 12'b??0000000_100: out=A^B; 
                    /*OR   */ 12'b??0000000_110: out=A|B; 
                    /*AND  */ 12'b??0000000_111: out=A&B; 
                    /*ALUB */ 12'b??0100000_111: out=B;   
                    /*SLT  */ 12'b??0000000_010: out=sA<sB? 64'b1:64'b0; 
                    /*SLTU */ 12'b??0000000_011: out=A<B? 64'b1:64'b0; 

                    /*SLL  */ 12'b000000000_001: out=A<<B[5:0];
                    /*SLLI */ 12'b10000000?_001: out=A<<B[5:0];
                    /*SLLW */ 12'b?10000000_001: out=A<<B[4:0];//忽略第5位

                    /*SRL  */ 12'b000000000_101: out=A>>B[5:0];
                    /*SRLI */ 12'b10000000?_101: out=A>>B[5:0];
                    /*SRLW */ 12'b?10000000_101: out={32'b0,A[31:0]>>B[4:0]};//忽略第5位
                    
                    /*SRA  */ 12'b?0010000?_101: out=sA>>>B[5:0];
                    /*SRAW */ 12'b?10100000_101: out={32'b0,sAw>>>B[4:0]};//忽略第5位
                    
                    /*MUL  */ 12'b??0000001_000: valid_mul<=1;       //out4=A*B;
                    /*DIV  */ 12'b0?0000001_100: if(sB==64'b0 || sB[31:0]==32'b0&&control[10])out3=64'hffffffffffffffff;
                                                else valid_div<=1;  //out3=sA/sB;
                    /*DIVU */ 12'b0?0000001_101: if(B==64'b0 || B[31:0]==32'b0&&control[10]) out3=64'hffffffffffffffff;
                                                else valid_div<=1;  //out3=A/B;
                    /*REM  */ 12'b??0000001_110: if(sB==64'b0 || sB[31:0]==32'b0&&control[10])out2=sA;
                                                else valid_div<=1;  //out2=sA%sB;
                    /*REMU */ 12'b??0000001_111: if(B==64'b0 || B[31:0]==32'b0&&control[10]) out2=A;
                                                else valid_div<=1;  //out2=A%B;
                    /*ALUA */ default:           out=A;
                endcase


                if(control[10:0]==11'b00100000_000)//SUB
                begin
                    ZF=(out==64'h0);
                    SF=(out[63]);
                    CF=(A<B);
                    OF=((A[63]!=B[63])&&(out[63]!=A[63]));
                end
                else
                    {ZF,SF,CF,OF}=4'b0;

                case(instr[6:0])//设置BRANCH信号
                    B__: case(instr[14:12])
                            BEQ:     begin BRANCH=ZF;       end 
                            BNE:     begin BRANCH=~ZF;      end
                            BLT:     begin BRANCH=SF^OF;    end
                            BGE:     begin BRANCH=~(SF^OF); end
                            BLTU:    begin BRANCH=CF;       end
                            BGEU:    begin BRANCH=~CF;      end
                            default: begin BRANCH=1'b0;end
                        endcase
                    JAL: BRANCH=1;
                    default: BRANCH=0;
                endcase

                
                casez(control)//设置下一个状态
                    12'b??0000001_000,12'b0?0000001_100,12'b0?0000001_101,12'b??0000001_110,12'b??0000001_111:
                        state=REQUEST_SENT;
                    default: state=RESPONSE_RECEIVED;

                endcase
                
                
            end

            REQUEST_SENT://等待乘除法器
            begin
                if(ok_mul || ok_div)
                begin
                    valid_mul<=0;
                    valid_div<=0;
                    state=RESPONSE_RECEIVED;
                end
                else;
            end

            RESPONSE_RECEIVED:
            begin
                flush_out<=0;
                state=IDLE;

                //以下control[10]相关的分支用于OPW/OPIW单字运算的砍一半并扩展
                if(control_lock[9:0]==10'b0000001_000)//乘法
                    if(control_lock[10])//单字
                        Result= {{32{out4[31]}},out4[31:0]};
                    else//双字
                        Result= out4;
                else if({control_lock[11],control_lock[9:1]}==10'b00000001_10)//除法
                    if(control_lock[10])//单字
                        Result= {{32{out3[31]}},out3[31:0]};
                    else//双字
                        Result= out3;
                else if(control_lock[9:1]==9'b0000001_11)//取余
                    if(control[10])//单字
                        Result= {{32{out2[31]}},out2[31:0]};
                    else//双字
                        Result= out2;
                else //乘除余以外的运算不需要特别处理
                    if(control_lock[10])//单字
                        Result= {{32{out[31]}},out[31:0]};
                    else//双字
                        Result= out;
            end

            default:;

        endcase
    end

    ALU_mul mul(clk,reset,valid_mul, A,B, ok_mul,error_mul, out4);//乘法
    ALU_div div(clk,reset,valid_div, A,B, ~control[0],control[10], ok_div,error_div, {out2,out3});//除法&取余

    
endmodule
