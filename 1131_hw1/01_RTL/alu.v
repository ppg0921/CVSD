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
	parameter I_ADD = 4'b0000;
	parameter I_SUB = 4'b0001;
	parameter I_MUL = 4'b0010;
	parameter I_ACC = 4'b0011;
	parameter I_SOFT = 4'b0100;
	parameter I_XOR = 4'b0101;
	parameter I_ARS = 4'b0110;
	parameter I_LR = 4'b0111;
	parameter I_CLZ = 4'b1000;
	parameter I_RM4 = 4'b1001;

	parameter S_IDLE = 2'b00;
	parameter S_OUT = 2'b10;
	parameter S_PROC = 2'b01;

	parameter POS_MAX = {{1'b0}, {(DATA_W-1){1'b1}}};
	parameter NEG_MAX = {{1'b1}, {(DATA_W-1){1'b0}}};
	parameter ONE_THIRD = {{2'b0}, {14'b01010101010101}};
	parameter ONE_NINTH = {{2'b0}, {14'b00010001000100}};

	parameter ACC_SIZE = 20;
    // Wires and Regs
	reg [INST_W-1:0] inst;
	reg signed [DATA_W-1:0] data_a, data_b, mul;
	reg signed [2*DATA_W-1:0] o_data_nxt, o_data_reg, o_data_tmp;
	reg [1:0] state, state_nxt;
	reg outflag;
	reg signed [ACC_SIZE-1:0] data_acc [0:15];
	reg signed [ACC_SIZE-1:0] data_acc_nxt;
	// wire [3:0] idx;


    // Continuous Assignments
	assign o_data = o_data_reg[DATA_W-1:0];
	assign o_busy = (state != S_IDLE);
	assign o_out_valid = (state == S_OUT);
	// assign idx = (data_a >>> 10);

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
		data_acc_nxt = data_acc[data_a];
		mul = 0;
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
				end
				I_ACC: begin
					data_acc_nxt = $signed(data_acc[data_a]) + data_b;
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
					if(data_a[DATA_W-1] == 1'b0)	// data_a >= 0
						o_data_tmp = data_a >>> 10;
					else
						o_data_tmp = $signed(data_a >>> 10) - 2'sb1;
					if(data_a >= 14'sb00_1000_0000_0000) begin
						o_data_nxt = data_a;
					end
					else if (data_a <= 14'sb11_0100_0000_0000) begin
						o_data_nxt = 0;
					end
					else begin
						if (data_a[DATA_W-1] == 1'b0 ) begin	// data_a >= 0
							o_data_tmp = $signed((data_a<<<1) + 12'b1000_0000_0000)*$signed(ONE_THIRD);
						end
						else if (data_a >= 14'sb11_1100_0000_0000) begin
							o_data_tmp = $signed(data_a + 12'b1000_0000_0000)*$signed(ONE_THIRD);
						end
						else if (data_a >= 14'sb11_1000_0000_0000) begin
							o_data_tmp = $signed((data_a<<<1) + 13'b1_0100_0000_0000)*$signed(ONE_NINTH);
						end
						else begin // (o_data_tmp >= -3)
							o_data_tmp = $signed(data_a + 12'b1100_0000_0000)*$signed(ONE_NINTH);
						end
						o_data_nxt = $signed( o_data_tmp + 14'b10_0000_0000_0000 ) >>> 14;	// for rounding
					
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
					o_data_nxt = o_data_tmp[2*DATA_W-1-$unsigned(data_b) -: DATA_W];
				end
				I_CLZ: begin
					o_data_tmp = -1;
					for (j=0; j<DATA_W-1; j=j+1) begin
						if(data_a[j] != 1'b0)
							o_data_tmp = j;
					end
					o_data_nxt = $signed(DATA_W) - 2'sb1 - o_data_tmp;
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
			for(i=0; i<16; i=i+1) begin
				data_acc[i] <= 20'b0;
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
				data_acc[data_a] <= data_acc_nxt;
			end
		end
	end


endmodule
