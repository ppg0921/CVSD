
module core (                       //Don't modify interface
	input         i_clk,
	input         i_rst_n,
	input         i_op_valid,
	input  [ 3:0] i_op_mode,
    output        o_op_ready,
	input         i_in_valid,
	input  [ 7:0] i_in_data,
	output        o_in_ready,
	output        o_out_valid,
	output [13:0] o_out_data
);
// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------
	localparam S_START = 4'd0;
	localparam S_LOAD	= 4'd1;
	localparam S_OP_READY = 4'd2;
	localparam S_OP_FETCH = 4'd3;
	localparam S_DATA_OP = 4'd4;
	localparam S_DISPLAY = 4'd5;
	localparam S_CONV = 4'd6;
	localparam S_LOAD_READY = 4'd7;
	localparam S_OP_WAIT = 4'd8;
	localparam S_DIS_PREP = 4'd9;
	localparam S_DIS_GET_LAST = 4'd10;
	localparam S_DIS_OUTPUT = 4'd11;

	localparam OP_LOAD = 4'd0;
	localparam OP_RIGHT = 4'd1;
	localparam OP_LEFT = 4'd2;
	localparam OP_UP = 4'd3;
	localparam OP_DOWN = 4'd4;
	localparam OP_REDUCE_DEPTH = 4'd5;
	localparam OP_INCREASE_DEPTH = 4'd6;
	localparam OP_DISPLAY = 4'd7;
	localparam OP_CONV = 4'd8;
	localparam OP_MEDIAN = 4'd9;
	localparam OP_SOBEL_NMS = 4'd10;



// ---------------------------------------------------------------------------
// Wires and Registers
// ---------------------------------------------------------------------------
// ---- Add your own wires and registers here if needed ---- //
	reg [3:0] state, state_nxt;
	reg [4:0] channel_depth, channel_depth_nxt;
	reg [2:0] origin_x, origin_x_nxt;
	reg [2:0] origin_y, origin_y_nxt;
	reg [10:0] cnt, cnt_nxt;
	reg [1:0] cnt_display, cnt_display_nxt;
	reg [3:0] operation_nxt, operation;
	reg [13:0] out_data, out_data_nxt;
	reg out_valid, out_valid_nxt;

	// SRAM
	reg SRAM_CEN[0:3], SRAM_WEN[0:3];
	reg [7:0] SRAM_Q [0:3];
	wire [7:0] SRAM_D [0:3];
	reg [11:0] SRAM_A [0:3];
	reg [7:0] load_add_offset, load_add_offset_nxt;	// for load operation and also for display channel offset
	wire signed [2:0] sram_idx [0:3];
	wire [3:0] dis_ori_addr [0:3];

	wire single_cycle_op;
	wire [3:0] op_now;

	integer i;


// ---------------------------------------------------------------------------
// SRAM
// ---------------------------------------------------------------------------
	sram_512x8 SRAM0(		// y = 0, 4
		.Q(),	// 8-bit data output
		.CLK(i_clk),
		.CEN(),	// Chip enable (active low)
		.WEN(),	// Write enable (active low)
		.A(),	// 12-bit address input
		.D() 	// 8-bit data input
	);

	sram_512x8 SRAM1(		// y = 1, 5
		.Q(),	// 8-bit data output
		.CLK(i_clk),
		.CEN(),	// Chip enable (active low)
		.WEN(),	// Write enable (active low)
		.A(),	// 12-bit address input
		.D() 	// 8-bit data input
	);

	sram_512x8 SRAM2(		// y = 2, 6
		.Q(),	// 8-bit data output
		.CLK(i_clk),
		.CEN(),	// Chip enable (active low)
		.WEN(),	// Write enable (active low)
		.A(),	// 12-bit address input
		.D() 	// 8-bit data input
	);

	sram_512x8 SRAM3(		// y = 3, 7
		.Q(),	// 8-bit data output
		.CLK(i_clk),
		.CEN(),	// Chip enable (active low)
		.WEN(),	// Write enable (active low)
		.A(),	// 12-bit address input
		.D() 	// 8-bit data input
	);


