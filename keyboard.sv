// ====================================================================
//                Radio-86RK FPGA REPLICA
//
//            Copyright (C) 2011 Dmitry Tselikov
//
// This core is distributed under modified BSD license. 
// For complete licensing information see LICENSE.TXT.
// -------------------------------------------------------------------- 
//
// An open implementation of Radio-86RK keyboard
//
// Author: Dmitry Tselikov   http://bashkiria-2m.narod.ru/
// 
//

module keyboard
(
	input         clk,
	input         reset,
	input         ps2_clk,
	input         ps2_dat,

	input   [5:0] row_in,
	output [11:0] col_out,
	input  [11:0] col_in,
	output  [5:0] row_out,
	output        nr,

	output reg    reset_key
);

assign nr = ~knr;
reg  knr;

reg [11:0] col_state[5:0];
assign col_out =~((col_state[0] & {12{~row_in[0]}})|
						(col_state[1] & {12{~row_in[1]}})|
						(col_state[2] & {12{~row_in[2]}})|
						(col_state[3] & {12{~row_in[3]}})|
						(col_state[4] & {12{~row_in[4]}})|
						(col_state[5] & {12{~row_in[5]}}));


reg [5:0] row_state[11:0];
assign row_out =~((row_state[0]  & {6{~col_in[0]}})|
						(row_state[1]  & {6{~col_in[1]}})|
						(row_state[2]  & {6{~col_in[2]}})|
						(row_state[3]  & {6{~col_in[3]}})|
						(row_state[4]  & {6{~col_in[4]}})|
						(row_state[5]  & {6{~col_in[5]}})|
						(row_state[6]  & {6{~col_in[6]}})|
						(row_state[7]  & {6{~col_in[7]}})|
						(row_state[8]  & {6{~col_in[8]}})|
						(row_state[9]  & {6{~col_in[9]}})|
						(row_state[10] & {6{~col_in[10]}})|
						(row_state[11] & {6{~col_in[11]}}));

reg  [2:0] c;
reg  [3:0] r;
reg        unpress;
reg  [3:0] prev_clk;
reg [11:0] shift_reg;

wire[11:0] kdata = {ps2_dat,shift_reg[11:1]};
wire [7:0] kcode = kdata[9:2];

/*
   5    4   3   2   1   0
0  NF   -=  :*  .>  ЗБ  ВК    
1  TF   0   ХH  Э\  /?  ПС
2  SF   9)  ЗZ  ЖV  ,<  ->
3  EDIT 8(  Щ]  ДD  Ю@  ПВ
4  F8   7,  Ш[  ЛL  БB  <-
5  F7   6&  ГG  ОO  ЬX  Sp
6  F6   5%  НN  РR  ТT  АР2
7  F5   4$  ЕE  ПP  ИI  ТАБ
8  F4   3#  КK  АA  МM  DOWN
9  F3   2"  УU  ВW  СS  UP
A  F2   1!  ЦC  ЫY  Ч^  HOME
B  F1   ;+  ЙJ  ФF  ЯQ  Р/Л
C                       NR
*/

