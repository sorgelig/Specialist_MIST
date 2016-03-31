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
	input         clk_pix, // Video clock (16 MHz)
	input         clk_ram, // Video ram clock (>50 MHz)

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

	// CPU bus
	input	 [15:0] addr,
	input	  [7:0] din,
	input			  we,
	
	// Misc signals
	input	  [2:0] color,
	input         bw_mode
);

reg clk_8;
always @(posedge clk_pix) clk_8 <= !clk_8;

reg [8:0] hc;
reg [8:0] vc;
reg HSync, VSync;

always @(posedge clk_8) begin
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

wire [10:0] vram_o;
dpram vram
(
	.clock(clk_ram),
	.wraddress(addr[13:0]-14'h1000),
	.data({color,din}),
	.wren(we & addr[15] & ~addr[14] & (addr[13] | addr[12])),
	.rdaddress({hc[8:3], vc[7:0]}),
	.q(vram_o)
);

reg [7:0] bmp;
reg [2:0] rgb;

always @(negedge clk_8) begin
	bmp <= {bmp[6:0], 1'b0};
	if(!hc[2:0] & ~(hc[8] & hc[7]) & ~vc[8]) {rgb, bmp} <= vram_o;
end

wire [5:0] R_out;
wire [5:0] G_out;
wire [5:0] B_out;

osd #(10'd0, 10'd0, 3'd4) osd
(
	.*,
	.clk_pix(clk_8),
	.R_in({6{bmp[7] & (bw_mode | rgb[1])}}),
	.G_in({6{bmp[7] & (bw_mode | rgb[2])}}),
	.B_in({6{bmp[7] & (bw_mode | rgb[0])}})
);

wire hs_out, vs_out;
wire [5:0] r_out;
wire [5:0] g_out;
wire [5:0] b_out;

scandoubler scandoubler(
	.*,
	.clk_x2(clk_pix),
	.scanlines(2'b00),
	    
	.hs_in(HSync),
	.vs_in(VSync),
	.r_in(R_out),
	.g_in(G_out),
	.b_in(B_out)
);

assign {VGA_HS,           VGA_VS,  VGA_R, VGA_G, VGA_B} = scandoubler_disable ? 
       {~(HSync ^ VSync), 1'b1,    R_out, G_out, B_out}: 
       {~hs_out,          ~vs_out, r_out, g_out, b_out};

endmodule
