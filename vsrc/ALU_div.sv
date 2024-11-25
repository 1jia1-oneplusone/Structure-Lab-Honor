`ifndef VERILATOR
`define VERILATOR
`endif

`ifdef VERILATOR
`include "include/common.sv"
`include "include/config.sv"
`else

`endif 

module ALU_div(
    input logic clk,reset,valid,
    input [63:0] a_in,b_in,
    input uors,//符号选择，0为无符号，1为有符号
    input w,//是否单字，0为双字，1为单字
    output logic ok, //握手信号，算完后维持1个周期
    output logic error, //还在算信号
    output logic[127:0] c //c={a%b,a/b}
);
    enum logic {INIT,DOING}state=INIT,state_nxt;//状态
    logic[66:0] count,count_nxt;//计数器
    logic sign,sign2;//最终结果的符号
    logic [63:0] a,b;//a、b的绝对值，用于正式计算
    
    always_ff @(posedge clk) 
    begin
        if(reset|~valid) //如果没有保持valid，就直接掐断
            {state,count}<='0;
        else
            {state,count}<={state_nxt,count_nxt};
    end

    assign ok=(state==DOING && state_nxt==INIT);
    always_comb //确定下一个状态
    begin
        {state_nxt,count_nxt}={state,count};//默认保持
        error=0;
        a=0;
        b=0;
        sign=0;
        sign2=0;
        if(state==INIT && valid || state==DOING && count_nxt!='0)
        begin
            if(b_in==64'b0 || b_in[31:0]==32'b0&&w)//除数为0
            begin
                a=a_in;
                b=b_in;
            end
            else
            begin
                if(w)//单字
                begin
                    sign= (a_in[31]^b_in[31]) & uors;//商的符号
                    sign2= a_in[31];//余数的符号
                    a= {32'b0 , (a_in[31]&uors) ? -a_in[31:0] : a_in[31:0]};//取绝对值
                    b= {32'b0 , (b_in[31]&uors) ? -b_in[31:0] : b_in[31:0]};//取绝对值
                end
                else//双字
                begin
                    sign= (a_in[63]^b_in[63]) & uors;//商的符号
                    sign2= a_in[63];//余数的符号
                    a= (a_in[63]&uors) ? -a_in : a_in;//取绝对值
                    b= (b_in[63]&uors) ? -b_in : b_in;//取绝对值
                end
            end
        end


        unique case(state)//状态机
            INIT:begin
                if(valid) //启动
                begin
                    if(b_in==64'b0 || b_in[31:0]==32'b0&&w)//除数为0
                        count_nxt=1;
                    else
                        count_nxt={2'b0,1'b1,64'b0};
                    error=1;
                    state_nxt=DOING;
                end
            end
            DOING: begin
                count_nxt=count_nxt>>1;//计数器--
                if(count_nxt=='0)//到次数了,算完了
                begin
                    error=0;
                    state_nxt=INIT;
                end
                else
                begin
                    error=1;
                end
            end
        endcase
    end

    logic[128:0] p, p_nxt;//存储除法结果
    always_comb //确定下一个状态
    begin
        p_nxt=p;//默认保持
        unique case(state)
            INIT: begin //启动
                p_nxt={65'b0,a};
            end
            DOING: begin
            	p_nxt=p_nxt<<1;
                if(p_nxt[127:64]>=b)//上商为1（其实应该用恢复/不恢复余数法更合理一点） 
                begin
                    p_nxt[127:64]-=b;
                    p_nxt[0]=1'b1;
                end
            end
        endcase
    end

    always_ff @(posedge clk) //每个时钟周期更新p
    begin
        if(reset)
            p<=0;
        else
        begin
            p<=p_nxt;
            if(valid && ~(state==DOING && state_nxt==INIT))//不要影响别人（乘法器）
            begin
                if(b==64'b0 || b[31:0]==32'b0&&w)//除数为0
                begin
                    c<={a,64'hffffffffffffffff};
                end
                else
                begin
                    if(~uors)//无符号除法
                        c<=p_nxt[127:0];
                    else //有符号除法
                        c<={(sign2? -p_nxt[127:64] : p_nxt[127:64]) , (sign? -p_nxt[63:0] : p_nxt[63:0])};
                end
            end
        end
    end

endmodule