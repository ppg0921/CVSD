
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
	localparam S_START = 5'd0;
	localparam S_LOAD	= 5'd1;
	localparam S_OP_READY = 5'd2;
	localparam S_OP_FETCH = 5'd3;
	localparam S_DATA_OP = 5'd4;
	localparam S_DISPLAY = 5'd5;
	localparam S_CONV = 5'd6;
	localparam S_LOAD_READY = 5'd7;
	localparam S_OP_WAIT = 5'd8;
	localparam S_DIS_PREP = 5'd9;
	localparam S_DIS_GET_LAST = 5'd10;
	localparam S_OUTPUT = 5'd11;
	localparam S_CONV_OUTPUT = 5'd12;
	localparam S_MEDIAN = 5'd13;
	localparam S_MEDIAN_OUTPUT = 5'd14;
	localparam S_SINGLE_CYCLE = 5'd15;

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
	reg [4:0] state, state_nxt;
	reg [5:0] channel_depth, channel_depth_nxt;
	reg [2:0] origin_x, origin_x_nxt;
	reg [2:0] origin_y, origin_y_nxt;
	reg [10:0] cnt, cnt_nxt;
	reg [4:0] cnt_display, cnt_display_nxt;
	reg [3:0] operation_nxt, operation;
	reg [13:0] out_data, out_data_nxt;
	reg out_valid, out_valid_nxt;
	reg [4:0] acc_ori_addr;
	reg sram_op_valid [0:3], sram_op_valid_nxt[0:3];
	reg [16:0] conv_result[0:3], conv_result_nxt[0:3];
	reg [7:0] conv_last_result, conv_last_result_nxt;
	reg [7:0] median_map[0:7][0:2], median_map_nxt[0:7][0:2];
	reg [7:0] median_final_map[0:2], median_final_map_nxt[0:2];	// final map for storing median numbers of 2

	// SRAM
	reg SRAM_CEN[0:3], SRAM_WEN[0:3];
	wire [7:0] SRAM_Q [0:3];		// output data
	reg [7:0] SRAM_Q_real [0:3];	// output data condisering valid
	reg [7:0] SRAM_D [0:3];		// input data
	reg [11:0] SRAM_A [0:3];
	reg [8:0] load_add_offset, load_add_offset_nxt;	// for load operation and also for display channel offset
	wire signed [3:0] sram_idx [0:3];
	reg [1:0] sram_idx_good [0:3];
	wire [3:0] dis_ori_addr [0:3];

	// sort3
	wire [7:0] out_sort0[0:2], out_sort1[0:2], out_sort2[0:2], out_sort3[0:2], out_sort4[0:2];
	reg [23:0] in_sort0, in_sort1, in_sort2, in_sort3, in_sort4;

	wire single_cycle_op;
	wire [3:0] op_now;

	integer i, j;


