`timescale 1ns/100ps
`define CYCLE       10.0
`define HCYCLE      (`CYCLE/2)
`define MAX_CYCLE   120000
`define PAT_LEN		 1024
`define MEM_DEPTH	 2048
`define MEM_SIZE 	 32
`define STAUS_SIZE	 3
`define MAX_INST	 1024


`ifdef p0
    `define Inst "../00_TB/PATTERN_v3/p0/inst.dat"
		`define GOLDEN_DATA "../00_TB/PATTERN_v3/p0/data.dat"
		`define GOLDEN_STATUS "../00_TB/PATTERN_v3/p0/status.dat"
`elsif p1
    `define Inst "../00_TB/PATTERN_v3/p1/inst.dat"
		`define GOLDEN_DATA "../00_TB/PATTERN_v3/p1/data.dat"
		`define GOLDEN_STATUS "../00_TB/PATTERN_v3/p1/status.dat"
`elsif p2
	`define Inst "../00_TB/PATTERN_v3/p2/inst.dat"
	`define GOLDEN_DATA "../00_TB/PATTERN_v3/p2/data.dat"
	`define GOLDEN_STATUS "../00_TB/PATTERN_v3/p2/status.dat"
`elsif p3
	`define Inst "../00_TB/PATTERN_v3/p3/inst.dat"
	`define GOLDEN_DATA "../00_TB/PATTERN_v3/p3/data.dat"
	`define GOLDEN_STATUS "../00_TB/PATTERN_v3/p3/status.dat"
`else
	`define Inst "../00_TB/PATTERN_v3/p0/inst.dat"
	`define GOLDEN_DATA "../00_TB/PATTERN_v3/p0/data.dat"
	`define GOLDEN_STATUS "../00_TB/PATTERN_v3/p0/status.dat"
`endif

module testbed;

	reg  rst_n;
	reg  clk = 0;
	wire            dmem_we;
	wire [ 31 : 0 ] dmem_addr;
	wire [ 31 : 0 ] dmem_wdata;
	wire [ 31 : 0 ] dmem_rdata;
	wire [  2 : 0 ] mips_status;
	wire            mips_status_valid;

	integer input_end, output_end, test_end, check_end;
	integer correct, error;
	integer j, k;

	// TB variables
	reg [`MEM_SIZE-1:0] golden_data [0:`MEM_DEPTH-1];
	reg [`STAUS_SIZE-1:0] golden_status [0:`MAX_INST-1];
	reg [31:0] test_addr;

	core u_core (
		.i_clk(clk),
		.i_rst_n(rst_n),
		.o_status(mips_status),
		.o_status_valid(mips_status_valid),
		.o_we(dmem_we),
		.o_addr(dmem_addr),
		.o_wdata(dmem_wdata),
		.i_rdata(dmem_rdata)
	);

	data_mem  u_data_mem (
		.i_clk(clk),
		.i_rst_n(rst_n),
		.i_we(dmem_we),
		.i_addr((output_end)?test_addr:dmem_addr),
		.i_wdata(dmem_wdata),
		.o_rdata(dmem_rdata)
	);

	// Clock generator
	always #(`HCYCLE) clk = ~clk;

	// load data memory & rst_n signal
	initial begin 
		rst_n = 1;
		#(0.25 * `CYCLE) rst_n = 0;
		#(`CYCLE) rst_n = 1;
		$readmemb (`Inst, u_data_mem.mem_r);
		$readmemb(`GOLDEN_DATA, golden_data);
		$readmemb(`GOLDEN_STATUS, golden_status);
	end

	initial begin
		wait (rst_n === 1'b0);
		wait (rst_n === 1'b1);
		#(         `MAX_CYCLE * `CYCLE);
		$display("Error! Runtime exceeded!");
    $finish;
	end

	initial begin
		$fsdbDumpfile("core.fsdb");
		$fsdbDumpvars(0, testbed, "+mda");
	end

	// Output
	initial begin
		correct = 0;
		error   = 0;
		output_end = 0;

		// wait for reset to finish
		wait (rst_n === 1'b0);
		wait (rst_n === 1'b1);

		// start
		@(posedge clk);

		// loop
		k = 0;
		while (k < `MAX_INST) begin
			@(negedge clk);
			if (mips_status_valid) begin
				if (mips_status === golden_status[k]) begin
					correct = correct + 1;
				end
				else begin
					error = error + 1;
					$display(
						"Test[%d]: Error! Golden_status=%b, Yours=%b",
						k,
						golden_status[k],
						mips_status,
					);
				end
				k = k+1;
				if(mips_status === `EOF_TYPE || mips_status == `INVALID_TYPE) begin
					k = `MAX_INST;
				end
			end
			@(posedge clk);
		end
			// final
		output_end = 1;
	end

	initial begin
		check_end = 0;
		wait (output_end == 1);
		for(j=0; j<`MEM_DEPTH; j=j+1) begin
			@(posedge clk);
			test_addr = j*4;
			#(`CYCLE);
			@(negedge clk);
			if (dmem_rdata !== golden_data[j]) begin
				$display("Error! Data mismatch at address %d. Expected: %b, Got: %b",
				 j*4-4096, golden_data[j], dmem_rdata);
				error = error + 1;
			end
		end
		check_end = 1;
	end

	initial begin
		wait (output_end && check_end);

		if (error === 0) begin
				$display("----------------------------------------------");
				$display("-                 ALL PASS!                  -");
				$display("----------------------------------------------");
		end
		else begin
				$display("----------------------------------------------");
				$display("  Wrong! Total Error: %d                      ", error);
				$display("----------------------------------------------");
		end

		# (2 * `CYCLE);
		$finish;
	end



endmodule