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
	reg [2:0] state, state_nxt;
	reg signed [31:0] PC, PC_nxt;
	reg [2:0] status, status_nxt;
	reg [DATA_WIDTH-1:0] inst, inst_nxt;
	reg signed [DATA_WIDTH-1:0] ImmGen;
	
	reg PC_out_of_range;
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
		.i_w_int(OPCODE==`OP_FADD && (now_inst[31:25] == `FUNCT7_FCLASS || now_inst[31:25] == `FUNCT7_FLT )),	// if FCLASS or FLT	
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
	
	



// ---------------------------------------------------------------------------
// Combinational Blocks
// ---------------------------------------------------------------------------
// ---- Write your conbinational block design here ---- //

	// PC
	always @(*) begin
		PC_nxt = PC;
		// PC_out_of_range = 0;
		if(state == S_WB_PC) begin
			
			if(Branch && alu_comp) begin
				$display("here");
				PC_nxt = PC + (ImmGen);
			end
			else begin
				PC_nxt = PC + 4;
			end

		end
		// $display("state = %d Branch&&alu_comp = %b, PC_nxt: %d",  state,Branch&&alu_comp, PC_nxt);
		PC_out_of_range = (PC_nxt > 4095 || PC_nxt < 0)? 1:0;
	end
	// Inst fetch
	always @(*) begin
		inst_nxt = inst;
		if(state == S_INST_DECODE) begin
			inst_nxt = i_rdata;
		end
		// $display("inst_nxt: %d", inst_nxt);
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
				ALUCtrl = 1;
			end
		
		end
	end

	// ImmGen

	always @(*) begin
		ImmGen = 0;
		if(OPCODE == `OP_ADDI || OPCODE == `OP_LW || OPCODE == `OP_FLW) begin // I type
			ImmGen = {{20{now_inst[31]}}, now_inst[31:20]};
		end
		else if (OPCODE == `OP_SW || OPCODE == `OP_FSW) begin	// S type
			ImmGen = {{20{now_inst[31]}}, now_inst[31:25], now_inst[11:7]};
		end
		else if (OPCODE == `OP_BEQ) begin	// B type
			ImmGen = {{19{now_inst[31]}}, now_inst[31], now_inst[7], now_inst[30:25], now_inst[11:8], 1'b0};
		end
	end


	// ImmGen and status
	always @(*) begin
		// ImmGen = 0;
		status_nxt = status;
		if(isEOF) begin
			status_nxt = 5;
		end
		else if(alu_invalid || PC_out_of_range) begin
			status_nxt = 4;
		end
		else if(OPCODE == `OP_ADDI || OPCODE == `OP_LW || OPCODE == `OP_FLW) begin // I type
			// ImmGen = {{20{now_inst[31]}}, now_inst[31:20]};
			if(state == S_INST_DECODE)
				status_nxt = 1;
		end
		else if (OPCODE == `OP_SW || OPCODE == `OP_FSW) begin	// S type
			// ImmGen = {{20{now_inst[31]}}, now_inst[31:25], now_inst[11:7]};
			if(state == S_INST_DECODE)
				status_nxt = 2;
		end
		else if (OPCODE == `OP_BEQ) begin	// B type
			// ImmGen = {{19{now_inst[31]}}, now_inst[31], now_inst[7], now_inst[30:25], now_inst[11:8], 1'b0};
			if(state == S_INST_DECODE)
				status_nxt = 3;
		end
		else begin
			if(state == S_INST_DECODE)
				status_nxt = 0;
		end
		
	end


	//FSM
	always @(*) begin
		state_nxt = state;
		case(state)
			S_IDLE: begin
				state_nxt = S_INST_FETCH;
			end
			S_INST_FETCH: begin
				state_nxt = S_INST_DECODE;
				// if(PC_out_of_range) begin
				// 	state_nxt = S_STATUS;
				// end
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