// ---------------------------------------------------------------------------
// SRAM
// ---------------------------------------------------------------------------
	sram_512x8 SRAM0(		// y = 0, 4
		.Q(SRAM_Q[0]),	// 8-bit data output
		.CLK(i_clk),
		.CEN(SRAM_CEN[0]),	// Chip enable (active low)
		.WEN(SRAM_WEN[0]),	// Write enable (active low)
		.A(SRAM_A[0]),	// 12-bit address input
		.D(SRAM_D[0]) 	// 8-bit data input
	);

	sram_512x8 SRAM1(		// y = 1, 5
		.Q(SRAM_Q[1]),	// 8-bit data output
		.CLK(i_clk),
		.CEN(SRAM_CEN[1]),	// Chip enable (active low)
		.WEN(SRAM_WEN[1]),	// Write enable (active low)
		.A(SRAM_A[1]),	// 12-bit address input
		.D(SRAM_D[1]) 	// 8-bit data input
	);

	sram_512x8 SRAM2(		// y = 2, 6
		.Q(SRAM_Q[2]),	// 8-bit data output
		.CLK(i_clk),
		.CEN(SRAM_CEN[2]),	// Chip enable (active low)
		.WEN(SRAM_WEN[2]),	// Write enable (active low)
		.A(SRAM_A[2]),	// 12-bit address input
		.D(SRAM_D[2]) 	// 8-bit data input
	);

	sram_512x8 SRAM3(		// y = 3, 7
		.Q(SRAM_Q[3]),	// 8-bit data output
		.CLK(i_clk),
		.CEN(SRAM_CEN[3]),	// Chip enable (active low)
		.WEN(SRAM_WEN[3]),	// Write enable (active low)
		.A(SRAM_A[3]),	// 12-bit address input
		.D(SRAM_D[3]) 	// 8-bit data input
	);

	sort3 sort3_0(		// sort 3 data
		.i_clk(i_clk),
		.i_en(state == S_MEDIAN || state == S_MEDIAN_OUTPUT),
		.i_rst_n(i_rst_n),
		.i_data(in_sort0),
		.o_data0(out_sort0[0]),
		.o_data1(out_sort0[1]),
		.o_data2(out_sort0[2])
	);

	sort3 sort3_1(		// sort 3 data
		.i_clk(i_clk),
		.i_en(state == S_MEDIAN || state == S_MEDIAN_OUTPUT),
		.i_rst_n(i_rst_n),
		.i_data(in_sort1),
		.o_data0(out_sort1[0]),
		.o_data1(out_sort1[1]),
		.o_data2(out_sort1[2])
	);

	sort3 sort3_2(		// sort 3 data
		.i_clk(i_clk),
		.i_en(state == S_MEDIAN || state == S_MEDIAN_OUTPUT),
		.i_rst_n(i_rst_n),
		.i_data(in_sort2),
		.o_data0(out_sort2[0]),
		.o_data1(out_sort2[1]),
		.o_data2(out_sort2[2])
	);

	sort3 sort3_3(		// sort 3 data
		.i_clk(i_clk),
		.i_en(state == S_MEDIAN || state == S_MEDIAN_OUTPUT),
		.i_rst_n(i_rst_n),
		.i_data(in_sort3),
		.o_data0(out_sort3[0]),
		.o_data1(out_sort3[1]),
		.o_data2(out_sort3[2])
	);

	sort3 sort3_4(		// sort 3 data
		.i_clk(i_clk),
		.i_en(state == S_MEDIAN || state == S_MEDIAN_OUTPUT),
		.i_rst_n(i_rst_n),
		.i_data(in_sort4),
		.o_data0(out_sort4[0]),
		.o_data1(out_sort4[1]),
		.o_data2(out_sort4[2])
	);


// ---------------------------------------------------------------------------
// Continuous Assignment
// ---------------------------------------------------------------------------
// ---- Add your own wire data assignments here if needed ---- //

	assign single_cycle_op =  (i_op_mode == OP_RIGHT) | (i_op_mode == OP_LEFT) | (i_op_mode == OP_UP) | (i_op_mode == OP_DOWN) | (i_op_mode == OP_REDUCE_DEPTH) | (i_op_mode == OP_INCREASE_DEPTH);
	assign op_now = (state == S_OP_FETCH) ? i_op_mode : operation;
	assign o_op_ready = (state == S_OP_READY || (state == S_START && cnt == 3)) ? 1 : 0;
	assign o_in_ready = (state == S_LOAD_READY || state == S_LOAD || state == S_OP_WAIT) ? 1 : 0;	//! need modification
	assign o_out_data = out_data;
	assign o_out_valid = out_valid;

	// which SRAM to read 
	assign sram_idx[0] = (origin_x > 4)? origin_x - 5 : origin_x - 1;		// if origin_x = 0, then sram_idx[0] = -1
	assign sram_idx[1] = (origin_x > 3)? origin_x - 4 : origin_x;				// sram_idx of origin
	assign sram_idx[2] = (origin_x > 2)? origin_x - 3 : origin_x + 1;
	assign sram_idx[3] = (origin_x > 1)? origin_x - 2 : origin_x + 2;		// if origin_x = 6, then sram_idx[3] = 4

	
	
	// accessed address in SRAM
	assign dis_ori_addr[1] = (origin_y << 1) + ((origin_x > 3)? 1 : 0);		// address of origin in SRAM
	assign dis_ori_addr[0] = (sram_idx[1] == 4)? dis_ori_addr[1] - 1 : dis_ori_addr[1];	// if origin_y = 0
	assign dis_ori_addr[2] = (sram_idx[1] >= 3)? dis_ori_addr[1] + 1 : dis_ori_addr[1];
	assign dis_ori_addr[3] = (sram_idx[1] >= 2)? dis_ori_addr[1] + 1 : dis_ori_addr[1];

	// genvar gi;  // for generate block
	// generate
	// 	for (gi = 0; gi < 4; gi = gi + 1) begin : loop
	// 		assign SRAM_Q_real[sram_idx[gi]] = (sram_op_valid[gi])? SRAM_Q[sram_idx[gi]] : 0;  // Continuous assignment using the loop
	// 	end
	// endgenerate



