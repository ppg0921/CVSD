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
  localparam S_IDLE = 2'd0;
  localparam S_MINMAX = 2'd1;   // calculation
  localparam S_CRYPT = 2'd2;   // calculation
  localparam S_CRC = 2'd3;   // calculation

  reg [63:0] key_upper, key_upper_nxt;
  reg [2:0] crc_remainder_reg;
  reg [63:0] data_nxt; // Dividend and remainder, biggest, smallest, plaintext
  reg [60:0] data;
  reg [63:0] minmax_upper, minmax_upper_nxt;
  reg [63:0] divisor, divisor_nxt; // Divisor, second biggest, second smallest, key
  reg [127:0] iot_data_out_nxt; // output data
  // reg [127:0] loaded_data, loaded_data_nxt; // loaded data 
  reg [7:0] loaded_data [0:15], loaded_data_nxt;
  reg [1:0] state, state_nxt;
  reg [6:0] cnt_data, cnt_data_nxt;
  reg [3:0] cnt_load, cnt_load_nxt;
  wire crypt_done, crc_done, minmax_done;
  wire [63:0] crypt_plaintext_out, crypt_key_out;
  wire [6:0] crc_remainder_out;
  wire [127:0] minmax_reg1_out, minmax_reg2_out;
  reg total_o_valid;
  reg o_busy_reg, o_busy_nxt, to_module_valid, to_module_valid_nxt;
  wire [127:0] crc_final_out, minmax_final_out;
  wire crc_o_valid, minmax_o_valid, crypt_o_valid;
  wire crypt_enable, crc_enable, minmax_enable;
  reg minmax_gate, key_update;
  wire dd_gate, key_upper_gate;
  reg load_gate [0:15];
  wire [127:0] all_loaded_data;
  // reg minmax_compare, minmax_compare_nxt;

  genvar gi;
  integer i;

  ENCRYPT crypt0 (
    .i_clk(clk),
    .i_rst(rst),
    .plaintext({data, crc_remainder_reg}),
    .key(divisor[63:0]),
    .i_valid(to_module_valid),
    .i_enable(crypt_enable),
    .i_encrypt(fn_sel == FN_ENCRYPT),
    .o_plaintext(crypt_plaintext_out),
    .o_key(crypt_key_out),
    .o_valid(crypt_o_valid)
  );

  CRC crc0 (
    .i_clk(clk),
    .i_rst(rst),
    .i_valid(to_module_valid_nxt),
    .i_remainder(crc_remainder_reg),
    .iot_in(all_loaded_data[7:0]),
    .i_enable(crc_enable),
    // .i_divisor(divisor),
    .o_remainder(crc_remainder_out[2:0]),
    // .o_divisor(crc_divisor_out),
    .o_final_out(crc_remainder_out[6:3]),
    .o_valid(crc_o_valid)
  );

  MinMax minmax0 (
    .i_clk(clk),
    .i_rst(rst),
    .iot_data(all_loaded_data),
    .i_valid(to_module_valid_nxt),
    .i_Max(fn_sel == FN_TOP2MAX),
    .i_enable(minmax_enable),
    // .i_compare(minmax_compare),
    .i_cnt_load(cnt_load),
    .i_data_segment(loaded_data[cnt_load-4'b1]),
    .reg1({minmax_upper, data, crc_remainder_reg}),
    .reg2({key_upper, divisor[63:0]}),
    .o_reg1(minmax_reg1_out),
    .o_reg2(minmax_reg2_out),
    .o_final_out(minmax_final_out),
    .o_valid(minmax_o_valid)
  ); 

  assign busy = o_busy_nxt; //! be careful, not reg
  assign valid = total_o_valid;
  assign iot_out = iot_data_out_nxt;

  assign crypt_enable = (fn_sel == FN_ENCRYPT || fn_sel == FN_DECRYPT);
  assign crc_enable = (fn_sel == FN_CRC_GEN);
  assign minmax_enable = (fn_sel == FN_TOP2MAX || fn_sel == FN_LAST2MIN);

  assign dd_gate = (crypt_enable || (minmax_gate));
  assign key_upper_gate = ((key_update)||(minmax_gate));

  assign all_loaded_data = {loaded_data[15], loaded_data[14], loaded_data[13], loaded_data[12], loaded_data[11], loaded_data[10], loaded_data[9], loaded_data[8], loaded_data[7], loaded_data[6], loaded_data[5], loaded_data[4], loaded_data[3], loaded_data[2], loaded_data[1], loaded_data[0]};




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
      // S_LOAD: begin
      //   if(in_en)
      //     cnt_load_nxt = cnt_load + 1;
      //   if(cnt_load == 15) begin
      //     cnt_data_nxt = cnt_data + 1;
      //   end
      // end
      S_MINMAX, S_CRC: begin
        o_busy_nxt = 0;
        if(in_en)
          cnt_load_nxt = cnt_load + 1;
        if(cnt_load == 15) begin
          cnt_data_nxt = cnt_data + 1;
          // if(cnt_data[2:0] == 3'd6)
          //   o_busy_nxt = 1;
        end
      end
      S_CRYPT: begin
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
    minmax_gate = 0;
    key_update = 0;
    // minmax_compare_nxt = 0;
    case(state)
      S_CRYPT: begin
        total_o_valid = crypt_o_valid;
        iot_data_out_nxt = {key_upper, crypt_plaintext_out};
        if(crypt_o_valid || (cnt_load == 15 && cnt_data == 0)) begin
          to_module_valid_nxt = 1;
          key_update = 1;
        end
          
        // to_module_valid = (cnt_load == 0 && cnt_data[2:0] != 0);
      end
      S_CRC: begin
        total_o_valid = crc_o_valid;
        iot_data_out_nxt = {{124'b0}, crc_remainder_out[6:3]};
        if(!(cnt_load == 0 && cnt_data == 0 && cnt_load_nxt != 1))
          to_module_valid_nxt = 1;
      
        // to_module_valid_nxt = (cnt_load == 0 && cnt_data != 0 && in_en);
      end
      S_MINMAX: begin
        total_o_valid = minmax_o_valid;
        iot_data_out_nxt = minmax_final_out;
        to_module_valid_nxt = (cnt_load == 0 && cnt_data != 0);
        minmax_gate = to_module_valid_nxt;
        // minmax_compare_nxt = in_en;
      end
    endcase
  end

  // Load data
  always @(*) begin
    data_nxt = {data, crc_remainder_reg};
    divisor_nxt = divisor;
    loaded_data_nxt = loaded_data[0];
    minmax_upper_nxt = minmax_upper;
    key_upper_nxt = key_upper;
    for(i=0; i<16; i=i+1) begin
      load_gate[i] = 0;
    end
    case(state)
      S_MINMAX: begin
        if(in_en)
          loaded_data_nxt = iot_in;
        load_gate[cnt_load] = in_en;
        {minmax_upper_nxt, data_nxt[63:0]} = minmax_reg1_out;
        // data_nxt = minmax_reg1_out;
        // divisor_nxt = minmax_reg2_out;
        {key_upper_nxt, divisor_nxt} = minmax_reg2_out;
      end
      S_CRYPT: begin
        if(in_en) begin
          loaded_data_nxt = iot_in; 
          // data_nxt = {{19'b0}, crypt_text_intermediate_out, crypt_plaintext_out};
          // divisor_nxt = {{3'b0}, divisor[127:64], crypt_key_out};
        end
        load_gate[cnt_load] = in_en;
        if ((cnt_load == 15 && cnt_data == 0)) begin
          // divisor_nxt[63:0] = {loaded_data_nxt, all_loaded_data[120:64]};
          // key_upper_nxt = {loaded_data_nxt, all_loaded_data[120:64]};
          data_nxt[63:0] = {all_loaded_data[63:0]};
          divisor_nxt[63:0] = {loaded_data_nxt, all_loaded_data[119:64]};
          key_upper_nxt = {loaded_data_nxt, all_loaded_data[119:64]};
        end else if(crypt_o_valid) begin
          data_nxt[63:0] = {all_loaded_data[63:0]};    // plaintext
          
          divisor_nxt[63:0] = {all_loaded_data[127:64]};
          key_upper_nxt = {all_loaded_data[127:64]};
        end else begin
          data_nxt[63:0] = {crypt_plaintext_out};
          // divisor_nxt = {divisor[127:64], crypt_key_out};
          divisor_nxt[63:0] = {crypt_key_out};
        end
        
      end
      S_CRC: begin
        if(in_en) begin
          loaded_data_nxt = iot_in;
        end
        load_gate[0] = in_en;
        data_nxt = {{157'b0}, crc_remainder_out};
      end
    endcase
  end

  // Sequential logic
  always @(posedge clk or posedge rst) begin
    if(rst) begin
      // data <= 0;
      // divisor <= 0;
      // iot_data <= 0;
      state <= S_IDLE;
      cnt_data <= 0;
      cnt_load <= 0;
      o_busy_reg <= 1;
      // loaded_data <= 0;
      // to_module_valid <= 0;
      crc_remainder_reg <= 0;
      // minmax_upper <= 0;
    end else begin
      // data <= data_nxt;
      // divisor <= divisor_nxt;
      // iot_data <= iot_data_nxt;
      state <= state_nxt;
      cnt_data <= cnt_data_nxt;
      cnt_load <= cnt_load_nxt;
      o_busy_reg <= o_busy_nxt;
      // loaded_data <= loaded_data_nxt;
      // to_module_valid <= to_module_valid_nxt;
      crc_remainder_reg <= data_nxt[2:0];
      // minmax_upper <= minmax_upper_nxt;
    end
  end

  always @(posedge clk or posedge rst) begin
    if(rst) begin
      minmax_upper <= 0;
      // minmax_compare <= 0;
    end else if (minmax_gate) begin
      minmax_upper <= minmax_upper_nxt;
      // minmax_compare <= minmax_compare_nxt;
    end
  end

  // always @(posedge clk or posedge rst) begin
  //   if(rst) begin
  //     loaded_data <= 0;
  //   end else if (in_en) begin
  //     loaded_data <= loaded_data_nxt;
  //   end
  // end

  always @(posedge clk or posedge rst) begin
    if(rst) begin
      divisor <= 0;
      data <= 0;
    end else if (dd_gate) begin
      divisor <= divisor_nxt;
      data <= data_nxt[63:3];
    end
  end

  always @(posedge clk or posedge rst) begin
    if(rst) begin
      key_upper <= 0;
    end else if (key_upper_gate) begin
      key_upper <= key_upper_nxt;
    end
  end

  always @(posedge clk or posedge rst) begin
    if(rst) begin
      to_module_valid <= 0;
    end else if (crypt_enable) begin
      to_module_valid <= to_module_valid_nxt;
    end
  end

  generate
    for(gi = 0; gi < 16; gi = gi + 1) begin: loadgenerate
      always @(posedge clk or posedge rst) begin
        if(rst) begin
          loaded_data[gi] <= 0;
        end else if (load_gate[gi]) begin
          loaded_data[gi] <= loaded_data_nxt;
        end
      end
    end
  endgenerate
  

  // always @(posedge clk or posedge rst) begin
  //   if(rst) begin
  //     crc_remainder_reg <= 0;
  //   end else begin
  //     crc_remainder_reg <= data_nxt[2:0];
  //   end
  // end

endmodule

module ENCRYPT(
  input i_clk,
  input i_rst,
  input [63:0] plaintext,
  input [63:0] key,
  input i_valid,
  input i_encrypt,    // 1: encrypt, 0: decrypt
  input i_enable,
  output [63:0] o_plaintext,
  output [63:0] o_key,
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
  localparam [5:0] PC1 [55:0] = '{6'd7,6'd15,6'd23,6'd31,6'd39,6'd47,6'd55,6'd63,6'd6,6'd14,6'd22,6'd30,6'd38,6'd46,6'd54,6'd62,6'd5,6'd13,6'd21,6'd29,6'd37,6'd45,6'd53,6'd61,6'd4,6'd12,6'd20,6'd28,6'd1,6'd9,6'd17,6'd25,6'd33,6'd41,6'd49,6'd57,6'd2,6'd10,6'd18,6'd26,6'd34,6'd42,6'd50,6'd58,6'd3,6'd11,6'd19,6'd27,6'd35,6'd43,6'd51,6'd59,6'd36,6'd44,6'd52,6'd60};
  localparam [5:0] PC2 [47:0] = '{6'd42, 6'd39, 6'd45, 6'd32, 6'd55, 6'd51, 6'd53, 6'd28, 6'd41, 6'd50, 6'd35, 6'd46, 6'd33, 6'd37, 6'd44, 6'd52, 6'd30, 6'd48, 6'd40, 6'd49, 6'd29, 6'd36, 6'd43, 6'd54, 6'd15, 6'd4, 6'd25, 6'd19, 6'd9, 6'd1, 6'd26, 6'd16, 6'd5, 6'd11, 6'd23, 6'd8, 6'd12, 6'd7, 6'd17, 6'd0, 6'd22, 6'd3, 6'd10, 6'd14, 6'd6, 6'd20, 6'd27, 6'd24};
  localparam [3:0] S1 [0:3][0:15] = '{'{4'd14, 4'd4, 4'd13, 4'd1, 4'd2, 4'd15, 4'd11, 4'd8, 4'd3, 4'd10, 4'd6, 4'd12, 4'd5, 4'd9, 4'd0, 4'd7},
  '{4'd0, 4'd15, 4'd7, 4'd4, 4'd14, 4'd2, 4'd13, 4'd1, 4'd10, 4'd6, 4'd12, 4'd11, 4'd9, 4'd5, 4'd3, 4'd8},
  '{4'd4, 4'd1, 4'd14, 4'd8, 4'd13, 4'd6, 4'd2, 4'd11, 4'd15, 4'd12, 4'd9, 4'd7, 4'd3, 4'd10, 4'd5, 4'd0},
  '{4'd15, 4'd12, 4'd8, 4'd2, 4'd4, 4'd9, 4'd1, 4'd7, 4'd5, 4'd11, 4'd3, 4'd14, 4'd10, 4'd0, 4'd6, 4'd13}
  };
  localparam [3:0] S2 [0:3][0:15] = '{'{4'd15, 4'd1, 4'd8, 4'd14, 4'd6, 4'd11, 4'd3, 4'd4, 4'd9, 4'd7, 4'd2, 4'd13, 4'd12, 4'd0, 4'd5, 4'd10},
  '{4'd3, 4'd13, 4'd4, 4'd7, 4'd15, 4'd2, 4'd8, 4'd14, 4'd12, 4'd0, 4'd1, 4'd10, 4'd6, 4'd9, 4'd11, 4'd5},
  '{4'd0, 4'd14, 4'd7, 4'd11, 4'd10, 4'd4, 4'd13, 4'd1, 4'd5, 4'd8, 4'd12, 4'd6, 4'd9, 4'd3, 4'd2, 4'd15},
  '{4'd13, 4'd8, 4'd10, 4'd1, 4'd3, 4'd15, 4'd4, 4'd2, 4'd11, 4'd6, 4'd7, 4'd12, 4'd0, 4'd5, 4'd14, 4'd9}
  };
  localparam [3:0] S3 [0:3][0:15] = '{'{4'd10, 4'd0, 4'd9, 4'd14, 4'd6, 4'd3, 4'd15, 4'd5, 4'd1, 4'd13, 4'd12, 4'd7, 4'd11, 4'd4, 4'd2, 4'd8},
  '{4'd13, 4'd7, 4'd0, 4'd9, 4'd3, 4'd4, 4'd6, 4'd10, 4'd2, 4'd8, 4'd5, 4'd14, 4'd12, 4'd11, 4'd15, 4'd1},
  '{4'd13, 4'd6, 4'd4, 4'd9, 4'd8, 4'd15, 4'd3, 4'd0, 4'd11, 4'd1, 4'd2, 4'd12, 4'd5, 4'd10, 4'd14, 4'd7},
  '{4'd1, 4'd10, 4'd13, 4'd0, 4'd6, 4'd9, 4'd8, 4'd7, 4'd4, 4'd15, 4'd14, 4'd3, 4'd11, 4'd5, 4'd2, 4'd12}
  };
  localparam [3:0] S4 [0:3][0:15] = '{'{4'd7, 4'd13, 4'd14, 4'd3, 4'd0, 4'd6, 4'd9, 4'd10, 4'd1, 4'd2, 4'd8, 4'd5, 4'd11, 4'd12, 4'd4, 4'd15},
  '{4'd13, 4'd8, 4'd11, 4'd5, 4'd6, 4'd15, 4'd0, 4'd3, 4'd4, 4'd7, 4'd2, 4'd12, 4'd1, 4'd10, 4'd14, 4'd9},
  '{4'd10, 4'd6, 4'd9, 4'd0, 4'd12, 4'd11, 4'd7, 4'd13, 4'd15, 4'd1, 4'd3, 4'd14, 4'd5, 4'd2, 4'd8, 4'd4},
  '{4'd3, 4'd15, 4'd0, 4'd6, 4'd10, 4'd1, 4'd13, 4'd8, 4'd9, 4'd4, 4'd5, 4'd11, 4'd12, 4'd7, 4'd2, 4'd14}
  };
  localparam [3:0] S5 [0:3][0:15] = '{'{4'd2, 4'd12, 4'd4, 4'd1, 4'd7, 4'd10, 4'd11, 4'd6, 4'd8, 4'd5, 4'd3, 4'd15, 4'd13, 4'd0, 4'd14, 4'd9},
  '{4'd14, 4'd11, 4'd2, 4'd12, 4'd4, 4'd7, 4'd13, 4'd1, 4'd5, 4'd0, 4'd15, 4'd10, 4'd3, 4'd9, 4'd8, 4'd6},
  '{4'd4, 4'd2, 4'd1, 4'd11, 4'd10, 4'd13, 4'd7, 4'd8, 4'd15, 4'd9, 4'd12, 4'd5, 4'd6, 4'd3, 4'd0, 4'd14},
  '{4'd11, 4'd8, 4'd12, 4'd7, 4'd1, 4'd14, 4'd2, 4'd13, 4'd6, 4'd15, 4'd0, 4'd9, 4'd10, 4'd4, 4'd5, 4'd3}
  };
  localparam [3:0] S6 [0:3][0:15] = '{'{4'd12, 4'd1, 4'd10, 4'd15, 4'd9, 4'd2, 4'd6, 4'd8, 4'd0, 4'd13, 4'd3, 4'd4, 4'd14, 4'd7, 4'd5, 4'd11},
  '{4'd10, 4'd15, 4'd4, 4'd2, 4'd7, 4'd12, 4'd9, 4'd5, 4'd6, 4'd1, 4'd13, 4'd14, 4'd0, 4'd11, 4'd3, 4'd8},
  '{4'd9, 4'd14, 4'd15, 4'd5, 4'd2, 4'd8, 4'd12, 4'd3, 4'd7, 4'd0, 4'd4, 4'd10, 4'd1, 4'd13, 4'd11, 4'd6},
  '{4'd4, 4'd3, 4'd2, 4'd12, 4'd9, 4'd5, 4'd15, 4'd10, 4'd11, 4'd14, 4'd1, 4'd7, 4'd6, 4'd0, 4'd8, 4'd13}
  };
  localparam [3:0] S7 [0:3][0:15] = '{'{4'd4, 4'd11, 4'd2, 4'd14, 4'd15, 4'd0, 4'd8, 4'd13, 4'd3, 4'd12, 4'd9, 4'd7, 4'd5, 4'd10, 4'd6, 4'd1},
  '{4'd13, 4'd0, 4'd11, 4'd7, 4'd4, 4'd9, 4'd1, 4'd10, 4'd14, 4'd3, 4'd5, 4'd12, 4'd2, 4'd15, 4'd8, 4'd6},
  '{4'd1, 4'd4, 4'd11, 4'd13, 4'd12, 4'd3, 4'd7, 4'd14, 4'd10, 4'd15, 4'd6, 4'd8, 4'd0, 4'd5, 4'd9, 4'd2},
  '{4'd6, 4'd11, 4'd13, 4'd8, 4'd1, 4'd4, 4'd10, 4'd7, 4'd9, 4'd5, 4'd0, 4'd15, 4'd14, 4'd2, 4'd3, 4'd12}
  };

  localparam [3:0] S8 [0:3][0:15] = '{'{4'd13, 4'd2, 4'd8, 4'd4, 4'd6, 4'd15, 4'd11, 4'd1, 4'd10, 4'd9, 4'd3, 4'd14, 4'd5, 4'd0, 4'd12, 4'd7},
  '{4'd1, 4'd15, 4'd13, 4'd8, 4'd10, 4'd3, 4'd7, 4'd4, 4'd12, 4'd5, 4'd6, 4'd11, 4'd0, 4'd14, 4'd9, 4'd2},
  '{4'd7, 4'd11, 4'd4, 4'd1, 4'd9, 4'd12, 4'd14, 4'd2, 4'd0, 4'd6, 4'd10, 4'd13, 4'd15, 4'd3, 4'd5, 4'd8},
  '{4'd2, 4'd1, 4'd14, 4'd7, 4'd4, 4'd10, 4'd8, 4'd13, 4'd15, 4'd12, 4'd9, 4'd0, 4'd3, 4'd5, 4'd6, 4'd11}
  };
  localparam [4:0] P [31:0] =  '{5'd16,5'd25,5'd12,5'd11,5'd3,5'd20,5'd4,5'd15,5'd31,5'd17,5'd9,5'd6,5'd27,5'd14,5'd1,5'd22,5'd30,5'd24,5'd8,5'd18,5'd0,5'd5,5'd29,5'd23,5'd13,5'd19,5'd2,5'd26,5'd10,5'd21,5'd28,5'd7};
  localparam [5:0] Expansion [47:0] = '{6'd0,6'd31,6'd30,6'd29,6'd28,6'd27,6'd28,6'd27,6'd26,6'd25,6'd24,6'd23,6'd24,6'd23,6'd22,6'd21,6'd20,6'd19,6'd20,6'd19,6'd18,6'd17,6'd16,6'd15,6'd16,6'd15,6'd14,6'd13,6'd12,6'd11,6'd12,6'd11,6'd10,6'd9,6'd8,6'd7,6'd8,6'd7,6'd6,6'd5,6'd4,6'd3,6'd4,6'd3,6'd2,6'd1,6'd0,6'd31};
  localparam [5:0] Final_permutation [63:0] = '{6'd24,6'd56,6'd16,6'd48,6'd8,6'd40,6'd0,6'd32,6'd25,6'd57,6'd17,6'd49,6'd9,6'd41,6'd1,6'd33,6'd26,6'd58,6'd18,6'd50,6'd10,6'd42,6'd2,6'd34,6'd27,6'd59,6'd19,6'd51,6'd11,6'd43,6'd3,6'd35,6'd28,6'd60,6'd20,6'd52,6'd12,6'd44,6'd4,6'd36,6'd29,6'd61,6'd21,6'd53,6'd13,6'd45,6'd5,6'd37,6'd30,6'd62,6'd22,6'd54,6'd14,6'd46,6'd6,6'd38,6'd31,6'd63,6'd23,6'd55,6'd15,6'd47,6'd7,6'd39};
  reg [3:0] cnt, cnt_nxt;
  reg [2:0] state, state_nxt;
  reg [63:0] plaintext_nxt, key_nxt, key_permuted;
  reg [47:0] key_PC2;
  reg [47:0] text_expended;
  reg [47:0] key_now, text_tmp;
  reg [56:0] key_tmp;
  wire [31:0] text_intermediate_nxt;
  reg [31:0]  F_out, R_nxt, L_nxt;
  wire [31:0] R_now, L_now;
  wire [1:0] row [7:0];
  wire [3:0] col [7:0];
  wire shift_one_bit;
  // wire [63:0] plaintext, key;
  integer i;

  assign shift_one_bit = (cnt == 6 || cnt == 13 || state == S_GEN_K1);
  // assign o_text_intermediate = text_intermediate_nxt;
  assign o_key = key_nxt;
  assign o_plaintext = plaintext_nxt;
  assign o_valid = (state == S_FIN_PERMUTATION);
  assign R_now = plaintext[31:0];
  assign L_now = plaintext[63:32];
  // assign plaintext = plaintext;
  // assign key = key;

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
      S_FIN_PERMUTATION: state_nxt = S_IDLE; //! need modification
      // S_DONE: state_nxt = S_IDLE; 
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
    // for(i = 0; i < 64; i = i + 1) begin
    //   key_tmp[i] = 0;
    // end
    // key_tmp[63:48] = 0;
    key_tmp = 0;
    key_PC2 = 0;
    key_nxt = key;
    // key_tmp = 0;
    key_permuted = 0;

    for(i=0; i<48; i=i+1)
      text_expended[i] = 0;
    // text_tmp = key_tmp[47:0] ^ text_expended;
    case(state)
      S_PC1_ROTATE: begin
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
        for(i=0; i<48; i=i+1)
          text_expended[i] = R_now[Expansion[i]];
        for(i = 0; i < 48; i = i + 1) begin
          key_PC2[i] = key[PC2[i]];
        end
        
      end
    endcase
    text_tmp = key_PC2[47:0] ^ text_expended;
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
      // S_DONE: begin
      //   plaintext_nxt = plaintext;
      // end
    endcase
    
  end

  // Sequential logic
  always @(posedge i_clk or posedge i_rst) begin
    if(i_rst) begin
      state <= S_IDLE;
      cnt <= 0;
    end else if(i_enable) begin
      state <= state_nxt;
      cnt <= cnt_nxt;
    end
  end
