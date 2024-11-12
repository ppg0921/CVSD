`timescale 1ns/100ps
`define CYCLE       10.0
`define HCYCLE      (`CYCLE/2)
`define MAX_CYCLE   120000

`define LEN 1024
// `define INST "inst.dat"
`define A "../00_TB/MY_PATTERN/a.dat"
`define B "../00_TB/MY_PATTERN/b.dat"
// `define GOLDEN "golden.dat"

module tb_alu ();

    localparam ALU_FADD = 3'd4;
	localparam ALU_FSUB = 3'd5;

    parameter sig_width = 23;
    parameter exp_width = 8;
    parameter ieee_compliance = 1;
    parameter rounding_mode = 0;


    reg rst_n;
	reg clk = 0;
    reg alu_valid;
    reg [31:0] a_r [0:`LEN-1];
    reg [31:0] b_r [0:`LEN-1];
    reg [31:0] inst [0:`LEN-1];
    reg [31:0] golden [0:`LEN-1];

    reg [31:0] a;
    reg [31:0] b;
    reg [6:0] opcode;
    reg [6:0] funct7;
    reg [2:0] funct3;
    reg [31:0] result;

    reg [31:0] i;
    reg [31:0] err_count;

    wire [sig_width + exp_width: 0] golden_output;
    wire [7:0] golden_status;
    wire alu_done;
    wire [sig_width + exp_width: 0] alu_data;
    wire alu_comp;
    wire alu_invalid;

    integer outfile;

    ALU u_alu (
        .i_clk(clk),
        .i_rst_n(rst_n),
        .i_valid(alu_valid),
        .i_ALUOp(ALU_FSUB),
        .i_ALUctrl(3),
        .i_data_a(a),
        .i_data_b(b),
        .o_done(alu_done),
        .o_data(alu_data),
        .o_comp(alu_comp),
        .o_invalid(alu_invalid)
    );

    DW_fp_addsub #(.sig_width(sig_width), .exp_width(exp_width), .ieee_compliance(ieee_compliance)) U1 ( 
        .a(a), 
        .b(b), 
        .rnd(rounding_mode), 
        .op(1), 
        .z(golden_output), 
        .status(golden_status) 
    );



    always #(`HCYCLE) clk = ~clk;

    initial begin 
		rst_n = 1;
		#(0.25 * `CYCLE) rst_n = 0;
		#(`CYCLE) rst_n = 1;
		#(`MAX_CYCLE)
		$display("----------------------------------------------");
		$display("-          Error! Runtime exceeded!          -");
		$display("----------------------------------------------");
		$finish;
	end

    initial begin
		$fsdbDumpfile("alu_float.fsdb");
		$fsdbDumpvars(0, tb_alu, "+mda");
	end

	// initial begin
	// 	$dumpfile("waveform.vcd");
	// 	$dumpvars();
	// 	outfile = $fopen("output.txt") | 1;
	// end

    initial begin
        alu_valid = 0;
		wait(rst_n === 1'b0);
		wait(rst_n === 1'b1);
		$display("Start simulation");
		// $readmemb (`INST, inst);
		$readmemb (`A, a_r);
        $readmemb (`B, b_r);
		// $readmemh (`GOLDEN, golden);
		i = 0;
		err_count = 0;
		@(posedge clk);
        #(`HCYCLE);
		while (i < `LEN) begin
            #(`CYCLE) alu_valid = 1;
            a = a_r[i];
            b = b_r[i];
            #(`CYCLE) alu_valid = 0;
            #(`CYCLE)

            // opcode = inst[i][6:0];
            // funct7 = inst[i][31:25];
            // funct3 = inst[i][14:12];
            wait(alu_done === 1);
			@(negedge clk);
            // dumpRegFile(i);
            if (alu_data !== golden_output && !(alu_invalid === 1 && (golden_status === 1 || golden_status === 2 || golden_status === 4))) begin
                $display("----------------------------------------------");
                $display("Error! Answer mismatch at cycle %d:", i);
                $display("a = %b, b = %b, golden = %b, your answer = %b", a, b, golden_output, alu_data);
                $display("alu_invalid = %b, golden_status = %d", alu_invalid, golden_status);
                $display("----------------------------------------------");
                err_count = err_count + 1;
            end
            #(`CYCLE)
            i = i + 1;
		end
		// if (err_count == 0) begin
		// 	$display("----------------------------------------------");
		// 	$display("-                 All passed!                -");
		// 	$display("----------------------------------------------");
		// end else begin
		// 	$display("----------------------------------------------");
		// 	$display("            Error count: %d", err_count);
		// 	$display("----------------------------------------------");
		// end
		$finish;
	end

endmodule