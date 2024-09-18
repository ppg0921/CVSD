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

    // Wires and Regs
	reg [INST_W-1:0] inst;
	reg signed [DATA_W-1:0] data_a, data_b;
	reg signed [DATA_W:0] o_data_reg;


    // Continuous Assignments


    // Combinatorial Blocks

		always @(*) begin
			case(inst)

			endcase
		end


    // Sequential Blocks

	always @(posedge i_clk or negedge i_rst_n) begin
		if(!i_rst_n) begin
		end
		else begin
			data_a <= data_a;
			data_b <= data_b;
			inst <= inst
			if(i_in_valid) begin
				data_a <= i_data_a;
				data_b <= i_data_b;
				inst <= i_inst;
			end
		end
	end


endmodule