always @(*) begin
	casex({knr,kcode})

	9'hX09: {c,r} = 7'h50; // F10 - NF
	9'hX71: {c,r} = 7'h51; // DELETE - TF
	9'hX70: {c,r} = 7'h52; // INSERT - SF
	9'hX01: {c,r} = 7'h53; // F9 - EDIT
	9'hX0A: {c,r} = 7'h54; // F8
	9'hX83: {c,r} = 7'h55; // F7
	9'hX0B: {c,r} = 7'h56; // F6
	9'hX03: {c,r} = 7'h57; // F5
	9'hX0C: {c,r} = 7'h58; // F4
	9'hX04: {c,r} = 7'h59; // F3
	9'hX06: {c,r} = 7'h5A; // F2
	9'hX05: {c,r} = 7'h5B; // F1

	9'hX4E: {c,r} = 7'h40; // -
	9'h045: {c,r} = 7'h41; // 0
	9'h046: {c,r} = 7'h42; // 9
	9'h03E: {c,r} = 7'h43; // 8
	9'h03D: {c,r} = 7'h44; // 7
	9'h036: {c,r} = 7'h45; // 6
	9'hX2E: {c,r} = 7'h46; // 5
	9'hX25: {c,r} = 7'h47; // 4
	9'hX26: {c,r} = 7'h48; // 3
	9'hX1E: {c,r} = 7'h49; // 2
	9'hX16: {c,r} = 7'h4A; // 1
	9'hX55: {c,r} = 7'h4B; // =

	9'h145: {c,r} = 7'h42; // 0
	9'h146: {c,r} = 7'h43; // 9
	9'h13E: {c,r} = 7'h30; // 8
	9'h13D: {c,r} = 7'h45; // 7
	9'h136: {c,r} = 7'h44; // 6
	
	9'hX4C: {c,r} = 7'h30; // ;
	9'hX33: {c,r} = 7'h31; // H
	9'hX1A: {c,r} = 7'h32; // Z
	9'hX5B: {c,r} = 7'h33; // ]
	9'hX54: {c,r} = 7'h34; // [
	9'hX34: {c,r} = 7'h35; // G
	9'hX31: {c,r} = 7'h36; // N
	9'hX24: {c,r} = 7'h37; // E
	9'hX42: {c,r} = 7'h38; // K
	9'hX3C: {c,r} = 7'h39; // U
	9'hX21: {c,r} = 7'h3A; // C
	9'hX3B: {c,r} = 7'h3B; // J

	9'hX49: {c,r} = 7'h20; // .
	9'hX5D: {c,r} = 7'h21; // \
	9'hX2A: {c,r} = 7'h22; // V
	9'hX23: {c,r} = 7'h23; // D
	9'hX4B: {c,r} = 7'h24; // L
	9'hX44: {c,r} = 7'h25; // O
	9'hX2D: {c,r} = 7'h26; // R
	9'hX4D: {c,r} = 7'h27; // P
	9'hX1C: {c,r} = 7'h28; // A
	9'hX1D: {c,r} = 7'h29; // W
	9'hX35: {c,r} = 7'h2A; // Y
	9'hX2B: {c,r} = 7'h2B; // F

	9'hX66: {c,r} = 7'h10; // bksp
	9'hX4A: {c,r} = 7'h11; // /
	9'hX41: {c,r} = 7'h12; // ,
	9'hX52: {c,r} = 7'h13; // '
	9'hX32: {c,r} = 7'h14; // B
	9'hX22: {c,r} = 7'h15; // X
	9'hX2C: {c,r} = 7'h16; // T
	9'hX43: {c,r} = 7'h17; // I
	9'hX3A: {c,r} = 7'h18; // M
	9'hX1B: {c,r} = 7'h19; // S
	9'hX0E: {c,r} = 7'h1A; // `
	9'hX15: {c,r} = 7'h1B; // Q

	9'hX5A: {c,r} = 7'h00; // enter
	9'hX59: {c,r} = 7'h01; // rshift - PS
	9'hX74: {c,r} = 7'h02; // right
	9'hX1F: {c,r} = 7'h03; // LWin - PV
	9'hX27: {c,r} = 7'h03; // RWin - PV
	9'hX6B: {c,r} = 7'h04; // left
	9'hX29: {c,r} = 7'h05; // space
	9'hX76: {c,r} = 7'h06; // esc - AR2
	9'hX0D: {c,r} = 7'h07; // tab
	9'hX72: {c,r} = 7'h08; // down
	9'hX75: {c,r} = 7'h09; // up
	9'hX6C: {c,r} = 7'h0A; // home
	9'hX58: {c,r} = 7'h0B; // caps - RUS/LAT

	9'hX12: {c,r} = 7'h0C; // lshift - NR

	default: {c,r} = 7'h7F;
	endcase
end

reg malt   = 0;
reg mctrl  = 0;
reg mshift = 0;

always @(posedge clk) begin
	reg old_reset;
	
	old_reset <= reset;
	if(!old_reset && reset) begin
		prev_clk <= 0;
		shift_reg <= 12'hFFF;
		unpress <= 0;
		col_state <= '{default:0};
		row_state <= '{default:0};
	end else begin
		prev_clk <= {ps2_clk,prev_clk[3:1]};
		if (prev_clk==4'b1) begin
			if (kdata[11]==1'b1 && ^kdata[10:2]==1'b1 && kdata[1:0]==2'b1) begin
				shift_reg <= 12'hFFF;
				if (kcode==8'h11) malt   <= ~unpress;
				if (kcode==8'h14) mctrl  <= ~unpress;
				if (kcode==8'h12) mshift <= ~unpress;
				if (kcode==8'h59) mshift <= ~unpress;
				if (kcode==8'h78) reset_key <= mctrl & ~unpress;
				if (kcode==8'hF0) unpress <= 1;
				else begin
					unpress <= 0;
					if(r != 4'hF) begin
						if(r == 4'hC) knr <= ~unpress;
						else begin 
							col_state[c][r] <= ~unpress;
							row_state[r][c] <= ~unpress;
						end
					end
				end
			end else begin
				shift_reg <= kdata;
			end
		end
	end
end

endmodule
