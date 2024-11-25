`ifndef VERILATOR
`define VERILATOR
`endif

`ifdef VERILATOR
`include "include/common.sv"
`include "include/config.sv"
`else

`endif 

module ALU_mul (
    input logic clk,reset,valid,
    input logic[63:0] a,b,
    output logic ok, //握手信号，算完后维持1个周期
    output logic error,
    output logic[63:0] c //c=a*b
);
    enum logic {INIT,DOING}state=INIT,state_nxt;//状态
    logic[65:0] count,count_nxt;//计数器

    always_ff @(posedge clk) //每个时间周期更新状态和计数器
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
        unique case(state)
            INIT:begin
                if(valid) //启动
                begin
                    error=1;
                    state_nxt=DOING;
                    count_nxt={1'b0,1'b1,64'b0};
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
                    state_nxt=DOING;
                end
            end
        endcase
    end

    logic[128:0] p, p_nxt;//存储乘法结果
    always_comb //确定下一个状态
    begin
        p_nxt=p;//默认保持
        unique case(state)
            INIT: begin //启动
                p_nxt={65'b0,a};
            end
            DOING: begin
                if(p_nxt[0]) 
                begin
                    p_nxt[128:64]=p_nxt[127:64]+b;
            	end
            	p_nxt=p_nxt>>1;
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
            if(valid && ~(state==DOING && state_nxt==INIT))//不要影响别人（除法器）
                c<=p_nxt[63:0];
        end
    end

endmodule