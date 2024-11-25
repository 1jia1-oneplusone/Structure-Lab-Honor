`ifndef __CORE_SV
`define __CORE_SV

`ifdef VERILATOR
`include "include/common.sv"
`endif

module core import common::*;(
	input  logic       clk, reset,
	output ibus_req_t  ireq,
	input  ibus_resp_t iresp,
	output dbus_req_t  dreq,
	input  dbus_resp_t dresp,
	input  logic       trint, swint, exint
);
	/* TODO: Add your CPU-Core here. */
// ���ñ���
    //logic [31:0] writedata, dataadr;
	word_t _Reg[31:0],CSR[CSR_SIZE-1:0];//, _Reg_next[31:0];
	word_t reg_DI;
    //logic memwrite;
    
    //�����źű���
    logic WREG,ALU_B,BRANCH,OFFSET;
    logic [1:0]REG_DATA_INPUT;
    logic [6:0]SEXT;
    logic [3:0]ALUC;
	logic WMEM,skip;
    
    //logic [31:0]imm,ALU_result;
    logic [31:0]instr;
    logic [63:0]pc,newpc;
	//assign newpc=64'h00000000_80000000;
    
    logic ERROR,BLOCK,finish_W;
    
    // ������·
    top top(clk, reset, PCINIT, _Reg, CSR, reg_DI, WREG,/*ALU_B,BRANCH,OFFSET,REG_DATA_INPUT,SEXT,ALUC,imm,ALU_result,WMEM,*/skip,instr,pc,newpc,ERROR,BLOCK, ireq,iresp,dreq,dresp,trint,swint,exint,finish_W);
    


`ifdef VERILATOR
//给difftest传信号的核心原则：在指令恰好生效的时候，传递新的信号给difftest
	DifftestInstrCommit DifftestInstrCommit(
		.clock              (clk),
		.coreid             (0),
		.index              (0),
		.valid              (finish_W && ~BLOCK),
		.pc                 (pc),
		.instr              (instr),
		.skip               (skip),
		.isRVC              (0),
		.scFailed           (0),
		.wen                (WREG),
		.wdest              ({3'b0,instr[11:7]}),
		.wdata              (reg_DI)
	);

	DifftestArchIntRegState DifftestArchIntRegState (
		//通用寄存器堆
		//因为寄存器会在下一个周期才改变，所以如果直接提交寄存器，就会晚一步
		//所以可以提交reg_next(也就是打算在下一个周期提交的寄存器值)
		.clock              (clk),
		.coreid             (0),
		.gpr_0              (_Reg[0]),
		.gpr_1              (_Reg[1]),
		.gpr_2              (_Reg[2]),
		.gpr_3              (_Reg[3]),
		.gpr_4              (_Reg[4]),
		.gpr_5              (_Reg[5]),
		.gpr_6              (_Reg[6]),
		.gpr_7              (_Reg[7]),
		.gpr_8              (_Reg[8]),
		.gpr_9              (_Reg[9]),
		.gpr_10             (_Reg[10]),
		.gpr_11             (_Reg[11]),
		.gpr_12             (_Reg[12]),
		.gpr_13             (_Reg[13]),
		.gpr_14             (_Reg[14]),
		.gpr_15             (_Reg[15]),
		.gpr_16             (_Reg[16]),
		.gpr_17             (_Reg[17]),
		.gpr_18             (_Reg[18]),
		.gpr_19             (_Reg[19]),
		.gpr_20             (_Reg[20]),
		.gpr_21             (_Reg[21]),
		.gpr_22             (_Reg[22]),
		.gpr_23             (_Reg[23]),
		.gpr_24             (_Reg[24]),
		.gpr_25             (_Reg[25]),
		.gpr_26             (_Reg[26]),
		.gpr_27             (_Reg[27]),
		.gpr_28             (_Reg[28]),
		.gpr_29             (_Reg[29]),
		.gpr_30             (_Reg[30]),
		.gpr_31             (_Reg[31])

	);

    DifftestTrapEvent DifftestTrapEvent(
		.clock              (clk),
		.coreid             (0),
		.valid              (0),
		.code               (0),
		.pc                 (0),
		//.cycleCnt           (CSR[8]),
		.cycleCnt           (0),
		.instrCnt           (0)
	);

	DifftestCSRState DifftestCSRState(
		.clock              (clk),
		.coreid             (0),
		.priviledgeMode     (CSR[11][1:0]),
		//.priviledgeMode     (3),
		.mstatus            (CSR[0]),
		.sstatus            (0 /* mstatus & 64'h800000030001e000 */),
		.mepc               (CSR[7]),
		.sepc               (0),
		.mtval              (CSR[6]),
		.stval              (0),
		.mtvec              (CSR[1]),
		.stvec              (0),
		.mcause             (CSR[5]),
		.scause             (0),
		.satp               (CSR[9]),
		.mip                (CSR[2]),
		.mie                (CSR[3]),
		.mscratch           (CSR[4]),
		.sscratch           (0),
		.mideleg            (0),
		.medeleg            (CSR[10])
	);
`endif
endmodule
`endif