`include "../00_TB/define.v"

module core #( // DO NOT MODIFY INTERFACE!!!
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32
) ( 
    input i_clk,
    input i_rst_n,

    // Testbench IOs
    output [2:0] o_status, 
    output       o_status_valid,

    // Memory IOs
    output [ADDR_WIDTH-1:0] o_addr,
    output [DATA_WIDTH-1:0] o_wdata,
    output                  o_we,
    input  [DATA_WIDTH-1:0] i_rdata
);

// ---------------------------------------------------------------------------
// Local Parameters
// ---------------------------------------------------------------------------
	
	// States
	localparam S_IDLE = 3'd0;
	localparam S_INST_FETCH = 3'd1;
	localparam S_INST_DECODE = 3'd2;
	localparam S_ALU = 3'd3;
	localparam S_LOAD_STORE = 3'd4;
	localparam S_WB_PC = 3'd5;
	localparam S_STATUS = 3'd6;
	localparam S_DONE = 3'd7;

	localparam ALU_ADD = 3'd0;
	localparam ALU_SUB = 3'd1;
	localparam ALU_SL = 3'd2;
	localparam ALU_SR = 3'd3;
	localparam ALU_FADD = 3'd4;
	localparam ALU_FSUB = 3'd5;
	localparam ALU_FCLASS = 3'd6;
	localparam ALU_FLESS = 3'd7;




// ---------------------------------------------------------------------------
// Wires and Registers
// ---------------------------------------------------------------------------
// ---- Add your own wires and registers here if needed ---- //
	reg [3:0] state, state_nxt;
	reg signed [13:0] PC, PC_nxt;
	reg [2:0] status, status_nxt;
	reg [DATA_WIDTH-1:0] inst, inst_nxt;
	reg [DATA_WIDTH-1:0] ImmGen;
	
	wire PC_out_of_range;
	wire signed [DATA_WIDTH-1:0] reg_rdata1, reg_rdata2;
	wire signed [DATA_WIDTH-1:0] reg_wdata;
	wire [DATA_WIDTH-1:0] alu_data;
	wire [DATA_WIDTH-1:0] data_mem_rdata, data_mem_wdata;
	wire [DATA_WIDTH-1:0] now_inst;
	wire [6:0] OPCODE;
	wire isEOF;
	wire alu_invalid, alu_done, alu_comp;
	reg is_float_reg, RegWrite, Branch, MemtoReg, MemWrite, ALUSrc, MemRead;
	reg [2:0] ALUOp;
	reg [1:0] ALUCtrl;


// ---------------------------------------------------------------------------
// Module Instantiations
// ---------------------------------------------------------------------------

	register_file reg0 (
		.i_clk(i_clk),
		.i_rst_n(i_rst_n),
		.i_wen(RegWrite && state == S_WB_PC),
		.i_float(is_float_reg),
		.i_w_int(OPCODE==`OP_FADD && now_inst[31:25] == `FUNCT7_FCLASS),	// if FCLASS
		.i_r_int(OPCODE==`OP_FLW || OPCODE==`OP_FSW),	// if FLW or FSW
		.i_rs1(now_inst[19:15]),
		.i_rs2(now_inst[24:20]),
		.i_rd(now_inst[11:7]),
		.i_wdata(reg_wdata),
		.o_rdata1(reg_rdata1),
		.o_rdata2(reg_rdata2)
	);

	ALU alu0 (
		.i_clk(i_clk),
		.i_rst_n(i_rst_n),
		.i_valid(state == S_ALU),
		.i_data_a(reg_rdata1),
		.i_data_b((ALUSrc)? ImmGen:reg_rdata2),
		.i_ALUOp(ALUOp),
		.i_ALUctrl(ALUCtrl),
		.o_data(alu_data),
		.o_comp(alu_comp),
		.o_invalid(alu_invalid),
		.o_done(alu_done)
	);


// ---------------------------------------------------------------------------
// Continuous Assignment
// ---------------------------------------------------------------------------
// ---- Add your own wire data assignments here if needed ---- //
	// Data memory
	assign o_addr = (state == S_INST_FETCH)? PC: alu_data[ADDR_WIDTH-1:0];
	assign o_wdata = reg_rdata2;
	assign o_we = (state == S_LOAD_STORE && MemWrite)? 1:0;
	// aluctrl = 1 for blt, slt, flt. But RegWrite = 0 for blt
	assign reg_wdata = (MemtoReg)? i_rdata: ((ALUCtrl == 1)? alu_comp : alu_data);
	assign o_status_valid = (state == S_STATUS)? 1:0;
	assign o_status = status;
	assign now_inst = (state == S_INST_DECODE)? inst_nxt: inst;
	assign OPCODE = now_inst[6:0];
	assign isEOF = (OPCODE == `OP_EOF)? 1:0;
	assign PC_out_of_range = (PC > 4095 || PC < 0)? 1:0;
	