endmodule

module CRC(
  input i_clk,
  input i_rst,
  input i_valid,
  input [2:0] i_remainder,
  input [7:0] iot_in,
  input i_enable,

  // input [130:0] i_divisor,
  output [2:0] o_remainder,
  // output [130:0] o_divisor,
  output [3:0] o_final_out,
  output o_valid
);
  // state
  localparam S_IDLE = 2'd0;
  localparam S_CALC_A = 2'd1;
  localparam S_CALC_B = 2'd2;
  localparam S_CALC_C = 2'd3;

  

  reg [1:0] state, state_nxt;
  reg [2:0] o_remainder_nxt;
  // reg [2:0] crc, crc_nxt;
  // core can handle crc on its own
  reg [3:0] cnt, cnt_nxt;
  reg o_valid_reg, o_valid_nxt;

  assign o_remainder = o_remainder_nxt;
  // assign o_divisor = o_divisor_nxt;
  assign o_final_out = {i_remainder, {1'b0}};
  assign o_valid = o_valid_reg;
  // Counter
  always @(*) begin
    cnt_nxt = 0;
    if(i_valid && state != S_IDLE) begin
      cnt_nxt = cnt + 1;
    end
  end
  // FSM
  always @(*) begin
    state_nxt = state;
    case(state)
      S_IDLE: begin
        if(i_valid) state_nxt = S_CALC_A;
      end
      S_CALC_A: begin
        if(cnt != 15) state_nxt = S_CALC_B;
      end
      S_CALC_B: state_nxt = S_CALC_C;
      S_CALC_C: state_nxt = S_CALC_A;
    endcase
  end

  function [2:0] calcA;
    input [7:0] i_data;
    input [2:0] last_remainder;
    reg [2:0] eleven, one, ten;
    begin
      eleven = (i_data[0] ^ i_data[3] ^ i_data[6])? {3'b011}: {3'b000};
      one = (i_data[1] ^ i_data[4] ^ i_data[7])? {3'b001}: {3'b000};
      ten = (i_data[2] ^ i_data[5])? {3'b010}: {3'b000};
      calcA = eleven ^ one ^ ten ^ last_remainder;
    end
  endfunction

  function [2:0] calcB;
    input [7:0] i_data;
    input [2:0] last_remainder;
    reg [2:0] eleven, one, ten;
    begin
      ten = (i_data[0] ^ i_data[3] ^ i_data[6])? {3'b010}: {3'b000};
      eleven = (i_data[1] ^ i_data[4] ^ i_data[7])? {3'b011}: {3'b000};
      one = (i_data[2] ^ i_data[5])? {3'b001}: {3'b000};
      calcB = eleven ^ one ^ ten ^ last_remainder;
    end
  endfunction

  function [2:0] calcC;
    input [7:0] i_data;
    input [2:0] last_remainder;
    reg [2:0] eleven, one, ten;
    begin
      one = (i_data[0] ^ i_data[3] ^ i_data[6])? {3'b001}: {3'b000};
      ten = (i_data[1] ^ i_data[4] ^ i_data[7])? {3'b010}: {3'b000};
      eleven = (i_data[2] ^ i_data[5])? {3'b011}: {3'b000};
      calcC = eleven ^ one ^ ten ^ last_remainder;
    end
  endfunction


  // calculation
  always @(*) begin
    o_remainder_nxt = 0;
    case(state)
      // S_IDLE: begin
      //   if(i_valid) o_remainder_nxt = calcA(iot_in, {3'b000});
      // end
      S_CALC_A: begin
        if(cnt == 0) 
          o_remainder_nxt = calcA(iot_in, {3'b000});
        else
          o_remainder_nxt = calcA(iot_in, i_remainder);
      end
      S_CALC_B: o_remainder_nxt = calcB(iot_in, i_remainder);
      S_CALC_C: o_remainder_nxt = calcC(iot_in, i_remainder);
    endcase
    o_valid_nxt = (cnt == 15);
  end

  // Sequential logic
  always @(posedge i_clk or posedge i_rst) begin
    if(i_rst) begin
      state <= S_IDLE;
      cnt <= 0;
      o_valid_reg <= 0;
    end else if(i_enable) begin
      state <= state_nxt;
      cnt <= cnt_nxt;
      o_valid_reg <= o_valid_nxt;
    end
  end
endmodule

module MinMax(
  input i_clk,
  input i_rst,
  input [127:0] iot_data,
  input i_valid,
  input i_Max,   // 1: top2max, 0: last2min
  input i_enable,
  input [127:0] reg1,
  input [127:0] reg2,
  input [7:0] i_data_segment,
  input [3:0] i_cnt_load,
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
  reg replace [0:1], replace_nxt[0:1]; 
  reg [7:0] selected_data [0:1];
  wire [3:0] cnt_load_now;

  integer i;

  assign o_reg1 = reg1_nxt;
  assign o_reg2 = reg2_nxt;
  assign o_final_out = (cnt == 0)? reg1 : reg2;
  assign o_valid = (state == S_DONE);
  assign cnt_load_now = (i_enable)? i_cnt_load - 1 : 0;

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
      S_DONE: begin
        if(cnt == 1)
          state_nxt = S_IDLE;
      end
    endcase
  end

  // Counter
  always @(*) begin
    cnt_nxt = cnt;
    if(state == S_DONE) begin
      cnt_nxt = cnt + 1;
      if(cnt == 1)
        cnt_nxt = 0;
    end else if(i_valid) begin
      if(cnt == 7)
        cnt_nxt = 0;
      else
        cnt_nxt = cnt + 1;
    end
  end

  always @(*) begin
    selected_data[0] = 0;
    selected_data[1] = 0;
    if(i_enable) begin
      selected_data[0] = reg1[cnt_load_now*8 +: 8];
      selected_data[1] = reg2[cnt_load_now*8 +: 8];
    end
  end

  // Calculation
  always @(*) begin
    for(i=0; i<2; i=i+1)
      replace_nxt[i] = replace[i];
    if(i_enable) begin
      if(i_data_segment > selected_data[0]) replace_nxt[0] = (i_Max);
      else if(i_data_segment < selected_data[0]) replace_nxt[0] = !(i_Max);
      if(i_data_segment > selected_data[1]) replace_nxt[1] = (i_Max);
      else if(i_data_segment < selected_data[1]) replace_nxt[1] = !(i_Max);
    end
    
  end


  always @(*) begin
    reg1_nxt = reg1;
    reg2_nxt = reg2;
    if(i_valid) begin
      if(cnt == 0) begin
        reg1_nxt = iot_data;
        reg2_nxt = (i_Max)? 0: {128{1'b1}};
      end
      else begin
        if(replace_nxt[0]) begin
          reg2_nxt = reg1;
          reg1_nxt = iot_data;
        end else if(replace_nxt[1]) begin
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
      for(i=0; i<2; i=i+1)
        replace[i] <= 0;
    end else if(i_enable) begin
      state <= state_nxt;
      cnt <= cnt_nxt;
      for(i=0; i<2; i=i+1)
        replace[i] <= replace_nxt[i];
    end
  end


endmodule
