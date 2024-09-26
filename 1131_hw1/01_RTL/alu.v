module alu #(
    parameter INST_W = 4,
    parameter INT_W  = 6,
    parameter FRAC_W = 10,
    parameter DATA_W = INT_W + FRAC_W
)(
    input                      i_clk,
    input                      i_rst_n,

    input                      i_in_valid,
    output                     o_busy,
    input         [INST_W-1:0] i_inst,
    input  signed [DATA_W-1:0] i_data_a,
    input  signed [DATA_W-1:0] i_data_b,

    output                     o_out_valid,
    output        [DATA_W-1:0] o_data
);

    // Local Parameters
	localparam I_ADD = 4'b0000;
	localparam I_SUB = 4'b0001;
	localparam I_MUL = 4'b0010;
	localparam I_ACC = 4'b0011;
	localparam I_SOFT = 4'b0100;
	localparam I_XOR = 4'b0101;
	localparam I_ARS = 4'b0110;
	localparam I_LR = 4'b0111;
	localparam I_CLZ = 4'b1000;
	localparam I_RM4 = 4'b1001;

	localparam S_IDLE = 2'b00;
	localparam S_OUT = 2'b10;
	localparam S_PROC = 2'b01;

	localparam POS_MAX = {{1'b0}, {(DATA_W-1){1'b1}}};
	localparam NEG_MAX = {{1'b1}, {(DATA_W-1){1'b0}}};
	// parameter ONE_THIRD = {{2'b0}, {30'b010101010101010101010101010101}};
	// parameter ONE_NINTH = {{2'b0}, {30'b000100010001000100010001000100}};
	// parameter ONE_THIRD = {{2'b0}, {14'b01010101010101}};
	// parameter ONE_NINTH = {{2'b0}, {14'b00011100011100}};
	localparam ONE_THIRD = 16'b1010101010101011;
	localparam ONE_NINTH = 16'b1110001110001111;
	localparam NEG_ONE = 14'sb11_1100_0000_0000;
	localparam NEG_TWO = 14'sb11_1000_0000_0000;
	localparam NEG_THREE = 14'sb11_0100_0000_0000;
	localparam TWO = 14'sb00_1000_0000_0000;
	localparam FIVE = 16'sb0001_0100_0000_0000;

	parameter ACC_SIZE = 20;
    // Wires and Regs
	reg [INST_W-1:0] inst;
	reg signed [DATA_W-1:0] data_a, data_b;
	reg signed [2*DATA_W-1:0] o_data_nxt, o_data_reg, o_data_tmp, data_comp;
	reg [1:0] state, state_nxt;
	reg outflag;
	reg signed [ACC_SIZE-1:0] data_acc [0:15];
	reg signed [ACC_SIZE:0] data_acc_nxt;
	reg [4:0] shift_amount;
	// wire [4:0] idx;


    // Continuous Assignments
	assign o_data = o_data_reg[DATA_W-1:0];
	assign o_busy = (state != S_IDLE);
	assign o_out_valid = (state == S_OUT);
	// assign idx = (inst == I_ACC)? {{1'b0},data_a[3:0]}: data_b[4:0];
	// assign idx = (data_a >>> 10);

	// Function practice

		// Maybe a FSM?
	always @(*) begin
		state_nxt = state;
		case(state)
			S_IDLE: begin
				if(i_in_valid)
					state_nxt = S_PROC;
			end
			S_OUT: state_nxt = S_IDLE;
			S_PROC: state_nxt = S_OUT;
		endcase
	end
	
    // Combinatorial Blocks
	integer j;
	always @(*) begin
		o_data_nxt = o_data_reg;
		o_data_tmp = 0;
		data_acc_nxt = data_acc[data_a[3:0]];
		shift_amount = 0;
		if(state == S_PROC || state == S_IDLE || state == S_OUT) begin
			case(inst)
				I_ADD: begin
					o_data_nxt = data_a + data_b;
					if((data_a[DATA_W-1] == data_b[DATA_W-1]) && data_a[DATA_W-1] != o_data_nxt[DATA_W-1]) begin
						if(data_a[DATA_W-1] == 1'b0)	// overflow (pos+pos->neg, should be pos)
							o_data_nxt = POS_MAX;
						else	// underflow
							o_data_nxt = NEG_MAX;
					end
				end
				I_SUB: begin
					o_data_nxt = data_a - data_b;
					if((data_a[DATA_W-1] != data_b[DATA_W-1]) && data_a[DATA_W-1] != o_data_nxt[DATA_W-1]) begin
						if(data_a[DATA_W-1] == 1'b0)	// overflow (pos-neg->neg, should be pos)
							o_data_nxt = POS_MAX;
						else	// underflow
							o_data_nxt = NEG_MAX;
					end
				end
				I_MUL: begin
					o_data_tmp = data_a*data_b;
					o_data_nxt = $signed( o_data_tmp+ 10'b10_0000_0000 ) >>> FRAC_W;	// for rounding
					if(o_data_nxt > $signed(POS_MAX))
						o_data_nxt = POS_MAX;
					else if(o_data_nxt < $signed(NEG_MAX))
						o_data_nxt = NEG_MAX;
					//!check rounding
				end
				I_ACC: begin
					data_acc_nxt = data_acc[data_a[3:0]] + data_b;
					o_data_nxt = data_acc_nxt;
					// Saturation
					if(o_data_nxt > $signed(POS_MAX))
						o_data_nxt = POS_MAX;
					else if(o_data_nxt < $signed(NEG_MAX))
						o_data_nxt = NEG_MAX;
					// if((data_acc[data_a][ACC_SIZE-1] == data_b[DATA_W-1]) && data_b[DATA_W-1] != o_data_nxt[ACC_SIZE-1]) begin
					// 	if(data_b[DATA_W-1] == 1'b0) // overflow (pos+pos->neg)
					// 		o_data_nxt = POS_MAX;
					// 	else
					// 		o_data_nxt = NEG_MAX;
					// end
					//! Why is the original one wrong
				end
				I_SOFT: begin
					if(data_a >= TWO) begin
						o_data_nxt = data_a;
					end
					else if (data_a <= NEG_THREE) begin
						o_data_nxt = 0;
					end
					else begin
						if (data_a[DATA_W-1] == 1'b0 ) begin	// data_a >= 0
							o_data_tmp = $unsigned((data_a << 1) + TWO)*(ONE_THIRD);
							shift_amount = 17;
						end
						else if (data_a >= NEG_ONE) begin
							o_data_tmp = $unsigned(data_a + TWO)*(ONE_THIRD);
							shift_amount = 17;
						end
						else if (data_a >= NEG_TWO) begin
							o_data_tmp = $unsigned((data_a << 1) + FIVE)*(ONE_NINTH);
							shift_amount = 19;
						end
						else begin // (o_data_tmp >= -3)
							o_data_tmp = $unsigned(data_a + 16'sb0000_1100_0000_0000)*(ONE_NINTH);
							shift_amount = 19;
						end
						o_data_nxt = $signed(o_data_tmp + {20'b1 << (shift_amount-1)}) >>> shift_amount;
						// if(shift_amount == 17)
						// 	o_data_nxt = $signed( o_data_tmp + {20'b1 << 16} ) >>> 17;	// for rounding
						// else
						// 	o_data_nxt = $signed( o_data_tmp + {20'b1 << 18} ) >>> 19;	// for rounding
					
						if(o_data_nxt > $signed(POS_MAX))
							o_data_nxt = POS_MAX;
						else if(o_data_nxt < $signed(NEG_MAX))
							o_data_nxt = NEG_MAX;
					end
				end
				I_XOR: begin
					o_data_nxt = data_a ^ data_b;
				end
				I_ARS: begin
					o_data_nxt = data_a >>> $unsigned(data_b);
				end
				I_LR: begin
					o_data_tmp = {data_a, data_a}; 
					o_data_nxt = o_data_tmp[2*DATA_W-1-(data_b[4:0]) -: DATA_W];
				end
				I_CLZ: begin
					o_data_tmp = 0;
					for (j=0; j<DATA_W; j=j+1) begin
						if(data_a[j] != 1'b0)
							o_data_tmp = j;
					end
					o_data_nxt = (DATA_W-1) - o_data_tmp;
				end
				I_RM4: begin
					for (j=0; j<=12; j=j+1) begin
						o_data_nxt[j] = (data_a[j+3-:4] == data_b[15-j-:4]);
					end
					o_data_nxt[15:13] = 3'b000;
				end

			endcase
		end
	end


    // Sequential Blocks
	integer i;
	always @(posedge i_clk or negedge i_rst_n) begin
		if(!i_rst_n) begin
			o_data_reg <= 0;
			data_a <= 0;
			data_b <= 0;
			state <= S_IDLE;
			inst <= 0;
			for(i=0; i<16; i=i+1) begin
				data_acc[i] <= 21'b0;
			end
				
		end
		else begin
			// load data
			// data_a <= data_a;
			// data_b <= data_b;
			// inst <= inst
			if(i_in_valid) begin
				data_a <= i_data_a;
				data_b <= i_data_b;
				inst <= i_inst;
			end
			o_data_reg <= o_data_nxt;
			state <= state_nxt;
			if(inst == I_ACC && state == S_PROC) begin
				data_acc[data_a[3:0]] <= data_acc_nxt[ACC_SIZE-1:0];
			end
		end
	end


endmodule
