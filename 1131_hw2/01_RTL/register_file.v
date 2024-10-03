
module register_file #(
  parameter DATA_WIDTH = 32,
  parameter REG_SIZE = 32,
  parameter ADDR_WIDTH = 5
) (
  input i_clk,
  input i_rst_n,
  input i_wen,
  input i_float,
  input [ADDR_WIDTH-1:0] i_rs1,
  input [ADDR_WIDTH-1:0] i_rs2,
  input [ADDR_WIDTH-1:0] i_rd,
  input [DATA_W-1:0] i_wdata,
  output [DATA_W-1:0] o_rdata1,
  output [DATA_W-1:0] o_rdata2
);
  
  reg signed [DATA_WIDTH-1:0] ireg [0:REG_SIZE-1];
  reg signed [DATA_WIDTH-1:0] ireg_nxt;
  reg [DATA_WIDTH-1:0] freg [0:REG_SIZE-1];
  reg signed [DATA_WIDTH-1:0] freg_nxt [0:REG_SIZE-1];

  integer i;

  assign o_rdata1 = (i_float)? freg[i_rs1] : ireg[i_rs1];
  assign o_rdata2 = (i_float)? freg[i_rs2] : ireg[i_rs2];

  always @(*) begin
    ireg_nxt = (i_wen && !i_float) ? i_wdata : ireg[i_rd];
    freg_nxt = (i_wen && i_float) ? i_wdata : freg[i_rd];
  end

  always @(posedge i_clk or negedge i_rst_n) begin
    if(!i_rst_n) begin
      for(i=0; i<REG_SIZE; i=i+1) begin
        ireg[i] <= 0;
        freg[i] <= 0;
      end
    end
    else begin
      ireg[i_rd] <= ireg_nxt;
      freg[i_rd] <= freg_nxt;
    end
  end

  

endmodule

module Reg_file(i_clk, i_rst_n, wen, rs1, rs2, rd, wdata, rdata1, rdata2);
   
    parameter BITS = 32;
    parameter word_depth = 32;
    parameter addr_width = 5; // 2^addr_width >= word_depth
    
    input i_clk, i_rst_n, wen; // wen: 0:read | 1:write
    input [BITS-1:0] wdata;
    input [addr_width-1:0] rs1, rs2, rd;

    output [BITS-1:0] rdata1, rdata2;

    reg [BITS-1:0] mem [0:word_depth-1];
    reg [BITS-1:0] mem_nxt [0:word_depth-1];

    integer i;

    assign rdata1 = mem[rs1];
    assign rdata2 = mem[rs2];

    always @(*) begin
        for (i=0; i<word_depth; i=i+1)
            mem_nxt[i] = (wen && (rd == i)) ? wdata : mem[i];
    end

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            mem[0] <= 0;
            for (i=1; i<word_depth; i=i+1) begin
                case(i)
                    32'd2: mem[i] <= 32'hbffffff0;
                    32'd3: mem[i] <= 32'h10008000;
                    default: mem[i] <= 32'h0;
                endcase
            end
        end
        else begin
            mem[0] <= 0;
            for (i=1; i<word_depth; i=i+1)
                mem[i] <= mem_nxt[i];
        end       
    end
endmodule