// ---------------------------------------------------------------------------
// Combinational Blocks
// ---------------------------------------------------------------------------
// ---- Write your conbinational block design here ---- //

	// FSM && fetch operation
	always @(*) begin
		state_nxt = state;
		operation_nxt = operation;
		case(state)	// synopsys parallel_case
			S_START: begin
				if(cnt == 3)
					state_nxt = S_LOAD_READY;
			end
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
				if(i_op_valid) begin
					operation_nxt = i_op_mode;
					if(single_cycle_op) begin
						state_nxt = S_SINGLE_CYCLE;
					end else begin
						case(i_op_mode)
							OP_DISPLAY: state_nxt = S_DISPLAY;
							OP_CONV: state_nxt = S_CONV;
							//! need modification
							OP_MEDIAN: state_nxt = S_MEDIAN;
							OP_SOBEL_NMS: state_nxt = S_CONV;
						endcase
					end
				end
			end
			S_SINGLE_CYCLE: state_nxt = S_OP_READY;
			S_DIS_PREP: state_nxt = S_DISPLAY;	// wont enter this state
			S_DISPLAY: begin
				if(cnt >> 4 == channel_depth - 1 && cnt_display == 3) begin
					state_nxt = S_DIS_GET_LAST;
				end
			end
			S_DIS_GET_LAST: state_nxt = S_OUTPUT;
			S_CONV: begin
				if(cnt >> 4 == channel_depth - 1 && cnt_display == 3) begin
					state_nxt = S_CONV_OUTPUT;
				end
			end
			S_CONV_OUTPUT: begin
				if(cnt_display == 3)
					state_nxt = S_OUTPUT;
			end
			S_MEDIAN: begin
				if(cnt >> 4 == 4 && cnt_display == 4) begin	// including one whole process after the 4th channel
					state_nxt = S_MEDIAN_OUTPUT;
				end
			end
			S_MEDIAN_OUTPUT: begin	// for setting output of median3 of channel 4
				state_nxt = S_OUTPUT;
			end
			S_OUTPUT: begin
				state_nxt = S_OP_READY;
			end
		endcase
	end

	// Counter
	always @(*) begin
		cnt_nxt = 0;
		cnt_display_nxt = 0;
		load_add_offset_nxt = load_add_offset;
		case(state)
			S_START: begin
				cnt_nxt = cnt + 1;
			end
			S_LOAD: begin
				if(i_in_valid) begin
					cnt_nxt = cnt + 1;
					if(cnt_display == 3) begin
						cnt_display_nxt = 0;
						load_add_offset_nxt = load_add_offset + 1;
					end else begin
						cnt_display_nxt = cnt_display + 1;
					end
				end
			end
			S_DISPLAY: begin
				if(cnt_display == 3) begin
					cnt_display_nxt = 0;
					cnt_nxt = cnt + 16;	// next channel
				end else begin
					cnt_display_nxt = cnt_display + 1;	// 0, 1, 2, 3
					cnt_nxt = cnt;
				end
			end
			S_CONV, S_CONV_OUTPUT: begin
				if(cnt_display == 3) begin
					cnt_display_nxt = 0;
					cnt_nxt = cnt + 16;	// next channel (representing which channel is being processed)
				end else begin
					cnt_display_nxt = cnt_display + 1;	// 0, 1, 2, 3
					cnt_nxt = cnt;
				end
			end
			S_MEDIAN: begin
				if(cnt_display == 4) begin
					cnt_display_nxt = 0;
					cnt_nxt = cnt + 16;	// next channel
				end else begin
					cnt_display_nxt = cnt_display + 1;	// 0, 1, 2, 3, 4
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
		if(state == S_SINGLE_CYCLE) begin
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
	end

	always @(*) begin
		for(i=0; i<4; i++) begin
			// if(sram_idx[i] <= 0)
			// 	sram_idx_good[i] = sram_idx[i] + 4;
			// else if(sram_idx[i] >= 4)
			// 	sram_idx_good[i] = sram_idx[i] - 4;
			// else
			// 	sram_idx_good[i] = sram_idx[i];
			sram_idx_good[i] = sram_idx[i][1:0];
		end
		for (i = 0; i < 4; i = i + 1) begin
			SRAM_Q_real[i] = 0; 
		end
		for (i = 0; i < 4; i = i + 1) begin
			SRAM_Q_real[sram_idx_good[i]] = (sram_op_valid[i])? SRAM_Q[sram_idx_good[i]] : 0; 
		end
	end

	// other operations
	always @(*) begin
		out_data_nxt = 0;
		out_valid_nxt = 0;
		acc_ori_addr = 0;
		conv_last_result_nxt = 0;
		for(i=0; i<4; i=i+1) begin
			SRAM_CEN[i] = 1;
			SRAM_WEN[i] = 1;
			SRAM_A[i] = 0;
			SRAM_D[i] = 0;
			sram_op_valid_nxt[i] = 0;
			conv_result_nxt[i] = conv_result[i];
		end
		for(i=0; i<3; i=i+1) begin
			median_final_map_nxt[i] = median_final_map[i];
		end
		for(i=0; i<8; i=i+1) begin
			for(j=0; j<3; j=j+1) begin
				median_map_nxt[i][j] = median_map[i][j];
			end
		end
		in_sort0 = 0;
		in_sort1 = 0;
		in_sort2 = 0;
		in_sort3 = 0;
		in_sort4 = 0;
		//! if state > S_OP_FETCH && state < S_OUTPUT && op_now != OP_LOAD
		case(op_now)	// synopsys parallel_case
			OP_LOAD: begin	// only need to set data, then SRAM will write data in the next cycle
				if(state == S_LOAD) begin
					SRAM_CEN[cnt_display] = 0;		// active low
					SRAM_WEN[cnt_display] = 0;
					SRAM_A[cnt_display] = load_add_offset;
					SRAM_D[cnt_display] = i_in_data;
				end
			end
			OP_DISPLAY: begin
				if(state == S_DISPLAY) begin
					if(cnt_display[0] == 0) begin
						//Todo: can be optimized by getting the index first
						SRAM_CEN[sram_idx_good[1]] = (state == S_DIS_PREP || state == S_DISPLAY)? 0 : 1;
						SRAM_A[sram_idx_good[1]] = dis_ori_addr[1] + {cnt_display[1], 1'b0} + (cnt);
						out_data_nxt = SRAM_Q[sram_idx_good[2]];	// output from the previous column
					end else begin
						SRAM_CEN[sram_idx_good[2]] = (state == S_DIS_PREP || state == S_DISPLAY)? 0 : 1;
						SRAM_A[sram_idx_good[2]] = dis_ori_addr[2] + {cnt_display[1], 1'b0} + (cnt);
						out_data_nxt = SRAM_Q[sram_idx_good[1]];	// output from the previous column
					end
					if(cnt == 0 && cnt_display == 0)
						out_valid_nxt = 0;
					else
						out_valid_nxt = 1;
				end else if (state == S_DIS_GET_LAST) begin
					out_data_nxt = SRAM_Q[sram_idx_good[2]];	// output from the previous column(right column)
					out_valid_nxt = 1;
				end
			end
			OP_CONV: begin
				if(state == S_CONV) begin

					for(i=0; i<4; i=i+1) begin
						acc_ori_addr = dis_ori_addr[i] + {cnt_display << 1} - 2;
						if(sram_idx[i]>=0 && sram_idx[i]<=3 && acc_ori_addr < 16 && acc_ori_addr >= 0) begin
							SRAM_CEN[sram_idx[i]] = 0;
							SRAM_A[sram_idx[i]] = acc_ori_addr + (cnt);
							sram_op_valid_nxt[i] = 1;
						end
					end
					case(cnt_display)
						0: begin
							if(cnt != 0) begin
								conv_result_nxt[2] = conv_result[2] + SRAM_Q_real[sram_idx_good[0]] + (SRAM_Q_real[sram_idx_good[1]] << 1) + SRAM_Q_real[sram_idx_good[2]];
								conv_result_nxt[3] = conv_result[3] + SRAM_Q_real[sram_idx_good[1]] + (SRAM_Q_real[sram_idx_good[2]] << 1) + SRAM_Q_real[sram_idx_good[3]];
							end else begin	// cnt == 0
								conv_result_nxt[0] = 0;
								conv_result_nxt[1] = 0;
								conv_result_nxt[2] = 0;
								conv_result_nxt[3] = 0;
							end
						end
						1: begin
							conv_result_nxt[0] = conv_result[0] + SRAM_Q_real[sram_idx_good[0]] + (SRAM_Q_real[sram_idx_good[1]] << 1) + SRAM_Q_real[sram_idx_good[2]];
							conv_result_nxt[1] = conv_result[1] + SRAM_Q_real[sram_idx_good[1]] + (SRAM_Q_real[sram_idx_good[2]] << 1) + SRAM_Q_real[sram_idx_good[3]];			
							// out_data_nxt = (conv_result[1] + 4'b1000) >> 4;	// already rounded in the previous cycle
							
						end
						2: begin
							conv_result_nxt[0] = conv_result[0] + (SRAM_Q_real[sram_idx_good[0]] << 1) + (SRAM_Q_real[sram_idx_good[1]] << 2) + (SRAM_Q_real[sram_idx_good[2]] << 1);
							conv_result_nxt[1] = conv_result[1] + (SRAM_Q_real[sram_idx_good[1]] << 1) + (SRAM_Q_real[sram_idx_good[2]] << 2) + (SRAM_Q_real[sram_idx_good[3]] << 1);
							conv_result_nxt[2] = conv_result[2] + (SRAM_Q_real[sram_idx_good[0]]) + (SRAM_Q_real[sram_idx_good[1]] << 1) + (SRAM_Q_real[sram_idx_good[2]]);
							conv_result_nxt[3] = conv_result[3] + (SRAM_Q_real[sram_idx_good[1]]) + (SRAM_Q_real[sram_idx_good[2]] << 1) + (SRAM_Q_real[sram_idx_good[3]]);
							
						end
						3: begin
							conv_result_nxt[0] = conv_result[0] + SRAM_Q_real[sram_idx_good[0]] + (SRAM_Q_real[sram_idx_good[1]] << 1) + SRAM_Q_real[sram_idx_good[2]];
							conv_result_nxt[1] = conv_result[1] + SRAM_Q_real[sram_idx_good[1]] + (SRAM_Q_real[sram_idx_good[2]] << 1) + SRAM_Q_real[sram_idx_good[3]];
							conv_result_nxt[2] = conv_result[2] + (SRAM_Q_real[sram_idx_good[0]] << 1) + (SRAM_Q_real[sram_idx_good[1]] << 2) + (SRAM_Q_real[sram_idx_good[2]] << 1);
							conv_result_nxt[3] = conv_result[3] + (SRAM_Q_real[sram_idx_good[1]] << 1) + (SRAM_Q_real[sram_idx_good[2]] << 2) + (SRAM_Q_real[sram_idx_good[3]] << 1);
							// out_data_nxt = conv_last_result;	// already rounded in the previous cycle
						end
					endcase
				end else if (state == S_CONV_OUTPUT) begin
					if(cnt_display == 0) begin
						conv_result_nxt[2] = conv_result[2] + SRAM_Q_real[sram_idx_good[0]] + (SRAM_Q_real[sram_idx_good[1]] << 1) + SRAM_Q_real[sram_idx_good[2]];
						conv_result_nxt[3] = conv_result[3] + SRAM_Q_real[sram_idx_good[1]] + (SRAM_Q_real[sram_idx_good[2]] << 1) + SRAM_Q_real[sram_idx_good[3]];
					end
					out_data_nxt = (conv_result[cnt_display] + 4'b1000) >> 4;
					out_valid_nxt = 1;
				end
			end
			OP_MEDIAN: begin
				//! remember to set out_valid
				if(state == S_MEDIAN) begin
					// request from sram
					if(cnt_display != 4 && cnt != 64) begin
						for(i=0; i<4; i=i+1) begin
							acc_ori_addr = dis_ori_addr[i] + {cnt_display << 1} - 2;
							if(sram_idx[i]>=0 && sram_idx[i]<=3 && acc_ori_addr < 16 && acc_ori_addr >= 0) begin
								SRAM_CEN[sram_idx_good[i]] = 0;
								SRAM_A[sram_idx_good[i]] = acc_ori_addr + (cnt);
								sram_op_valid_nxt[i] = 1;
							end
						end
					end
					// set median map
					if(cnt_display != 1 ) begin
						if(cnt_display == 0) begin
							for(i=0; i<3; i++) begin
								median_map_nxt[6][i] = out_sort0[i];
								median_map_nxt[7][i] = out_sort1[i];
							end
						end else begin
							for(i=0; i<3; i++) begin
								median_map_nxt[(cnt_display-2) << 1][i] = out_sort0[i];
								median_map_nxt[((cnt_display-2) << 1) + 1][i] = out_sort1[i];
							end
						end
					end
					if(cnt != 0 && cnt_display != 3 && !(cnt == 16 && cnt_display == 0)) begin
						out_valid_nxt = 1;
					end
					case(cnt_display)
						0: begin
							in_sort0 = {median_map[1][0], median_map[3][0], median_map[5][0]};
							in_sort1 = {median_map[1][1], median_map[3][1], median_map[5][1]};
							in_sort2 = {median_map[1][2], median_map[3][2], median_map[5][2]};
							in_sort3 = {out_sort4[0], out_sort3[1], out_sort2[2]};
							in_sort4 = {median_map[2][0], median_map[4][0], out_sort0[0]};
							out_data_nxt = conv_last_result;		// median of 3
						end
						1: begin
							in_sort0 = {SRAM_Q_real[sram_idx_good[0]], SRAM_Q_real[sram_idx_good[1]], SRAM_Q_real[sram_idx_good[2]]};
							in_sort1 = {SRAM_Q_real[sram_idx_good[1]], SRAM_Q_real[sram_idx_good[2]], SRAM_Q_real[sram_idx_good[3]]};
							in_sort2 = {out_sort2[0], out_sort1[1], out_sort0[2]};
							in_sort3 = {median_map[2][1], median_map[4][1], median_map[6][1]};
							in_sort4 = {median_map[2][2], median_map[4][2], median_map[6][2]};
							median_final_map_nxt[2] = out_sort4[2];
							out_data_nxt = out_sort3[1];		// median of 0
						end
						2: begin
							in_sort0 = {SRAM_Q_real[sram_idx_good[0]], SRAM_Q_real[sram_idx_good[1]], SRAM_Q_real[sram_idx_good[2]]};
							in_sort1 = {SRAM_Q_real[sram_idx_good[1]], SRAM_Q_real[sram_idx_good[2]], SRAM_Q_real[sram_idx_good[3]]};
							in_sort2 = {median_map[3][0], median_map[5][0], median_map[7][0]};
							in_sort3 = {median_map[3][1], median_map[5][1], median_map[7][1]};
							in_sort4 = {median_map[3][2], median_map[5][2], median_map[7][2]};
							median_final_map_nxt[1] = out_sort3[1];
							median_final_map_nxt[0] = out_sort4[0];
							out_data_nxt = out_sort2[1];		// median of 1
						end
						3: begin
							in_sort0 = {SRAM_Q_real[sram_idx_good[0]], SRAM_Q_real[sram_idx_good[1]], SRAM_Q_real[sram_idx_good[2]]};
							in_sort1 = {SRAM_Q_real[sram_idx_good[1]], SRAM_Q_real[sram_idx_good[2]], SRAM_Q_real[sram_idx_good[3]]};
							in_sort2 = {median_final_map[0], median_final_map[1], median_final_map[2]};
							in_sort3 = {out_sort4[0], out_sort3[1], out_sort2[2]};
							// no output
						end
						4: begin
							in_sort0 = {SRAM_Q_real[sram_idx_good[0]], SRAM_Q_real[sram_idx_good[1]], SRAM_Q_real[sram_idx_good[2]]};
							in_sort1 = {SRAM_Q_real[sram_idx_good[1]], SRAM_Q_real[sram_idx_good[2]], SRAM_Q_real[sram_idx_good[3]]};
							in_sort2 = {median_map[0][0], median_map[2][0], out_sort0[0]};
							in_sort3 = {median_map[0][1], median_map[2][1], out_sort0[1]};
							in_sort4 = {median_map[0][2], median_map[2][2], out_sort0[2]};
							out_data_nxt = out_sort2[1];		// median of 2
							conv_last_result_nxt = out_sort3[1];
						end
					endcase
				end else if (state == S_MEDIAN_OUTPUT) begin
					out_data_nxt = conv_last_result;
					out_valid_nxt = 1;
				end
			end 
			OP_SOBEL_NMS: begin

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
			operation <= OP_LOAD;
			out_data <= 0;
			out_valid <= 0;
			for(i=0; i<4; i=i+1) begin
				sram_op_valid[i] <= 0;
				conv_result[i] <= 0;
			end
			conv_last_result <= 0;
			load_add_offset <= 0;
			for (i=0; i<3; i=i+1) begin
				median_final_map[i] <= 0;
			end
			for (i=0; i<8; i=i+1) begin
				for (j=0; j<3; j=j+1) begin
					median_map[i][j] <= 0;
				end
			end
		end else begin
			state <= state_nxt;
			channel_depth <= channel_depth_nxt;
			origin_x <= origin_x_nxt;
			origin_y <= origin_y_nxt;
			cnt <= cnt_nxt;
			cnt_display <= cnt_display_nxt;
			operation <= operation_nxt;
			out_data <= out_data_nxt;
			out_valid <= out_valid_nxt;
			for(i=0; i<4; i=i+1) begin
				sram_op_valid[i] <= sram_op_valid_nxt[i];
				conv_result[i] <= conv_result_nxt[i];
			end
			conv_last_result <= conv_last_result_nxt;
			load_add_offset <= load_add_offset_nxt;
			for (i=0; i<3; i=i+1) begin
				median_final_map[i] <= median_final_map_nxt[i];
			end
			for (i=0; i<8; i=i+1) begin
				for (j=0; j<3; j=j+1) begin
					median_map[i][j] <= median_map_nxt[i][j];
				end
			end
		end
	end



endmodule

module SobelDirection (
	input i_clk,
	input i_rst_n,
	input signed [10:0] Gx,
	input signed [10:0] Gy,
	output [1:0] o_dir
);

	localparam DIR0 = 2'd0;
	localparam DIR45 = 2'd1;
	localparam DIR90 = 2'd2;
	localparam DIR135 = 2'd3;

	wire [9:0] abs_Gx, abs_Gy;
	wire signed [16:0] tan225, tan675;
	reg [1:0] o_dir_reg, o_dir_nxt;

	assign abs_Gx = (Gx[10])? ~Gx + 1 : Gx;
	assign abs_Gy = (Gy[10])? ~Gy + 1 : Gy;

	assign tan225 = abs_Gx + abs_Gx << 2 + abs_Gx << 4 + abs_Gx << 5;
	assign tan675 = abs_Gx + abs_Gx << 2 + abs_Gx << 4 + abs_Gx << 5 + abs_Gx << 8;
	
	always @(*) begin
		if(Gx[10] == Gy[10]) begin
			if(abs_Gy < tan225) begin
				o_dir_nxt = DIR0;
			end else if(abs_Gy <= tan675) begin
				o_dir_nxt = DIR45;
			end else begin
				o_dir_nxt = DIR90;
			end
		end else begin
			if(abs_Gy < tan225) begin
				o_dir_nxt = DIR0;
			end else if(abs_Gy <= tan675) begin
				o_dir_nxt = DIR135;
			end else begin
				o_dir_nxt = DIR90;
			end
		end
	end
	always @(posedge i_clk or negedge i_rst_n) begin
		if(!i_rst_n) begin
			o_dir_reg <= 0;
		end else begin
			o_dir_reg <= o_dir_nxt;
		end
	end

endmodule

module sort3 (
	input i_clk,
	input i_en,
	input i_rst_n,
	input [23:0] i_data,
	output [7:0] o_data0,
	output [7:0] o_data1,
	output [7:0] o_data2
);

	reg [7:0] o_data0_nxt, o_data1_nxt, o_data2_nxt, o_data0_reg, o_data1_reg, o_data2_reg;
	wire [7:0] i_data0, i_data1, i_data2;

	assign o_data0 = o_data0_reg;
	assign o_data1 = o_data1_reg;
	assign o_data2 = o_data2_reg;
	assign i_data0 = i_data[23:16];
	assign i_data1 = i_data[15:8];
	assign i_data2 = i_data[7:0];

	always @(*) begin
		if(!i_en) begin
			o_data0_nxt = 0;
			o_data1_nxt = 0;
			o_data2_nxt = 0;
		end 
		else if(i_data0<=i_data1) begin
			if(i_data1<=i_data2) begin
				o_data0_nxt = i_data0;
				o_data1_nxt = i_data1;
				o_data2_nxt = i_data2;
			end else if(i_data0<=i_data2) begin
				o_data0_nxt = i_data0;
				o_data1_nxt = i_data2;
				o_data2_nxt = i_data1;
			end else begin
				o_data0_nxt = i_data2;
				o_data1_nxt = i_data0;
				o_data2_nxt = i_data1;
			end
		end else begin // i_data0 > i_data1
			if(i_data1 > i_data2) begin
				o_data0_nxt = i_data2;
				o_data1_nxt = i_data1;
				o_data2_nxt = i_data0;
			end else if(i_data0 > i_data2) begin
				o_data0_nxt = i_data1;
				o_data1_nxt = i_data2;
				o_data2_nxt = i_data0;
			end else begin
				o_data0_nxt = i_data1;
				o_data1_nxt = i_data0;
				o_data2_nxt = i_data2;
			end
		end
	end

	always @(posedge i_clk or negedge i_rst_n) begin
		if(!i_rst_n) begin
			o_data0_reg <= 0;
			o_data1_reg <= 0;
			o_data2_reg <= 0;
		end else begin
			o_data0_reg <= o_data0_nxt;
			o_data1_reg <= o_data1_nxt;
			o_data2_reg <= o_data2_nxt;
		end
	end
endmodule
