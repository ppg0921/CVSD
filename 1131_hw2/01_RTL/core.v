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




// ---------------------------------------------------------------------------
// Wires and Registers
// ---------------------------------------------------------------------------
// ---- Add your own wires and registers here if needed ---- //


// ---------------------------------------------------------------------------
// Continuous Assignment
// ---------------------------------------------------------------------------
// ---- Add your own wire data assignments here if needed ---- //

// ---------------------------------------------------------------------------
// Combinational Blocks
// ---------------------------------------------------------------------------
// ---- Write your conbinational block design here ---- //

// ---------------------------------------------------------------------------
// Sequential Block
// ---------------------------------------------------------------------------
// ---- Write your sequential block design here ---- //

endmodule

module ALU #(
	parameter DATA_WIDTH = 32
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
	output o_invalid
);
	localparam ALU_ADD = 3'd0;
	localparam ALU_SUB = 3'd1;
	localparam ALU_SL = 3'd2;
	localparam ALU_SR = 3'd3;
	localparam ALU_FADD = 3'd4;
	localparam ALUFSUB = 3'd5;

	reg signed [DATA_WIDTH: 0] o_data_reg, o_data_nxt;
	reg overflow, ALU_comp;

	// for floating point calculation
	wire sign_a = i_data_a[31];
	wire sign_b = i_data_b[31];
	wire [7:0] exp_a = i_data_a[30:23];
	wire [7:0] exp_b = i_data_b[30:23];
	wire [24:0] mant_a = (exp_a == 8'b0)? {i_data_a[22:0], 1'b0, 1'b0} : {1'b1, i_data_a[22:0], 1'b0}; // Implicit leading 1 for normalized numbers
	wire [24:0] mant_b = (exp_b == 8'b0)? {i_data_b[22:0], 1'b0, 1'b0} : {1'b1, i_data_b[22:0], 1'b0}; // Implicit leading 1 for normalized numbers
	wire [7:0] exp_diff = (exp_a > exp_b) ? (exp_a - exp_b) : (exp_b - exp_a);
	wire [24:0] mant_a_shifted = (exp_a >= exp_b) ? {mant_a} : (mant_a >> exp_diff);
  wire [24:0] mant_b_shifted = (exp_b >= exp_a) ? {mant_b} : (mant_b >> exp_diff);
	wire INFNaN = (exp_a == 8'b11111111) || (exp_b == 8'b11111111);

	assign o_invalid = overflow;
	assign o_data = o_data_reg[DATA_WIDTH:0];

	

	always @(*) begin
		o_data_nxt = o_data_reg;
		overflow = 0;
		ALU_comp = 0;
		if(i_valid) begin
			case(i_ALUOp)
				ALU_ADD: begin
					o_data_nxt = i_data_a + i_data_b;
					if((i_data_a[DATA_W-1] == i_data_b[DATA_W-1]) && i_data_a[DATA_W-1] != o_data_nxt[DATA_W-1]) begin
						overflow = 1;
					end
					else if(i_ALUctrl == 2 && (o_data_nxt > 1023 || o_data_nxt < 0)) begin	// address out of range
						overflow = 1;
					end
				end
				ALU_SUB: begin
					o_data_nxt = i_data_a - i_data_b;
					if(i_ALUctrl == 0) begin
						ALU_comp = (o_data_nxt == 0)? 1:0;
					end
					else if(i_ALUctrl == 1) begin
						if(i_data_a[DATA_WIDTH-1] == i_data_b[DATA_WIDTH-1]) begin	// no overflow
							if(o_data_nxt[DATA_WIDTH-1] == 1)	// a-b < 0--> a < b
								ALU_comp = 1;
						end
						else if(i_data_a[DATA_WIDTH-1] == 1 && i_data_b[DATA_WIDTH] == 0) // a neg, b pos --> a < b
							ALU_comp = 1;
					end
					else if((i_data_a[DATA_W-1] != i_data_b[DATA_W-1]) && i_data_a[DATA_W-1] != o_data_nxt[DATA_W-1]) begin
						overflow = 1;
					end
				end
				ALU_SL: begin
					o_data_nxt = i_data_a << $unsigned(i_data_b);
				end
				ALU_SR: begin
					o_data_nxt = i_data_a >>> $unsigned(i_data_b);
				end
				ALU_FADD: begin
					
				end
			endcase
		end
	end

	always @(posedge i_clk or negedge i_rst_n) begin
		if(!i_rst_n) begin
			o_data_reg <= 0;
		end
		else begin
			o_data_reg <= o_data_nxt; 
		end
	end




endmodule