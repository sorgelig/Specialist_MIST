// ====================================================================
//                Specialist FPGA REPLICA
//
//            Copyright (C) 2016 Sorgelig
//
// This core is distributed under modified BSD license. 
// For complete licensing information see LICENSE.TXT.
// -------------------------------------------------------------------- 
//
// An open implementation of Specialist home computer
//
// 

module Specialist
(
   input         CLOCK_27,  // Input clock 27 MHz

   output  [5:0] VGA_R,
   output  [5:0] VGA_G,
   output  [5:0] VGA_B,
   output        VGA_HS,
   output        VGA_VS,
	 
   output        LED,

   output        AUDIO_L,
   output        AUDIO_R,

   input         SPI_SCK,
   output        SPI_DO,
   input         SPI_DI,
   input         SPI_SS2,
   input         SPI_SS3,
   input         SPI_SS4,
   input         CONF_DATA0,

   output [12:0] SDRAM_A,
   inout  [15:0] SDRAM_DQ,
   output        SDRAM_DQML,
   output        SDRAM_DQMH,
   output        SDRAM_nWE,
   output        SDRAM_nCAS,
   output        SDRAM_nRAS,
   output        SDRAM_nCS,
   output  [1:0] SDRAM_BA,
   output        SDRAM_CLK,
   output        SDRAM_CKE
);

///////////////////   ARM I/O   //////////////////
wire [7:0] status;
wire [1:0] buttons;
wire scandoubler_disable;
wire ps2_kbd_clk, ps2_kbd_data;

user_io #(.STRLEN(51)) user_io 
(
	.conf_str
	(
	     "SPCLST;RKS;O1,Color,On,Off;O4,Turbo,Off,On;T6,Reset"
	),
	.SPI_SCK(SPI_SCK),
	.CONF_DATA0(CONF_DATA0),
	.SPI_DO(SPI_DO),
	.SPI_DI(SPI_DI),

	.status(status),
	.buttons(buttons),
	.scandoubler_disable(scandoubler_disable),

	.ps2_clk(ce_ps2),
	.ps2_kbd_clk(ps2_kbd_clk),
	.ps2_kbd_data(ps2_kbd_data)
);

////////////////////   CLOCKS   ///////////////////
wire locked;
pll pll
(
	.inclk0(CLOCK_27),
	.locked(locked),
	.c0(clk_ram),
	.c1(SDRAM_CLK),
	.c2(clk_sys)
);

wire clk_sys;       // 48Mhz
wire clk_ram;       // 72MHz
reg  clk_io;        // 24MHz
                    //
                    // strobes:
reg  ce_f1,ce_f2;   // 1.78MHz/3.56MHz
reg  ce_pix;        // 16MHz
reg  ce_ps2;        // 14KHz

always @(negedge clk_sys) begin
	reg [2:0] clk_viddiv;
	reg [5:0] cpu_div = 0;
	int ps2_div;
	reg turbo = 0;

	clk_io <= ~clk_io;

	clk_viddiv <= clk_viddiv + 1'd1;
	if(clk_viddiv == 2) clk_viddiv <=0;
	ce_pix   <= !clk_viddiv;

	cpu_div <= cpu_div + 1'd1;
	if(cpu_div == 23) begin 
		cpu_div <= 0;
		turbo <= status[4];
	end
	ce_f1  <= ((cpu_div == 0) | (turbo & (cpu_div == 12)));
	ce_f2  <= ((cpu_div == 2) | (turbo & (cpu_div == 14)));

	ps2_div <= ps2_div+1;
	if(ps2_div == 3570) ps2_div <=0;
	ce_ps2 <= !ps2_div;

	startup <= reset|(startup&~addrbus[15]);
end

////////////////////   RESET   ////////////////////
reg [3:0] reset_cnt;
reg       reset = 1;
wire      RESET = status[0] | status[6] | buttons[1] | reset_key;

