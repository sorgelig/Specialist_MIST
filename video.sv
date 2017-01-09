//
// Specialist display implementation
// 
// Copyright (c) 2016 Sorgelig
//
// 
// This source file is free software: you can redistribute it and/or modify 
// it under the terms of the GNU General Public License as published 
// by the Free Software Foundation, either version 3 of the License, or 
// (at your option) any later version. 
// 
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of 
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the 
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License 
// along with this program.  If not, see <http://www.gnu.org/licenses/>. 
//


`timescale 1ns / 1ps

module video
(
	// Clocks
	input         clk_sys,
	input         ce_pix_p, // Video clock enable (16 MHz)
	input         ce_pix_n, // Video clock enable (16 MHz)

	// OSD data
	input         SPI_SCK,
	input         SPI_SS3,
	input         SPI_DI,

	// Video outputs
	output  [5:0] VGA_R,
	output  [5:0] VGA_G,
	output  [5:0] VGA_B,
	output        VGA_VS,
	output        VGA_HS,
	
	// TV/VGA
	input         scandoubler_disable,
	input         ypbpr,

	// CPU bus
	input	 [15:0] addr,
	input	  [7:0] din,
	input			  we,
	
	// Misc signals
	input	  [7:0] color,
	input	        mx,
	input         bw_mode
);

reg [8:0] hc;
reg [8:0] vc;
reg       HSync;
reg       VSync;
reg [7:0] bmp;
reg [7:0] rgb;
reg       blank;

always @(posedge clk_sys) begin
	if(ce_pix_p) begin
		if(hc == 511) begin 
			hc <=0;
			if (vc == 311) begin 
				vc <= 9'd0;
			end else begin
				vc <= vc + 1'd1;

				if(vc == 271) VSync  <= 1;
				if(vc == 281) VSync  <= 0;
			end
		end else hc <= hc + 1'd1;

		if(hc == 415) HSync  <= 1;
		if(hc == 463) HSync  <= 0;
	end
	if(ce_pix_n) begin
		bmp <= {bmp[6:0], 1'b0};
		if(!hc[2:0] & ~(hc[8] & hc[7]) & ~vc[8]) {rgb, bmp} <= vram_o;
		blank <= (hc[8] & hc[7]) | vc[8];
	end
end

wire [15:0] vram_o;
dpram vram
(
	.clock(clk_sys),
	.wraddress(addr[13:0]-14'h1000),
	.data({color,din}),
	.wren(we & addr[15] & ~addr[14] & (addr[13] | addr[12])),
	.rdaddress({hc[8:3], vc[7:0]}),
	.q(vram_o)
);

wire [5:0] R_in,  G_in,  B_in;
wire [5:0] R_out, G_out, B_out;

always_comb begin
	casex({blank, bw_mode, mx})
		3'b1XX: {R_in,G_in,B_in} = {18{1'b0}};
		2'b01X: {R_in,G_in,B_in} = {18{bmp[7]}};
		2'b000: begin
			R_in = {6{bmp[7] & rgb[6]}};
			G_in = {6{bmp[7] & rgb[5]}};
			B_in = {6{bmp[7] & rgb[4]}};
		end
		2'b001: begin
			R_in = bmp[7] ? {{3{rgb[6],rgb[7]}}} : {{3{rgb[2],rgb[3]}}};
			G_in = bmp[7] ? {{3{rgb[5],rgb[7]}}} : {{3{rgb[1],rgb[3]}}};
			B_in = bmp[7] ? {{3{rgb[4],rgb[7]}}} : {{3{rgb[0],rgb[3]}}};
		end
	endcase
end

osd #(10'd0, 10'd0, 3'd4) osd
(
	.*,
	.ce_pix(ce_pix_p),
	.R_in(R_in),
	.G_in(G_in),
	.B_in(B_in)
);

wire hs_out, vs_out;
wire [5:0] r_out;
wire [5:0] g_out;
wire [5:0] b_out;

scandoubler scandoubler
(
	.*,
	.ce_x2(ce_pix_p | ce_pix_n),
	.ce_x1(ce_pix_p),
	.scanlines(2'b00),
	.hs_in(HSync),
	.vs_in(VSync),
	.r_in(R_out),
	.g_in(G_out),
	.b_in(B_out)
);

video_mixer video_mixer
(
	.*,
	.ypbpr_full(1),

	.r_i({R_out, R_out[5:4]}),
	.g_i({G_out, G_out[5:4]}),
	.b_i({B_out, B_out[5:4]}),
	.hsync_i(HSync),
	.vsync_i(VSync),

	.r_p({r_out, r_out[5:4]}),
	.g_p({g_out, g_out[5:4]}),
	.b_p({b_out, b_out[5:4]}),
	.hsync_p(hs_out),
	.vsync_p(vs_out)
);


endmodule
