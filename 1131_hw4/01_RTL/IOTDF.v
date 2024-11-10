`timescale 1ns/10ps
module IOTDF( clk, rst, in_en, iot_in, fn_sel, busy, valid, iot_out);
input          clk;
input          rst;
input          in_en;
input  [7:0]   iot_in;
input  [2:0]   fn_sel;
output         busy;
output         valid;
output [127:0] iot_out;

  // function select
  localparam FN_ENCRYPT = 3'b001;
  localparam FN_DECRYPT = 3'b010;
  localparam FN_CRC_GEN = 3'b011;
  localparam FN_TOP2MAX = 3'b100;
  localparam FN_LAST2MIN = 3'b101;

  // state
  localparam S_IDLE = 4'd0;
  localparam S_LOAD = 4'd1;   // load to text
  localparam S_MINMAX = 4'd2;   // calculation
  localparam S_CRYPT = 4'd3;   // calculation
  localparam S_CRC = 4'd4;   // calculation
  localparam S_OUTPUT = 4'd5;   // output


  reg [130:0] data, data_nxt; // Dividend and remainder, biggest, smallest, plaintext
  reg [130:0] divisor, divisor_nxt; // Divisor, second biggest, second smallest, key
  reg [127:0] iot_data_out, iot_data_out_nxt; // output data
  reg [127:0] loaded_data, loaded_data_nxt; // loaded data 
  reg [3:0] state, state_nxt;
  reg [6:0] cnt_data, cnt_data_nxt;
  reg [3:0] cnt_load, cnt_load_nxt;
  wire crypt_done, crc_done, minmax_done;
  wire [63:0] crypt_plaintext_out, crypt_key_out;
  wire [47:0] crypt_text_intermediate_out;
  wire [130:0] crc_divisor_out, crc_remainder_out;
  wire [127:0] minmax_reg1_out, minmax_reg2_out;
  reg total_o_valid;
  reg o_busy_reg, o_busy_nxt, to_module_valid, to_module_valid_nxt;
  wire [127:0] crc_final_out, minmax_final_out;
  wire crc_o_valid, minmax_o_valid, crypt_o_valid;

  ENCRYPT crypt0 (
    .i_clk(clk),
    .i_rst(rst),
    .plaintext(data[63:0]),
    .key(divisor[63:0]),
    .text_intermediate(data[111:64]),
    .i_valid(to_module_valid),
    .i_encrypt(fn_sel == FN_ENCRYPT),
    .o_plaintext(crypt_plaintext_out),
    .o_key(crypt_key_out),
    .o_text_intermediate(crypt_text_intermediate_out),
    .o_valid(crypt_o_valid)
  );

  CRC crc0 (
    .i_clk(clk),
    .i_rst(rst),
    .i_valid(to_module_valid),
    .i_remainder(data),
    // .i_divisor(divisor),
    .o_remainder(crc_remainder_out),
    // .o_divisor(crc_divisor_out),
    .o_final_out(crc_final_out),
    .o_valid(crc_o_valid)
  );

  MinMax minmax0 (
    .i_clk(clk),
    .i_rst(rst),
    .iot_data(loaded_data),
    .i_valid(to_module_valid_nxt),
    .i_Max(fn_sel == FN_TOP2MAX),
    .reg1(data[127:0]),
    .reg2(divisor[127:0]),
    .o_reg1(minmax_reg1_out),
    .o_reg2(minmax_reg2_out),
    .o_final_out(minmax_final_out),
    .o_valid(minmax_o_valid)
  ); 

  assign busy = o_busy_nxt; //! be careful, not reg
  assign valid = total_o_valid;
  assign iot_out = iot_data_out_nxt;




  // FSM
  always @(*) begin
    state_nxt = state;
    case(state)
      S_IDLE: begin
        case(fn_sel)
          FN_ENCRYPT, FN_DECRYPT: state_nxt = S_CRYPT;
          FN_CRC_GEN: state_nxt = S_CRC;
          FN_TOP2MAX, FN_LAST2MIN: state_nxt = S_MINMAX;
        endcase
      end
      // S_MINMAX: begin
      //   if(cnt_load == 15 && cnt_data == 3'd6)
      //     state_nxt = S_OUTPUT;
      // end
      // S_OUTPUT: state_nxt = S_MINMAX;
    endcase
  end

  // Counter
  always @(*) begin
    cnt_load_nxt = 0;
    cnt_data_nxt = cnt_data;
    o_busy_nxt = o_busy_reg;
    case(state)
      S_IDLE: begin
        cnt_data_nxt = 0;
        o_busy_nxt = 0;
      end
      S_LOAD: begin
        if(in_en)
          cnt_load_nxt = cnt_load + 1;
        if(cnt_load == 15) begin
          cnt_data_nxt = cnt_data + 1;
        end
      end
      S_MINMAX: begin
        o_busy_nxt = 0;
        if(in_en)
          cnt_load_nxt = cnt_load + 1;
        if(cnt_load == 15) begin
          cnt_data_nxt = cnt_data + 1;
          // if(cnt_data[2:0] == 3'd6)
          //   o_busy_nxt = 1;
        end
      end
      S_CRYPT, S_CRC: begin
        if(in_en)
          cnt_load_nxt = cnt_load + 1;
        if(cnt_load == 15) begin
          cnt_data_nxt = cnt_data + 1;
          if(cnt_data != 0)
            o_busy_nxt = 1;
        end else if(total_o_valid) begin
          o_busy_nxt = 0;
        end
      end
    endcase 
  end
  
  // signals
  always @(*) begin
    total_o_valid = 0;
    iot_data_out_nxt = 0;
    to_module_valid_nxt = 0;
    case(fn_sel)
      FN_DECRYPT, FN_ENCRYPT: begin
        total_o_valid = crypt_o_valid;
        iot_data_out_nxt = {divisor[127:64], crypt_plaintext_out};
        if(crypt_o_valid || (cnt_load == 15 && cnt_data == 0))
          to_module_valid_nxt = 1;
        // to_module_valid = (cnt_load == 0 && cnt_data[2:0] != 0);
      end
      FN_CRC_GEN: begin
        total_o_valid = crc_o_valid;
        iot_data_out_nxt = crc_final_out;
        if(crc_o_valid || (cnt_load == 15 && cnt_data == 0))
          to_module_valid_nxt = 1;
      
        // to_module_valid_nxt = (cnt_load == 0 && cnt_data != 0 && in_en);
      end
      FN_TOP2MAX, FN_LAST2MIN: begin
        total_o_valid = minmax_o_valid;
        iot_data_out_nxt = minmax_final_out;
        to_module_valid_nxt = (cnt_load == 0 && cnt_data != 0);
      end
    endcase
  end

  // Load data
  always @(*) begin
    data_nxt = data;
    divisor_nxt = divisor;
    loaded_data_nxt = loaded_data;
    case(state)
      S_MINMAX: begin
        if(in_en)
          loaded_data_nxt[cnt_load*8 +: 8] = iot_in;
        data_nxt = minmax_reg1_out;
        divisor_nxt = minmax_reg2_out;
      end
      S_CRYPT: begin
        if(in_en) begin
          loaded_data_nxt[cnt_load*8 +: 8] = iot_in; 
          // data_nxt = {{19'b0}, crypt_text_intermediate_out, crypt_plaintext_out};
          // divisor_nxt = {{3'b0}, divisor[127:64], crypt_key_out};
        end
        if(crypt_o_valid || (cnt_load == 15 && cnt_data == 0)) begin
          data_nxt = {{67'b0}, loaded_data_nxt[63:0]};    // plaintext
          divisor_nxt = {{3'b0}, loaded_data_nxt[127:64], loaded_data_nxt[127:64]};   // key
        end else begin
          data_nxt = {{19'b0}, crypt_text_intermediate_out, crypt_plaintext_out};
          divisor_nxt = {{3'b0}, divisor[127:64], crypt_key_out};
        end
        
      end
      S_CRC: begin
        if(in_en) begin
          loaded_data_nxt[cnt_load*8 +: 8] = iot_in;
        end
        if(crc_o_valid || (cnt_load == 15 && cnt_data == 0)) begin
          data_nxt = {loaded_data_nxt, {3'b0}}; // dividend
          divisor_nxt = {{4'b1110}, {127'b0}};
        end else begin
          data_nxt = crc_remainder_out;
          divisor_nxt = divisor;
        end
      end
    endcase
  end

  // Sequential logic
  always @(posedge clk or posedge rst) begin
    if(rst) begin
      data <= 0;
      divisor <= 0;
      // iot_data <= 0;
      state <= S_IDLE;
      cnt_data <= 0;
      cnt_load <= 0;
      o_busy_reg <= 1;
      loaded_data <= 0;
      to_module_valid <= 0;
    end else begin
      data <= data_nxt;
      divisor <= divisor_nxt;
      // iot_data <= iot_data_nxt;
      state <= state_nxt;
      cnt_data <= cnt_data_nxt;
      cnt_load <= cnt_load_nxt;
      o_busy_reg <= o_busy_nxt;
      loaded_data <= loaded_data_nxt;
      to_module_valid <= to_module_valid_nxt;
    end
  end

endmodule

module ENCRYPT(
  input i_clk,
  input i_rst,
  input [63:0] plaintext,
  input [63:0] key,
  input [47:0] text_intermediate,
  input i_valid,
  input i_encrypt,    // 1: encrypt, 0: decrypt
  output [63:0] o_plaintext,
  output [63:0] o_key,
  output [47:0] o_text_intermediate,
  output o_valid
);
  // state
  localparam S_IDLE = 3'd0;
  localparam S_PC1_ROTATE = 3'd1;
  localparam S_GEN_K1 = 3'd2;
  localparam S_ENCRYPT = 3'd3;
  localparam S_FIN_PERMUTATION = 3'd4;
  localparam S_DONE = 3'd5;
  // PC2 lookup table
  reg [5:0] PC1 [55:0] = '{6'd7,6'd15,6'd23,6'd31,6'd39,6'd47,6'd55,6'd63,6'd6,6'd14,6'd22,6'd30,6'd38,6'd46,6'd54,6'd62,6'd5,6'd13,6'd21,6'd29,6'd37,6'd45,6'd53,6'd61,6'd4,6'd12,6'd20,6'd28,6'd1,6'd9,6'd17,6'd25,6'd33,6'd41,6'd49,6'd57,6'd2,6'd10,6'd18,6'd26,6'd34,6'd42,6'd50,6'd58,6'd3,6'd11,6'd19,6'd27,6'd35,6'd43,6'd51,6'd59,6'd36,6'd44,6'd52,6'd60};
  reg [5:0] PC2 [47:0] = '{6'd42, 6'd39, 6'd45, 6'd32, 6'd55, 6'd51, 6'd53, 6'd28, 6'd41, 6'd50, 6'd35, 6'd46, 6'd33, 6'd37, 6'd44, 6'd52, 6'd30, 6'd48, 6'd40, 6'd49, 6'd29, 6'd36, 6'd43, 6'd54, 6'd15, 6'd4, 6'd25, 6'd19, 6'd9, 6'd1, 6'd26, 6'd16, 6'd5, 6'd11, 6'd23, 6'd8, 6'd12, 6'd7, 6'd17, 6'd0, 6'd22, 6'd3, 6'd10, 6'd14, 6'd6, 6'd20, 6'd27, 6'd24};
  reg [3:0] S1 [0:3][0:15] = '{'{4'd14, 4'd4, 4'd13, 4'd1, 4'd2, 4'd15, 4'd11, 4'd8, 4'd3, 4'd10, 4'd6, 4'd12, 4'd5, 4'd9, 4'd0, 4'd7},
  '{4'd0, 4'd15, 4'd7, 4'd4, 4'd14, 4'd2, 4'd13, 4'd1, 4'd10, 4'd6, 4'd12, 4'd11, 4'd9, 4'd5, 4'd3, 4'd8},
  '{4'd4, 4'd1, 4'd14, 4'd8, 4'd13, 4'd6, 4'd2, 4'd11, 4'd15, 4'd12, 4'd9, 4'd7, 4'd3, 4'd10, 4'd5, 4'd0},
  '{4'd15, 4'd12, 4'd8, 4'd2, 4'd4, 4'd9, 4'd1, 4'd7, 4'd5, 4'd11, 4'd3, 4'd14, 4'd10, 4'd0, 4'd6, 4'd13}
  };
  reg [3:0] S2 [0:3][0:15] = '{'{4'd15, 4'd1, 4'd8, 4'd14, 4'd6, 4'd11, 4'd3, 4'd4, 4'd9, 4'd7, 4'd2, 4'd13, 4'd12, 4'd0, 4'd5, 4'd10},
  '{4'd3, 4'd13, 4'd4, 4'd7, 4'd15, 4'd2, 4'd8, 4'd14, 4'd12, 4'd0, 4'd1, 4'd10, 4'd6, 4'd9, 4'd11, 4'd5},
  '{4'd0, 4'd14, 4'd7, 4'd11, 4'd10, 4'd4, 4'd13, 4'd1, 4'd5, 4'd8, 4'd12, 4'd6, 4'd9, 4'd3, 4'd2, 4'd15},
  '{4'd13, 4'd8, 4'd10, 4'd1, 4'd3, 4'd15, 4'd4, 4'd2, 4'd11, 4'd6, 4'd7, 4'd12, 4'd0, 4'd5, 4'd14, 4'd9}
  };
  reg [3:0] S3 [0:3][0:15] = '{'{4'd10, 4'd0, 4'd9, 4'd14, 4'd6, 4'd3, 4'd15, 4'd5, 4'd1, 4'd13, 4'd12, 4'd7, 4'd11, 4'd4, 4'd2, 4'd8},
  '{4'd13, 4'd7, 4'd0, 4'd9, 4'd3, 4'd4, 4'd6, 4'd10, 4'd2, 4'd8, 4'd5, 4'd14, 4'd12, 4'd11, 4'd15, 4'd1},
  '{4'd13, 4'd6, 4'd4, 4'd9, 4'd8, 4'd15, 4'd3, 4'd0, 4'd11, 4'd1, 4'd2, 4'd12, 4'd5, 4'd10, 4'd14, 4'd7},
  '{4'd1, 4'd10, 4'd13, 4'd0, 4'd6, 4'd9, 4'd8, 4'd7, 4'd4, 4'd15, 4'd14, 4'd3, 4'd11, 4'd5, 4'd2, 4'd12}
  };
  reg [3:0] S4 [0:3][0:15] = '{'{4'd7, 4'd13, 4'd14, 4'd3, 4'd0, 4'd6, 4'd9, 4'd10, 4'd1, 4'd2, 4'd8, 4'd5, 4'd11, 4'd12, 4'd4, 4'd15},
  '{4'd13, 4'd8, 4'd11, 4'd5, 4'd6, 4'd15, 4'd0, 4'd3, 4'd4, 4'd7, 4'd2, 4'd12, 4'd1, 4'd10, 4'd14, 4'd9},
  '{4'd10, 4'd6, 4'd9, 4'd0, 4'd12, 4'd11, 4'd7, 4'd13, 4'd15, 4'd1, 4'd3, 4'd14, 4'd5, 4'd2, 4'd8, 4'd4},
  '{4'd3, 4'd15, 4'd0, 4'd6, 4'd10, 4'd1, 4'd13, 4'd8, 4'd9, 4'd4, 4'd5, 4'd11, 4'd12, 4'd7, 4'd2, 4'd14}
  };
  reg [3:0] S5 [0:3][0:15] = '{'{4'd2, 4'd12, 4'd4, 4'd1, 4'd7, 4'd10, 4'd11, 4'd6, 4'd8, 4'd5, 4'd3, 4'd15, 4'd13, 4'd0, 4'd14, 4'd9},
  '{4'd14, 4'd11, 4'd2, 4'd12, 4'd4, 4'd7, 4'd13, 4'd1, 4'd5, 4'd0, 4'd15, 4'd10, 4'd3, 4'd9, 4'd8, 4'd6},
  '{4'd4, 4'd2, 4'd1, 4'd11, 4'd10, 4'd13, 4'd7, 4'd8, 4'd15, 4'd9, 4'd12, 4'd5, 4'd6, 4'd3, 4'd0, 4'd14},
  '{4'd11, 4'd8, 4'd12, 4'd7, 4'd1, 4'd14, 4'd2, 4'd13, 4'd6, 4'd15, 4'd0, 4'd9, 4'd10, 4'd4, 4'd5, 4'd3}
  };
  reg [3:0] S6 [0:3][0:15] = '{'{4'd12, 4'd1, 4'd10, 4'd15, 4'd9, 4'd2, 4'd6, 4'd8, 4'd0, 4'd13, 4'd3, 4'd4, 4'd14, 4'd7, 4'd5, 4'd11},
  '{4'd10, 4'd15, 4'd4, 4'd2, 4'd7, 4'd12, 4'd9, 4'd5, 4'd6, 4'd1, 4'd13, 4'd14, 4'd0, 4'd11, 4'd3, 4'd8},
  '{4'd9, 4'd14, 4'd15, 4'd5, 4'd2, 4'd8, 4'd12, 4'd3, 4'd7, 4'd0, 4'd4, 4'd10, 4'd1, 4'd13, 4'd11, 4'd6},
  '{4'd4, 4'd3, 4'd2, 4'd12, 4'd9, 4'd5, 4'd15, 4'd10, 4'd11, 4'd14, 4'd1, 4'd7, 4'd6, 4'd0, 4'd8, 4'd13}
  };
  reg [3:0] S7 [0:3][0:15] = '{'{4'd4, 4'd11, 4'd2, 4'd14, 4'd15, 4'd0, 4'd8, 4'd13, 4'd3, 4'd12, 4'd9, 4'd7, 4'd5, 4'd10, 4'd6, 4'd1},
  '{4'd13, 4'd0, 4'd11, 4'd7, 4'd4, 4'd9, 4'd1, 4'd10, 4'd14, 4'd3, 4'd5, 4'd12, 4'd2, 4'd15, 4'd8, 4'd6},
  '{4'd1, 4'd4, 4'd11, 4'd13, 4'd12, 4'd3, 4'd7, 4'd14, 4'd10, 4'd15, 4'd6, 4'd8, 4'd0, 4'd5, 4'd9, 4'd2},
  '{4'd6, 4'd11, 4'd13, 4'd8, 4'd1, 4'd4, 4'd10, 4'd7, 4'd9, 4'd5, 4'd0, 4'd15, 4'd14, 4'd2, 4'd3, 4'd12}
  };
  reg [3:0] S8 [0:3][0:15] = '{'{4'd13, 4'd2, 4'd8, 4'd4, 4'd6, 4'd15, 4'd11, 4'd1, 4'd10, 4'd9, 4'd3, 4'd14, 4'd5, 4'd0, 4'd12, 4'd7},
  '{4'd1, 4'd15, 4'd13, 4'd8, 4'd10, 4'd3, 4'd7, 4'd4, 4'd12, 4'd5, 4'd6, 4'd11, 4'd0, 4'd14, 4'd9, 4'd2},
  '{4'd7, 4'd11, 4'd4, 4'd1, 4'd9, 4'd12, 4'd14, 4'd2, 4'd0, 4'd6, 4'd10, 4'd13, 4'd15, 4'd3, 4'd5, 4'd8},
  '{4'd2, 4'd1, 4'd14, 4'd7, 4'd4, 4'd10, 4'd8, 4'd13, 4'd15, 4'd12, 4'd9, 4'd0, 4'd3, 4'd5, 4'd6, 4'd11}
  };
  reg [4:0] P [31:0] =  '{5'd16,5'd25,5'd12,5'd11,5'd3,5'd20,5'd4,5'd15,5'd31,5'd17,5'd9,5'd6,5'd27,5'd14,5'd1,5'd22,5'd30,5'd24,5'd8,5'd18,5'd0,5'd5,5'd29,5'd23,5'd13,5'd19,5'd2,5'd26,5'd10,5'd21,5'd28,5'd7};
  reg [5:0] Expansion [47:0] = '{6'd0,6'd31,6'd30,6'd29,6'd28,6'd27,6'd28,6'd27,6'd26,6'd25,6'd24,6'd23,6'd24,6'd23,6'd22,6'd21,6'd20,6'd19,6'd20,6'd19,6'd18,6'd17,6'd16,6'd15,6'd16,6'd15,6'd14,6'd13,6'd12,6'd11,6'd12,6'd11,6'd10,6'd9,6'd8,6'd7,6'd8,6'd7,6'd6,6'd5,6'd4,6'd3,6'd4,6'd3,6'd2,6'd1,6'd0,6'd31};
  reg [5:0] Final_permutation [63:0] = '{6'd24,6'd56,6'd16,6'd48,6'd8,6'd40,6'd0,6'd32,6'd25,6'd57,6'd17,6'd49,6'd9,6'd41,6'd1,6'd33,6'd26,6'd58,6'd18,6'd50,6'd10,6'd42,6'd2,6'd34,6'd27,6'd59,6'd19,6'd51,6'd11,6'd43,6'd3,6'd35,6'd28,6'd60,6'd20,6'd52,6'd12,6'd44,6'd4,6'd36,6'd29,6'd61,6'd21,6'd53,6'd13,6'd45,6'd5,6'd37,6'd30,6'd62,6'd22,6'd54,6'd14,6'd46,6'd6,6'd38,6'd31,6'd63,6'd23,6'd55,6'd15,6'd47,6'd7,6'd39};
  reg [3:0] cnt, cnt_nxt;
  reg [2:0] state, state_nxt;
  reg [63:0] plaintext_nxt, key_nxt, key_tmp, key_permuted, text_expended;
  reg [47:0] key_now, text_tmp;
  wire [31:0] text_intermediate_nxt;
  reg [31:0]  F_out, R_nxt, L_nxt;
  wire [31:0] R_now, L_now;
  wire [1:0] row [7:0];
  wire [3:0] col [7:0];
  wire shift_one_bit;
  integer i;

  assign shift_one_bit = (cnt == 6 || cnt == 13 || state == S_GEN_K1);
  assign o_text_intermediate = text_intermediate_nxt;
  assign o_key = key_nxt;
  assign o_plaintext = plaintext_nxt;
  assign o_valid = (state == S_FIN_PERMUTATION);
  assign R_now = plaintext[31:0];
  assign L_now = plaintext[63:32];

  genvar gi;
  generate
  for(gi = 0; gi < 8; gi = gi + 1) begin : SBOX
    assign row[7-gi] = {text_tmp[gi*6 + 5], text_tmp[gi*6]};
    assign col[7-gi] = text_tmp[(gi*6 + 4) -: 4];
  end
  endgenerate

  assign text_intermediate_nxt = {S1[row[0]][col[0]], S2[row[1]][col[1]], S3[row[2]][col[2]], S4[row[3]][col[3]], S5[row[4]][col[4]], S6[row[5]][col[5]], S7[row[6]][col[6]], S8[row[7]][col[7]]};
  

  // FSM
  always @(*) begin
    state_nxt = state;
    case(state)
      S_IDLE: begin
        if(i_valid) state_nxt = S_PC1_ROTATE;
      end
      S_PC1_ROTATE: state_nxt = S_GEN_K1;
      S_GEN_K1: state_nxt = S_ENCRYPT;
      S_ENCRYPT: begin
        if(cnt == 14) state_nxt = S_FIN_PERMUTATION;
      end
      S_FIN_PERMUTATION: state_nxt = S_PC1_ROTATE; //! need modification
      S_DONE: state_nxt = S_IDLE; 
    endcase
  end

  // Counter
  always @(*) begin
    cnt_nxt = 0;
    if(state == S_ENCRYPT) begin
      cnt_nxt = cnt + 1;
    end
  end

  // key generation && text tmp --> text intermediate
  always @(*) begin
    for(i = 0; i < 48; i = i + 1) begin
      key_tmp[i] = key[PC2[i]];
    end
    key_tmp[63:48] = 0;
    key_nxt = key;
    // key_tmp = 0;
    key_permuted = 0;
    case(state)
      S_PC1_ROTATE: begin
        // for(i=0; i<8; i=i+1) begin    // PC1
        //   key_permuted[55-i] = key[7+(i<<3)];
        //   key_permuted[47-i] = key[6+(i<<3)];
        //   key_permuted[39-i] = key[5+(i<<3)];
        //   key_permuted[31-i] = key[4+(i<<3)];
        //   key_permuted[23-i] = key[1+(i<<3)];
        //   key_permuted[15-i] = key[2+(i<<3)];
        //   key_permuted[7-i] = key[3+(i<<3)];
        // end
        // key_tmp = {key_permuted[55:28], key_permuted[23:0], key_permuted[27:24]};    // for completing PC1 (left rotate by 4)
        for(i=0; i<56; i=i+1) begin
          key_tmp[i] = key[PC1[i]];
        end
        if(i_encrypt) 
          key_nxt = {key_tmp[54:28], key_tmp[55], key_tmp[26:0], key_tmp[27]};  // upper and lower part circular shift left repectively
        else
          key_nxt = key_tmp;
      end
      // S_GEN_K1: begin
      //   if(i_encrypt) begin
      //     key_nxt = {key[54:28], key[55], key[26:0], key[27]};    // left rotate 1 bit
      //   end else begin
      //     key_nxt = {key[28], key[55:29], key[0], key[27:1]};   // right rotate 1 bit
      //   end
      // end
      S_ENCRYPT, S_GEN_K1: begin
        if(i_encrypt) begin // left rotate
          if(shift_one_bit)
            key_nxt = {key[54:28], key[55], key[26:0], key[27]};
          else
            key_nxt = {key[53:28], key[55:54], key[25:0], key[27:26]};
        end else begin
          if(shift_one_bit)   // cnt == 14 has no effect  // right rotate
            key_nxt = {key[28], key[55:29], key[0], key[27:1]};
          else
            key_nxt = {key[29:28], key[55:30], key[1:0], key[27:2]};
        end
        // for(i=0; i<48; i=i+1)
        //   key_tmp[i] = key[PC2[i]];
      end
    endcase
    for(i=0; i<48; i=i+1)
      text_expended[i] = R_now[Expansion[i]];
    text_tmp = key_tmp[47:0] ^ text_expended;
  end

  // F function && plaintext_nxt
  always @(*) begin
    for(i=0; i<32; i=i+1) begin
      F_out[i] = text_intermediate_nxt[P[i]];
    end
    R_nxt = R_now;
    L_nxt = L_now;
    plaintext_nxt = plaintext;
    case(state)
      S_PC1_ROTATE: begin
        // Initial permutation of plaintext
        for(i=0; i<8; i=i+1) begin
          plaintext_nxt[63-i] = plaintext[6+(i<<3)];
          plaintext_nxt[55-i] = plaintext[4+(i<<3)];
          plaintext_nxt[47-i] = plaintext[2+(i<<3)];
          plaintext_nxt[39-i] = plaintext[0+(i<<3)];
          plaintext_nxt[31-i] = plaintext[7+(i<<3)];
          plaintext_nxt[23-i] = plaintext[5+(i<<3)];
          plaintext_nxt[15-i] = plaintext[3+(i<<3)];
          plaintext_nxt[7-i] = plaintext[1+(i<<3)];
        end
      end
      S_GEN_K1: begin
        for(i=0; i<32; i=i+1) begin
          F_out[i] = text_intermediate_nxt[P[i]];
        end
        R_nxt = L_now ^ F_out;
        L_nxt = R_now;
        
        plaintext_nxt = {L_nxt, R_nxt};
      end
      S_ENCRYPT: begin
        if(cnt == 14) begin
          R_nxt = R_now;
          L_nxt = L_now ^ F_out;
        end else begin
          R_nxt = L_now ^ F_out;
          L_nxt = R_now;
        end
        plaintext_nxt = {L_nxt, R_nxt};
      end
      S_FIN_PERMUTATION: begin
        for(i=0; i<64; i=i+1) begin
          plaintext_nxt[i] = plaintext[Final_permutation[i]];
        end
      end
    endcase
    
  end

  // Sequential logic
  always @(posedge i_clk or posedge i_rst) begin
    if(i_rst) begin
      state <= S_IDLE;
      cnt <= 0;
    end else begin
      state <= state_nxt;
      cnt <= cnt_nxt;
    end
  end
  
endmodule

module CRC(
  input i_clk,
  input i_rst,
  input i_valid,
  input [130:0] i_remainder,
  // input [130:0] i_divisor,
  output [130:0] o_remainder,
  // output [130:0] o_divisor,
  output [127:0] o_final_out,
  output o_valid
);
  // state
  localparam S_IDLE = 2'd0;
  localparam S_CALC = 2'd1;
  localparam S_DONE = 2'd2;

  localparam DIVISOR = {{4'b1110}, {127'b0}};
  

  reg [1:0] state, state_nxt;
  reg [130:0] data_tmp, o_remainder_nxt, o_divisor_nxt;
  // reg [2:0] crc, crc_nxt;
  // core can handle crc on its own
  reg [7:0] cnt, cnt_nxt;

  assign o_remainder = o_remainder_nxt;
  // assign o_divisor = o_divisor_nxt;
  assign o_final_out = {{125'b0}, o_remainder_nxt[130:128]};
  assign o_valid = (cnt == 127);
  // Counter
  always @(*) begin
    cnt_nxt = 0;
    if(state == S_CALC || (state == S_IDLE && i_valid)) begin
      if(cnt == 127)
        cnt_nxt = 0;
      else
        cnt_nxt = cnt + 1;
    end
  end
  // FSM
  always @(*) begin
    state_nxt = state;
    case(state)
      S_IDLE: begin
        if(i_valid) state_nxt = S_CALC;
      end
      S_CALC: begin
        if(cnt == 127)
          state_nxt = S_IDLE;   //! not sure
      end
      S_DONE: state_nxt = S_IDLE;
    endcase
  end

  // calculation
  always @(*) begin
    o_remainder_nxt = i_remainder;
    // o_divisor_nxt = i_divisor;
    data_tmp = 0;
    if(state == S_CALC || (state == S_IDLE && i_valid)) begin
      if(i_remainder[130]) begin
        data_tmp = i_remainder ^ DIVISOR;
        o_remainder_nxt = {{data_tmp[129:0]}, {1'b1}};
      end else begin
        o_remainder_nxt = {i_remainder[129:0], {1'b0}};
      end
      // o_divisor_nxt = i_divisor >> 1;
    end
  end

  // Sequential logic
  always @(posedge i_clk or posedge i_rst) begin
    if(i_rst) begin
      state <= S_IDLE;
      cnt <= 0;
    end else begin
      state <= state_nxt;
      cnt <= cnt_nxt;
    end
  end
endmodule

module MinMax(
  input i_clk,
  input i_rst,
  input [127:0] iot_data,
  input i_valid,
  input i_Max,   // 1: top2max, 0: last2min
  input [127:0] reg1,
  input [127:0] reg2,
  output [127:0] o_reg1,
  output [127:0] o_reg2,
  output [127:0] o_final_out,
  output o_valid
);

  // State
  localparam S_IDLE = 2'd0;
  localparam S_CALC = 2'd1;
  localparam S_DONE = 2'd2;

  reg [1:0] state, state_nxt;
  reg [127:0] reg1_nxt, reg2_nxt;
  reg [2:0] cnt, cnt_nxt;

  assign o_reg1 = reg1_nxt;
  assign o_reg2 = reg2_nxt;
  assign o_final_out = (cnt == 7)? reg1_nxt : reg2_nxt;
  assign o_valid = (state == S_DONE || (state == S_CALC && cnt == 7 && i_valid));

  // FSM
  always @(*) begin
    state_nxt = state;
    case(state)
      S_IDLE: begin
        if(i_valid) state_nxt = S_CALC;
      end
      S_CALC: begin
        if(cnt == 7 && i_valid)
          state_nxt = S_DONE;
      end
      S_DONE: state_nxt = S_IDLE;
    endcase
  end

  // Counter
  always @(*) begin
    cnt_nxt = cnt;
    if(i_valid) begin
      if(cnt == 7)
        cnt_nxt = 0;
      else
        cnt_nxt = cnt + 1;
    end
  end

  // Calculation
  always @(*) begin
    reg1_nxt = reg1;
    reg2_nxt = reg2;
    if(i_valid) begin
      if(cnt == 0) begin
        reg1_nxt = iot_data;
        reg2_nxt = (i_Max)? 0: {127{1'b1}};
      end
      else if(i_Max) begin
        if(iot_data > reg1) begin
          reg2_nxt = reg1;
          reg1_nxt = iot_data;
        end else if(iot_data > reg2) begin
          reg2_nxt = iot_data;
        end
      end else begin
        if(iot_data < reg1) begin
          reg2_nxt = reg1;
          reg1_nxt = iot_data;
        end else if(iot_data < reg2) begin
          reg2_nxt = iot_data;
        end
      end
    end
  end

  // Sequential logic
  always @(posedge i_clk or posedge i_rst) begin
    if(i_rst) begin
      state <= S_IDLE;
      cnt <= 0;
    end else begin
      state <= state_nxt;
      cnt <= cnt_nxt;
    end
  end


endmodule