// ---------------------------------------------------------------------------
// Continuous Assignment
// ---------------------------------------------------------------------------
// ---- Add your own wire data assignments here if needed ---- //

	assign single_cycle_op =  (i_op_mode == OP_RIGHT) | (i_op_mode == OP_LEFT) | (i_op_mode == OP_UP) | (i_op_mode == OP_DOWN) | (i_op_mode == OP_REDUCE_DEPTH) | (i_op_mode == OP_INCREASE_DEPTH);
	assign op_now = (state == S_OP_FETCH) ? i_op_mode : operation;
	assign o_op_ready = (state == S_OP_READY) ? 1 : 0;
	assign o_in_ready = (state == S_LOAD_READY || state == S_LOAD) ? 1 : 0;	//! need modification

	assign sram_idx[0] = (origin_x > 4)? origin_x - 5 : origin_x - 1;		// if origin_x = 0, then sram_idx[0] = -1
	assign sram_idx[1] = (origin_x > 3)? origin_x - 4 : origin_x;				// sram_idx of origin
	assign sram_idx[2] = (origin_x > 2)? origin_x - 3 : origin_x + 1;
	assign sram_idx[3] = (origin_x > 1)? origin_x - 2 : origin_x + 2;		// if origin_x = 6, then sram_idx[3] = 8
	
	assign dis_ori_addr[1] = (origin_y << 1) + ((origin_x > 3)? 1 : 0);		// address of origin in SRAM
	assign dis_ori_addr[0] = (sram_idx[1] == 4)? dis_ori_addr[1] - 1 : dis_ori_addr[1];
	assign dis_ori_addr[2] = (sram_idx[1] == 3)? dis_ori_addr[1] + 1 : dis_ori_addr[1];