// ---------------------------------------------------------------------------
// Combinational Blocks
// ---------------------------------------------------------------------------
// ---- Write your conbinational block design here ---- //

	// PC
	always @(*) begin
		PC_nxt = PC;
		if(state==S_WB_PC) begin
			PC_nxt = (Branch && alu_comp)? PC + (ImmGen): PC + 4;
		end
	end
	// Inst fetch
	always @(*) begin
		inst_nxt = inst;
		if(state == S_INST_DECODE) begin
			inst_nxt = i_rdata;
		end
	end
	// Control signals
	always @(*) begin
		Branch = (OPCODE==`OP_BEQ || OPCODE==`OP_BLT)? 1:0;
		RegWrite = (OPCODE==`OP_ADD || OPCODE==`OP_ADDI || OPCODE==`OP_LW || OPCODE==`OP_FADD || OPCODE==`OP_FLW)? 1:0;
		MemtoReg = (OPCODE==`OP_LW || OPCODE==`OP_FLW)? 1:0;
		MemWrite = (OPCODE==`OP_SW || OPCODE==`OP_FSW)? 1:0;
		ALUSrc = (OPCODE==`OP_ADDI || OPCODE==`OP_LW || OPCODE==`OP_SW || OPCODE==`OP_FLW || OPCODE==`OP_FSW)? 1:0;
		is_float_reg = (OPCODE==`OP_FADD || OPCODE==`OP_FLW || OPCODE==`OP_FSW)? 1:0;
		MemRead = (OPCODE==`OP_LW || OPCODE==`OP_FLW)? 1:0;
		ALUCtrl = 3;
		ALUOp = ALU_ADD;
		if(OPCODE==`OP_ADD) begin	// R type
			if(now_inst[31:25] == `FUNCT7_ADD)	begin// ADD, SLT, SLL, SRL
				if(now_inst[14:12] == `FUNCT3_ADD) begin	// ADD
					ALUOp = ALU_ADD;
				end
				else if(now_inst[14:12] == `FUNCT3_SLT) begin	// SLT
					ALUOp = ALU_SUB;
					ALUCtrl = 1;
				end
				else if(now_inst[14:12] == `FUNCT3_SLL) begin // SLL
					ALUOp = ALU_SL;
				end
				else if(now_inst[14:12] == `FUNCT3_SRL) begin	// SRL
					ALUOp = ALU_SR;
				end
			end
			else if(now_inst[31:25] == `FUNCT7_SUB) begin	// SUB
				ALUOp = ALU_SUB;
			end
		end
		else if(OPCODE==`OP_ADDI) begin	// ADDI, LW, SW, FLW, FSW
			ALUOp = ALU_ADD;
		end
		else if(OPCODE==`OP_LW || OPCODE==`OP_SW || OPCODE == `OP_FSW || OPCODE == `OP_FLW) begin
			ALUOp = ALU_ADD;
			ALUCtrl = 2;
		end
		else if(OPCODE==`OP_BEQ) begin// BEQ, BLT
			ALUOp = ALU_SUB;
			if(now_inst[14:12] == `FUNCT3_BEQ) begin	// BEQ
				ALUCtrl = 0;
			end
			else if(now_inst[14:12] == `FUNCT3_BLT) begin	// BLT
				ALUCtrl = 1;
			end
		end
		else if (OPCODE==`OP_FADD) begin	// FADD, FSUB, FCLASS, FLT
			if(now_inst[31:25] == `FUNCT7_FADD) begin	// FADD
				ALUOp = ALU_FADD;
			end
			else if(now_inst[31:25] == `FUNCT7_FSUB) begin	// FSUB
				ALUOp = ALU_FSUB;
			end
			else if(now_inst[31:25] == `FUNCT7_FCLASS) begin	// FCLASS
				ALUOp = ALU_FCLASS;
			end
			else if(now_inst[31:25] == `FUNCT7_FLT) begin	// FLT
				ALUOp = ALU_FLESS;
			end
		
		end
	end
	// ImmGen and status
	always @(*) begin
		ImmGen = 0;
		status_nxt = status;
		if(OPCODE == `OP_ADDI || OPCODE == `OP_LW || OPCODE == `OP_FLW) begin // I type
			ImmGen = {{20{now_inst[31]}}, now_inst[31:20]};
			if(state == S_INST_DECODE)
				status_nxt = 1;
		end
		else if (OPCODE == `OP_SW || OPCODE == `OP_FSW) begin	// S type
			ImmGen = {{20{now_inst[31]}}, now_inst[31:25], now_inst[11:7]};
			if(state == S_INST_DECODE)
				status_nxt = 2;
		end
		else if (OPCODE == `OP_BEQ) begin	// B type
			ImmGen = {{19{now_inst[31]}}, now_inst[31], now_inst[7], now_inst[30:25], now_inst[11:8], 1'b0};
			if(state == S_INST_DECODE)
				status_nxt = 3;
		end
		else begin
			if(state == S_INST_DECODE)
				status_nxt = 0;
		end
		if(isEOF) begin
			status_nxt = 5;
		end
		else if(alu_invalid || PC_out_of_range) begin
			status_nxt = 4;
		end
	end


	//FSM
	always @(*) begin
		case(state)
			S_IDLE: begin
				state_nxt = S_INST_FETCH;
			end
			S_INST_FETCH: begin
				state_nxt = S_INST_DECODE;
				if(PC_out_of_range) begin
					state_nxt = S_DONE;
				end
			end
			S_INST_DECODE: begin
				if(isEOF)	state_nxt = S_STATUS;
				else state_nxt = S_ALU;
			end
			S_ALU: begin
				if(alu_invalid) state_nxt = S_STATUS;
				else if(alu_done) begin
					if(MemWrite || MemRead) state_nxt = S_LOAD_STORE;
					else state_nxt = S_WB_PC;
				end
			end
			S_LOAD_STORE: begin
				state_nxt = S_WB_PC;
			end
			S_WB_PC: begin
				state_nxt = S_STATUS;
			end
			S_STATUS: begin
				if(status == 4 || status == 5)	state_nxt = S_DONE;
				else state_nxt = S_INST_FETCH;
			end
			S_DONE: begin
				state_nxt = S_DONE;
			end
		endcase
	end

// ---------------------------------------------------------------------------
// Sequential Block
// ---------------------------------------------------------------------------
// ---- Write your sequential block design here ---- //
	always @(posedge i_clk or negedge i_rst_n) begin
		if(!i_rst_n) begin
			inst <= 0;
			PC <= 0;
			status <= 0;
			state <= S_IDLE;
		end
		else begin
			inst <= inst_nxt;
			PC <= PC_nxt;
			status <= status_nxt;
			state <= state_nxt;
		end
	end

endmodule

module ALU #(
	parameter DATA_WIDTH = 32,
	parameter EXP_WIDTH = 8,
	parameter MAN_WIDTH = 23
) (
	input i_clk,
	input i_rst_n,
	input i_valid,
	input signed [DATA_WIDTH-1: 0] i_data_a,
	input signed [DATA_WIDTH-1: 0] i_data_b,
	input [2:0] i_ALUOp,
	input [1:0] i_ALUctrl,
	output [DATA_WIDTH-1: 0] o_data,
	output o_comp,
	output o_invalid,
	output o_done
);
	localparam ALU_ADD = 3'd0;
	localparam ALU_SUB = 3'd1;
	localparam ALU_SL = 3'd2;
	localparam ALU_SR = 3'd3;
	localparam ALU_FADD = 3'd4;
	localparam ALU_FSUB = 3'd5;
	localparam ALU_FCLASS = 3'd6;
	localparam ALU_FLESS = 3'd7;

	localparam S_IDLE = 3'd0;
	localparam S_SHIFT = 3'd1;
	localparam S_OUT = 3'd2;
	localparam S_INVALID = 3'd3;

	reg [2:0] state, state_nxt;
	reg signed [DATA_WIDTH: 0] o_data_reg, o_data_nxt;
	reg o_comp_reg, o_comp_nxt;
	reg [25:0] mant_sum, mant_sum_nxt, mant_sum_tmp;
	reg result_sign, result_sign_nxt;
	reg [8:0] exp_result, exp_result_nxt;
	reg shift_done, invalid, overflow;

	// for floating point calculation
	wire sign_a, sign_b;
	wire [7:0] exp_a, exp_b, exp_diff, exp_bigger;
	wire [24:0] mant_a, mant_b, mant_a_shifted, mant_b_shifted;
	wire INFNaN, abzero;

	assign sign_a = i_data_a[DATA_WIDTH-1];
	assign sign_b = (i_ALUOp == ALU_FSUB)? ~i_data_b[DATA_WIDTH-1]: i_data_b[DATA_WIDTH-1];
	assign exp_a = i_data_a[30:23];
	assign exp_b = i_data_b[30:23];
	assign exp_diff = (exp_a > exp_b) ? (exp_a - exp_b) : (exp_b - exp_a);
	assign exp_bigger = (exp_a > exp_b)? exp_a: exp_b;
	assign mant_a = (exp_a == 8'b0)? {i_data_a[22:0], 1'b0, 1'b0} : {1'b1, i_data_a[22:0], 1'b0}; // Implicit leading 1 for normalized numbers
	assign mant_b = (exp_b == 8'b0)? {i_data_b[22:0], 1'b0, 1'b0} : {1'b1, i_data_b[22:0], 1'b0}; // Implicit leading 1 for normalized numbers
	assign mant_a_shifted = (exp_a >= exp_b) ? {mant_a} : (mant_a >> exp_diff);
  assign mant_b_shifted = (exp_b >= exp_a) ? {mant_b} : (mant_b >> exp_diff);
	// INPNaN will only be true for FADD, FSUB, FLESS
	assign INFNaN = (i_ALUOp == ALU_FADD || i_ALUOp == ALU_FSUB || i_ALUOp == ALU_FLESS) && ((exp_a == 8'b11111111) || (exp_b == 8'b11111111));
	assign abzero = (i_ALUOp == ALU_FADD || i_ALUOp == ALU_FSUB) && ((i_data_a[DATA_WIDTH-2:0] == {(DATA_WIDTH-1){1'b0}}) || (i_data_b[DATA_WIDTH-2:0] == {(DATA_WIDTH-1){1'b0}}));

	//! need modify(won't hold value to the next clock)
	assign o_invalid = (state == S_INVALID);
	assign o_data = o_data_reg[DATA_WIDTH-1:0];
	assign o_done = (state == S_OUT || state == S_INVALID);
	assign o_comp = o_comp_reg;

	integer j;

	// FSM
	always @(*) begin
		state_nxt = state;
		case(state)
			S_IDLE: begin
				if(i_valid) begin
					if((i_ALUOp == ALU_FADD || i_ALUOp == ALU_FSUB) && !INFNaN && !abzero) begin	// if abzeor: state_nxt = S_OUT
						state_nxt = S_SHIFT;
					end
					else
						state_nxt = S_OUT;
					if(overflow || INFNaN)
						state_nxt = S_INVALID;
				end
			end
			S_SHIFT: begin
				if(shift_done) begin
					state_nxt = S_OUT;
				end
				if(overflow)
					state_nxt = S_INVALID;
			end
			S_INVALID: begin
				state_nxt = S_IDLE;
			end
			S_OUT: begin
				state_nxt = S_IDLE;
			end
		endcase
	end

	always @(*) begin
		o_data_nxt = o_data_reg;
		overflow = 0;
		o_comp_nxt = o_comp_reg;
		result_sign_nxt = result_sign;
		shift_done = 0;
		mant_sum_nxt = mant_sum;
		mant_sum_tmp = mant_sum;
		exp_result_nxt = exp_result;
		//! need modify if(i_valid)
		if(i_valid && state == S_IDLE) begin
			o_comp_nxt = 0;
			case(i_ALUOp)
				ALU_ADD: begin
					o_data_nxt = i_data_a + i_data_b;
					if((i_data_a[DATA_WIDTH-1] == i_data_b[DATA_WIDTH-1]) && (i_data_a[DATA_WIDTH-1] != o_data_nxt[DATA_WIDTH-1])) begin
						overflow = 1;
					end
					else if(i_ALUctrl == 2 && (o_data_nxt > 8191 || o_data_nxt < 4096)) begin	// address out of range
						overflow = 1;
					end
				end
				ALU_SUB: begin
					o_data_nxt = i_data_a - i_data_b;
					if(i_ALUctrl == 0) begin
						o_comp_nxt = (o_data_nxt == 0)? 1:0;
					end
					else if(i_ALUctrl == 1) begin
						if(i_data_a[DATA_WIDTH-1] == i_data_b[DATA_WIDTH-1]) begin	// no overflow
							if(o_data_nxt[DATA_WIDTH-1] == 1)	// a-b < 0--> a < b
								o_comp_nxt = 1;
						end
						else if(i_data_a[DATA_WIDTH-1] == 1 && i_data_b[DATA_WIDTH-1] == 0) // a neg, b pos --> a < b
							o_comp_nxt = 1;
					end
					else begin	// aluctrl = 3
						// o_data_nxt = o_data_tmp;
						if((i_data_a[DATA_WIDTH-1] != i_data_b[DATA_WIDTH-1]) && i_data_a[DATA_WIDTH-1] != o_data_nxt[DATA_WIDTH-1]) begin
							overflow = 1;
						end
					end
					
				end
				ALU_SL: begin
					o_data_nxt = i_data_a << $unsigned(i_data_b);
				end
				ALU_SR: begin
					o_data_nxt = i_data_a >> $unsigned(i_data_b);
				end
				ALU_FADD, ALU_FSUB: begin
					// a == 0 or b == 0
					if(i_data_a[DATA_WIDTH-2:0] == {(DATA_WIDTH-1){1'b0}}) begin
						o_data_nxt = i_data_b;
						shift_done = 1;
					end
						
					else if(i_data_b[DATA_WIDTH-2:0] == {(DATA_WIDTH-1){1'b0}}) begin
						o_data_nxt = i_data_a;
						shift_done = 1;
					end
					else if(!INFNaN) begin
						if (sign_a == sign_b) begin // a and b same sign: add mantissas
							mant_sum_tmp = mant_a_shifted + mant_b_shifted;
							result_sign_nxt = sign_a;
						end
						else begin // Different signs: Subtract mantissas (bigger substract smaller)
							if (mant_a_shifted > mant_b_shifted) begin
								mant_sum_tmp = mant_a_shifted - mant_b_shifted;
								result_sign_nxt = sign_a;
							end else begin
								mant_sum_tmp = mant_b_shifted - mant_a_shifted;
								result_sign_nxt = sign_b;
							end
    				end
						if(mant_sum_tmp[25] == 1'b1) begin
							exp_result_nxt = exp_bigger + 1;
							mant_sum_nxt = mant_sum_tmp >> 1;
							if(exp_result_nxt == 255) begin
								overflow = 1;
							end
						end
						else begin
							exp_result_nxt = exp_bigger;
							mant_sum_nxt = mant_sum_tmp;
						end

					end
				end
				ALU_FCLASS: begin
					if(exp_a == 255 && mant_a != 0) o_data_nxt = `FLOAT_NAN;
					else if(sign_a == 0) begin // positive
						if(exp_a > 0 && exp_a < 255) o_data_nxt = `FLOAT_POS_NORM;
						else if(exp_a == 255 && mant_a == 0) o_data_nxt = `FLOAT_POS_INF;
						else if(exp_a == 0 && mant_a == 0) o_data_nxt = `FLOAT_POS_ZERO;
						else o_data_nxt = `FLOAT_POS_SUBNORM;
					end
					else begin	// negative
						if(exp_a > 0 && exp_a < 255) o_data_nxt = `FLOAT_NEG_NORM;
						else if(exp_a == 255 && mant_a == 0) o_data_nxt = `FLOAT_NEG_INF;
						else if(exp_a == 0 && mant_a == 0) o_data_nxt = `FLOAT_NEG_ZERO;
						else o_data_nxt = `FLOAT_NEG_SUBNORM;
					end
				end
				ALU_FLESS: begin
					// both a, b = 0
					o_comp_nxt = 0;
					if((i_data_a[DATA_WIDTH-2:0] == {(DATA_WIDTH-1){1'b0}}) && (i_data_b[DATA_WIDTH-2:0] == {(DATA_WIDTH-1){1'b0}}))
						o_comp_nxt = 0;
					else if(sign_a == 1 && sign_b == 0) begin	// a<0, b>0
						o_comp_nxt = 1;
					end
					else if(sign_a == 0 && sign_b == 1) begin // a>0, b<0
						o_comp_nxt = 0;
					end
					else if(sign_a == 0 && sign_b == 0) begin	// a, b>0
						if(exp_a > exp_b) begin
							o_comp_nxt = 0;
						end
						else if(exp_a < exp_b) begin
							o_comp_nxt = 1;
						end
						else begin									// same exponent
							if(mant_a >= mant_b) begin	
								o_comp_nxt = 0;
							end
							else begin
								o_comp_nxt = 1;
							end
						end
					end
					else if(sign_a == 1 && sign_b == 1) begin
						if(exp_a > exp_b) begin
							o_comp_nxt = 1;
						end
						else if(exp_a < exp_b) begin
							o_comp_nxt = 0;
						end
						else begin
							if(mant_a > mant_b) begin
								o_comp_nxt = 1;
							end
							else begin
								o_comp_nxt = 0;
							end
						end
					end
				end
			endcase
		end
		// shift
		else if(state == S_SHIFT) begin
			if(mant_sum == 0) begin	// mantissa all 0
				shift_done = 1;
			end
			else if(exp_result == 0) begin	// can be shift no more
				shift_done = 1;
			end
			else if(mant_sum[24] == 1) begin	// find 1
				shift_done = 1;
			end
			else if(exp_result >= 1) begin		// not 1 but can still be shifted
				mant_sum_nxt = mant_sum << 1;
				exp_result_nxt = exp_result - 1;
			end
			if(shift_done) begin // shift done, start rounding
				if(exp_result == 0) begin		// take m to be mant[24:2]
					if(mant_sum[1:0] == 2'b11 || mant_sum[2:1] == 2'b11) begin	// increase
						mant_sum_nxt = (mant_sum + 3'b100) >> 1;
						if(mant_sum_nxt[24] == 1) begin
							exp_result_nxt = 1;
						end
					end
				end
				else if(mant_sum[1:0] == 2'b11) begin	// m is mant[23:1]
					mant_sum_tmp = mant_sum + 2'b10;
					if(mant_sum_nxt[25] == 1) begin
						if(exp_result == 254) begin
							overflow = 1;
						end
						else begin
							exp_result_nxt = exp_result + 1;
							mant_sum_nxt = mant_sum_tmp >> 1;
						end
					end
					else
						mant_sum_nxt = mant_sum_tmp;
				end
				o_data_nxt = {result_sign, exp_result_nxt[7:0], mant_sum_nxt[23:1]};
			end
		
			
		end
	end


	always @(posedge i_clk or negedge i_rst_n) begin
		if(!i_rst_n) begin
			state <= S_IDLE;
			o_data_reg <= 0;
			mant_sum <= 0;
			o_comp_reg <= 0;
			result_sign <= 0;
			exp_result <= 0;
		end
		else begin
			state <= state_nxt;
			o_data_reg <= o_data_nxt; 
			mant_sum <= mant_sum_nxt;
			result_sign <= result_sign_nxt;
			exp_result <= exp_result_nxt;
			o_comp_reg <= o_comp_nxt;
		end
	end
endmodule

// module Program_counter #(
// 	parameter MAX_ADDR = 1023,
// 	parameter MIN_ADDR = 0
// ) (
// 	input i_clk,
// 	input i_rst_n,
// 	input 
// );
	
// endmodule