always @(posedge clk_sys) begin
	if(!RESET && reset_cnt==4'd14)
		reset <= 0;
	else begin
		reset <= 1;
		reset_cnt <= reset_cnt+4'd1;
	end
end

////////////////////   MEM   ////////////////////
wire  [7:0] ram_o;
sram sram
( 
	.*,
	.init(!locked),
	.clk_sdram(clk_ram),
	.dout(ram_o),
	.din (ioctl_download ? ioctl_data : cpu_o    ),
	.addr(ioctl_download ? ioctl_addr : addrbus  ),
	.we  (ioctl_download ? ioctl_wr   : ~cpu_wr_n),
	.rd  (ioctl_download ? 1'b0       : cpu_rd   )
);

wire  [7:0] rom_o;
bios   rom(.address(addrbus[11:0]), .clock(clk_sys), .q(rom_o));

////////////////////   CPU   ////////////////////
wire [15:0] addrbus;
reg   [7:0] cpu_i;
wire  [7:0] cpu_o;
wire        cpu_rd;
wire        cpu_wr_n;
wire        cpu_inte;
reg         startup;

reg ppa1_sel, ppa2_sel;
always_comb begin
	ppa1_sel =0;
	ppa2_sel =0;
	casex({~startup, addrbus[15:8]})
		9'b00000XXXX: begin cpu_i <= rom_o;                 end
		9'bX1100XXXX: begin cpu_i <= rom_o;                 end
		9'bX11110XXX: begin cpu_i <= ppa2_o; ppa2_sel <= 1; end
		9'bX11111XXX: begin cpu_i <= ppa1_o; ppa1_sel <= 1; end
			  default: begin cpu_i <= ram_o;                 end
	endcase
end

k580vm80a cpu
(
   .pin_clk(clk_sys),
   .pin_f1(ce_f1),
   .pin_f2(ce_f2),
   .pin_reset(reset | ioctl_download),
   .pin_a(addrbus),
   .pin_dout(cpu_o),
   .pin_din(cpu_i),
   .pin_hold(0),
   .pin_ready(1),
   .pin_int(0),
   .pin_inte(cpu_inte),
   .pin_dbin(cpu_rd),
   .pin_wr_n(cpu_wr_n)
);

////////////////////   VIDEO   ////////////////////
wire [2:0] color;
video video
(
	.*,
	
	.clk_pix(ce_pix),

	.addr(addrbus),
	.din(cpu_o),
	.we(~cpu_wr_n),
	.color(~color),
	.bw_mode(status[1])
);

////////////////////   KBD   ////////////////////
wire  [5:0] row_in;
wire [11:0] col_out;
wire [11:0] col_in;
wire  [5:0] row_out;
wire        nr;
wire        reset_key;

keyboard kbd
(
	.*,
	.clk(clk_sys), 
	.reset(reset),
	.ps2_clk(ps2_kbd_clk),
	.ps2_dat(ps2_kbd_data)
);

////////////////////   SYS PPA   ////////////////////
wire [7:0] ppa1_o;
wire [7:0] ppa1_mode;

k580vv55 ppa1
(
	.reset(reset),
	.addr(addrbus[1:0]),
	.we_n(~ppa1_sel | cpu_wr_n),
	.idata(cpu_o),
	.odata(ppa1_o),
	
	.ipa(col_out[7:0]),
	.ipc({4'b1111, col_out[11:8]}), 
	.opb({row_in, 2'bZZ}),

	.opa(col_in[7:0]),
	.opc({color[2], color[1], spk_out, color[0], col_in[11:8]}),
	.ipb({row_out, nr, 1'b0}),

	.mode(ppa1_mode)
);

/////////////////   PPA2(DUMMY)   //////////////////
wire [7:0] ppa2_o;
wire [7:0] ppa2_a;
wire [7:0] ppa2_b;
wire [7:0] ppa2_c;

k580vv55 ppa2
(
	.reset(reset), 
	.addr(addrbus[1:0]), 
	.we_n(~ppa2_sel | cpu_wr_n),
	.idata(cpu_o), 
	.odata(ppa2_o), 
	.ipa(ppa2_a), 
	.opa(ppa2_a), 
	.ipb(ppa2_b), 
	.opb(ppa2_b), 
	.ipc(ppa2_c), 
	.opc(ppa2_c)
);

////////////////////   SOUND   ////////////////////

reg spk_out;
assign AUDIO_R = ~spk_out;
assign AUDIO_L = AUDIO_R;

//////////////////   LOADING   //////////////////
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_data;
wire        ioctl_download;
wire  [4:0] ioctl_index;

data_io data_io
(
	.sck(SPI_SCK),
	.ss(SPI_SS2),
	.sdi(SPI_DI),

	.downloading(ioctl_download),
	.index(ioctl_index),

	.clk(clk_io),
	.wr(ioctl_wr),
	.a(ioctl_addr),
	.d(ioctl_data)
);

assign LED = ~ioctl_download;

endmodule