// ---------------------------------------------------------------------------
// Combinational Blocks
// ---------------------------------------------------------------------------
// ---- Write your conbinational block design here ---- //

	// FSM && fetch operation
	always @(*) begin
		state_nxt = state;
		operation_nxt = operation;
		case(state)	// synopsys parallel_case
			S_START: state_nxt = S_LOAD_READY;
			S_LOAD_READY: begin
				if (i_op_valid) begin
					state_nxt = S_LOAD;
				end
			end
			S_LOAD: begin
				if(cnt == 2047) begin
					state_nxt = S_OP_WAIT;
				end
			end
			S_OP_WAIT: state_nxt = S_OP_READY;
			S_OP_READY: begin
				state_nxt = S_OP_FETCH;
			end
			S_OP_FETCH: begin
				if(i_in_valid) begin
					operation_nxt = i_op_mode;
					if(single_cycle_op) begin
						state_nxt = S_OP_READY;
					end else begin
						case(i_op_mode)
							OP_DISPLAY: state_nxt = S_DISPLAY;
							OP_CONV: state_nxt = S_CONV;
							//! need modification
							OP_MEDIAN: state_nxt = S_CONV;
							OP_SOBEL_NMS: state_nxt = S_CONV;
						endcase
					end
				end
			end
			S_DIS_PREP: state_nxt = S_DISPLAY;
			S_DISPLAY: begin
				if(cnt >> 4 == channel_depth - 1) begin
					state_nxt = S_DIS_GET_LAST;
				end
			end
			S_DIS_GET_LAST: state_nxt = S_DIS_OUTPUT;
		endcase
	end

	// Counter
	always @(*) begin
		cnt_nxt = 0;
		cnt_display_nxt = 0;
		load_add_offset_nxt = load_add_offset;
		case(state)	// synopsys parallel_case
			S_LOAD: begin
				cnt_nxt = cnt + 1;
				if(cnt_display == 3) begin
					cnt_display_nxt = 0;
					load_add_offset_nxt = load_add_offset + 1;
				end else begin
					cnt_display_nxt = cnt_display + 1;
				end
			end
			S_DISPLAY: begin
				if(cnt_display == 3) begin
					cnt_display_nxt = 0;
					cnt_nxt = cnt + 16;	// next channel
				end else begin
					cnt_display_nxt = cnt_display + 1;
					cnt_nxt = cnt;
				end
			end
		endcase
	end

	// Operation for channel depth and origin shift
	always @(*) begin
		channel_depth_nxt = channel_depth;
		origin_x_nxt = origin_x;
		origin_y_nxt = origin_y;
		case(op_now)	// synopsys parallel_case
			OP_LOAD: begin
			end
			OP_RIGHT: begin
				if(origin_x != 6)
					origin_x_nxt = origin_x + 1;
			end
			OP_LEFT: begin
				if(origin_x != 0)
					origin_x_nxt = origin_x - 1;
			end
			OP_UP: begin
				if(origin_y != 0)
					origin_y_nxt = origin_y - 1;
			end
			OP_DOWN: begin
				if(origin_y != 6)
					origin_y_nxt = origin_y + 1;
			end
			OP_REDUCE_DEPTH: begin
				if(channel_depth != 8)
					channel_depth_nxt = channel_depth >> 1;	// divide by 2
			end
			OP_INCREASE_DEPTH: begin
				if(channel_depth != 32)
					channel_depth_nxt = channel_depth << 1;	// multiply by 2
			end
		endcase
	end

	// other operations
	always @(*) begin
		out_data_nxt = 0;
		out_valid_nxt = 0;
		for(i=0; i<4; i=i+1) begin
			SRAM_CEN[i] = 1;
			SRAM_WEN[i] = 1;
			SRAM_A[i] = 0;
			SRAM_D[i] = 0;
		end
		//! if state > S_OP_FETCH && state < S_OUTPUT && op_now != OP_LOAD
		case(op_now)	// synopsys parallel_case
			OP_LOAD: begin	// only need to set data, then SRAM will write data in the next cycle
				SRAM_CEN[cnt_display] = 0;		// active low
				SRAM_WEN[cnt_display] = 0;
				SRAM_A[cnt_display] = load_add_offset;
				SRAM_D = i_in_data;
			end
			OP_DISPLAY: begin
				if(state == S_DISPLAY) begin
					if(cnt_display[0] == 0) begin
						//Todo: can be optimized by getting the index first
						SRAM_CEN[sram_idx[1]] = (state == S_DIS_PREP || state == S_DISPLAY)? 0 : 1;
						SRAM_A[sram_idx[1]] = dis_ori_addr[1] + {cnt_display[1], 1'b0};
						out_data_nxt = SRAM_Q[sram_idx[2]];	// output from the previous column
					end else begin
						SRAM_CEN[sram_idx[2]] = (state == S_DIS_PREP || state == S_DISPLAY)? 0 : 1;
						SRAM_A[sram_idx[2]] = dis_ori_addr[2] + {cnt_display[1], 1'b0};
						out_data_nxt = SRAM_Q[sram_idx[1]];	// output from the previous column
					end
					if(cnt == 0 && cnt_display == 0)
						out_valid_nxt = 0;
					else
						out_valid_nxt = 1;
				end else if (state == S_DIS_GET_LAST) begin
					out_data_nxt = SRAM_Q[sram_idx[2]];	// output from the previous column(right column)
					out_valid_nxt = 1;
				end
			end
		endcase
	end
		



// ---------------------------------------------------------------------------
// Sequential Block
// ---------------------------------------------------------------------------
// ---- Write your sequential block design here ---- //
	always @(posedge i_clk or negedge i_rst_n) begin
		if (!i_rst_n) begin
			state <= S_START;
			channel_depth <= 32;
			origin_x <= 0;
			origin_y <= 0;
			cnt <= 0;
			cnt_display <= 0;
			operation <= OP_START;
			out_data <= 0;
		end else begin
			state <= state_nxt;
			channel_depth <= channel_depth_nxt;
			origin_x <= origin_x_nxt;
			origin_y <= origin_y_nxt;
			cnt <= cnt_nxt;
			cnt_display <= cnt_display_nxt;
			operation <= operation_nxt;
			out_data <= out_data_nxt;
		end
	end



endmodule
