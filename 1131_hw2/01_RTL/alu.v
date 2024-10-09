`include "../00_TB/define.v"

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
	reg signed [DATA_WIDTH: 0] o_data_reg, o_data_nxt, o_data_tmp;
	reg o_comp_reg, o_comp_nxt;
	reg [49:0] mant_sum, mant_sum_nxt, mant_sum_tmp;
	reg result_sign, result_sign_nxt;
	reg [8:0] exp_result, exp_result_nxt;
	reg shift_done, invalid, overflow;

	// for floating point calculation
	wire sign_a, sign_b;
	wire [7:0] exp_a, exp_b, exp_diff, exp_bigger;
	wire [48:0] mant_a, mant_b;
	reg [48:0] mant_a_shifted, mant_b_shifted;
	reg sticky;
	wire INFNaN, abzero;

	assign sign_a = i_data_a[DATA_WIDTH-1];
	assign sign_b = (i_ALUOp == ALU_FSUB)? ~i_data_b[DATA_WIDTH-1]: i_data_b[DATA_WIDTH-1];
	assign exp_a = i_data_a[30:23];
	assign exp_b = i_data_b[30:23];
	assign exp_diff = (exp_a > exp_b) ? (exp_a - exp_b) : (exp_b - exp_a);
	assign exp_bigger = (exp_a > exp_b)? exp_a: exp_b;
	assign mant_a = (exp_a == 8'b0)? {i_data_a[22:0], 1'b0, 25'b0} : {1'b1, i_data_a[22:0], 25'b0}; // Implicit leading 1 for normalized numbers
	assign mant_b = (exp_b == 8'b0)? {i_data_b[22:0], 1'b0, 25'b0} : {1'b1, i_data_b[22:0], 25'b0}; // Implicit leading 1 for normalized numbers

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

	// manta, mantb shifted
	always @(*) begin
		sticky = 0;
		if(exp_a >= exp_b) begin
			if(exp_diff > 25 && exp_diff < 48) begin
				sticky = |(mant_b << (49-exp_diff));
			end
			else if(exp_diff >= 48) begin
				sticky = |mant_b;
			end
			mant_a_shifted = mant_a;
			mant_b_shifted = (mant_b >> exp_diff) | {{48'b0}, sticky};
		end
		else begin
			if(exp_diff > 25 && exp_diff < 48) begin
				sticky = |(mant_a << (49-exp_diff));
			end
			else if(exp_diff >= 48) begin
				sticky = |mant_a;
			end
			mant_a_shifted = (mant_a >> exp_diff) | {{48'b0}, sticky};
			mant_b_shifted = mant_b;
		end

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
						// if(i_data_a < i_data_b) begin
						// 	o_comp_nxt = 1;
						// end
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
					o_data_nxt = $unsigned(i_data_a) >> $unsigned(i_data_b);
				end
				ALU_FADD, ALU_FSUB: begin
					// a == 0 or b == 0
					if(i_data_a[DATA_WIDTH-2:0] == {(DATA_WIDTH-1){1'b0}}) begin
						if(i_data_b[DATA_WIDTH-2:0] == {(DATA_WIDTH-1){1'b0}})	// a==0, b==0
							o_data_nxt = {(DATA_WIDTH-1){1'b0}};
						else
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
						if(mant_sum_tmp[49] == 1'b1) begin
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
						if(exp_a < exp_b || (exp_a == exp_b && mant_a < mant_b)) begin
							o_comp_nxt = 1;
						end
					end
					else if(sign_a == 1 && sign_b == 1) begin	// a, b<0
						if(exp_a > exp_b || (exp_a == exp_b && mant_a > mant_b)) begin
							o_comp_nxt = 1;
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
			else if(mant_sum[48] == 1) begin	// find 1
				shift_done = 1;
			end
			else if(exp_result >= 1) begin		// not 1 but can still be shifted
				mant_sum_nxt = mant_sum << 1;
				exp_result_nxt = exp_result - 1;
			end
			if(shift_done) begin // shift done, start rounding
				if(exp_result == 0) begin		// take m to be mant[48:26]
					if({mant_sum[25], {|mant_sum[24:0]}} == 2'b11 || mant_sum[26:25] == 2'b11) begin	// increase
						mant_sum_nxt = (mant_sum + (1'b1 << 25)) >> 1;
						if(mant_sum_nxt[48] == 1) begin
							exp_result_nxt = 1;
						end
					end
					else begin
						mant_sum_nxt = mant_sum >> 1;
					end
				end
				else if({mant_sum[24], {|mant_sum[23:0]}} == 2'b11 || mant_sum[25:24] == 2'b11) begin	// m is mant[47:25]
					mant_sum_tmp = mant_sum + (1'b1 << 24);
					if(mant_sum_nxt[49] == 1) begin
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
				if(exp_result_nxt == 0 && mant_sum_nxt == 0)
					o_data_nxt = {(DATA_WIDTH-1){1'b0}};
				else
					o_data_nxt = {result_sign, exp_result_nxt[7:0], mant_sum_nxt[47:25]};
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