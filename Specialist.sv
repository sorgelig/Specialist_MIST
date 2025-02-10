// ====================================================================
//                Specialist FPGA REPLICA
//
//            Copyright (C) 2016 Sorgelig
//
// This core is distributed under modified GNU GPL v2 license. 
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

assign LED = ~(ioctl_download | ioctl_erasing);

`include "build_id.v"
localparam CONF_STR =
{
	"SPMX;;",
	"F1,RKS,Load Tape;",
	"S0,ODI,Mount Disk;",
	"O4,CPU Speed,2MHz,4MHz;",
	"O23,Model,Original,MX & Disk,MX;",
	"O78,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%;",
	"T6,Cold Reset;",
	"V0,v2.20.",`BUILD_DATE
};


///////////////////   ARM I/O   //////////////////
wire [31:0] status;
wire  [1:0] buttons;
wire        scandoubler_disable;
wire        ypbpr;
wire        ps2_kbd_clk;
wire        ps2_kbd_data;

wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire        ioctl_download;
wire        ioctl_erasing;
wire  [7:0] ioctl_index;
wire        rom_load =  (ioctl_download & (ioctl_index==0));
wire        rks_load =  (ioctl_download & (ioctl_index==1));
wire        odi_load =  (ioctl_download & (ioctl_index==2));

wire [31:0] sd_lba;
wire        sd_rd;
wire        sd_wr;
wire        sd_ack;
wire  [8:0] sd_buff_addr;
wire  [7:0] sd_buff_dout;
wire  [7:0] sd_buff_din;
wire        sd_buff_wr;
wire        img_mounted;
wire [31:0] img_size;

mist_io #(.STRLEN($size(CONF_STR)>>3)) mist_io 
(
	.*,
	.conf_str(CONF_STR),
	.sd_conf(0),
	.sd_sdhc(1),
	.ioctl_force_erase(status[6]),

	// unused
	.joystick_0(),
	.joystick_1(),
	.joystick_analog_0(),
	.joystick_analog_1(),
	.sd_ack_conf(),
	.switches(),
	.ps2_mouse_clk(),
	.ps2_mouse_data()
);


////////////////////   CLOCKS   ///////////////////
wire locked;
pll pll
(
	.inclk0(CLOCK_27),
	.locked(locked),
	.c0(clk_sys),
	.c1(SDRAM_CLK)
);

wire clk_sys;       // 96MHz
reg  ce_f1,ce_f2;   // 2MHz/4MHz
reg  ce_pit;        // 2MHz
reg  ce_pix_p;      // 16MHz
reg  ce_pix_n;      // 16MHz

always @(negedge clk_sys) begin
	reg [3:0] clk_viddiv;
	reg [5:0] cpu_div = 0;
	reg       turbo = 0;

	clk_viddiv <= clk_viddiv + 1'd1;
	if(clk_viddiv == 11) clk_viddiv <=0;
	ce_pix_p <= (clk_viddiv == 0);
	ce_pix_n <= (clk_viddiv == 6);

	cpu_div <= cpu_div + 1'd1;
	if(cpu_div == 47) begin 
		cpu_div <= 0;
		turbo <= status[4];
	end
	ce_f1  <= ((cpu_div == 0)  | (turbo & (cpu_div == 24)));
	ce_f2  <= ((cpu_div == 12) | (turbo & (cpu_div == 36)));
	ce_pit <= !cpu_div;
end


////////////////////   RESET   ////////////////////
reg       reset = 0;
reg [7:0] mon;

always @(posedge clk_sys) begin
	if(status[0] | buttons[1] | reset_key[0] | rom_load | ioctl_erasing) begin
		mx    <= (status[3:2] >0);
		mxd   <= (status[3:2]==1) && ~reset_key[1];
		mon   <= (status[3:2]==0) ? 8'h1C : ((status[3:2]==1) && reset_key[1]) ? 8'h0C : 8'h1D;
		reset <= 1;
	end else begin
		reset <= 0;
	end
end


//////////////////   MEMORY   ////////////////////
wire  [7:0] ram_o;
sram sram
( 
	.*,
	.init(!locked),
	.clk_sdram(clk_sys),
	.dout(ram_o),
	.din ((ioctl_download | ioctl_erasing) ? ioctl_dout : cpu_o    ),
	.addr((ioctl_download | ioctl_erasing) ? ioctl_addr : ram_addr ),
	.we  ((ioctl_download | ioctl_erasing) ? ioctl_wr   : ~cpu_wr_n & ~rom_sel),
	.rd  ((ioctl_download | ioctl_erasing) ? 1'b0       : cpu_rd   ),
	.ready()
);

reg [3:0] page = 1;
wire      romp = (page == 1);
always @(posedge clk_sys) begin
	reg old_wr;
	old_wr <= cpu_wr_n;

	if(reset) begin
		page <= 1;
	end else if(rks_load) begin
		page <= 0;
	end else begin
		if(old_wr & ~cpu_wr_n & page_sel & mxd) begin
			casex(addrbus[1:0])
				2'b00: page <= 4'd0;
				2'b01: page <= 4'd2 + cpu_o[2:0];
				2'b1X: page <= 4'd1;
			endcase
		end
		if(~(mx & mxd) & addrbus[15]) page <= 0;
	end
end

reg [24:0] ram_addr;
always_comb begin
	casex({mxd, base_sel, rom_sel})
		//without disk
		4'b0_X0: ram_addr = addrbus;
		4'b0_X1: ram_addr = {mon,  addrbus[11:0]};

		//with disk
		4'b1_1X: ram_addr = addrbus;
		4'b1_0X: ram_addr = {page, addrbus};
	endcase
end


////////////////////   MMU   ////////////////////
reg ppi1_sel;
reg ppi2_sel;
reg pit_sel;
reg pal_sel;
reg page_sel;
reg base_sel;
reg rom_sel;
reg fdd_sel;
reg fdd2_sel;
reg mx;
reg mxd;

always_comb begin
	ppi1_sel = 0;
	ppi2_sel = 0;
	pit_sel  = 0;
	pal_sel  = 0;
	page_sel = 0;
	base_sel = 0;
	rom_sel  = 0;
	fdd_sel  = 0;
	fdd2_sel = 0;
	cpu_i    = 255;
	casex({mx, mxd, romp, addrbus})

		//MX
		'b11_1_0XXXXXXX_XXXXXXXX: begin cpu_i = ram_o;  rom_sel  = 1;    end
		'b11_1_10XXXXXX_XXXXXXXX: begin cpu_i = ram_o;  rom_sel  = 1;    end
		'b10_1_0000XXXX_XXXXXXXX: begin cpu_i = ram_o;  rom_sel  = 1;    end
		'b10_X_1100XXXX_XXXXXXXX: begin cpu_i = ram_o;  rom_sel  = 1;    end
		'b1X_X_11111111_110XXXXX: begin cpu_i = ram_o;  base_sel = 1;    end
		'b1X_X_11111111_111000XX: begin cpu_i = ppi1_o; ppi1_sel = 1;    end
		'b1X_X_11111111_111001XX: begin cpu_i = ppi2_o; ppi2_sel = 1;    end
		'b1X_X_11111111_111010XX: begin cpu_i = fdd_o;  fdd_sel  = 1;    end
		'b1X_X_11111111_111011XX: begin cpu_i = pit_o;  pit_sel  = 1;    end
		'b1X_X_11111111_111100XX: begin                 fdd2_sel = 1;    end
		'b1X_X_11111111_111101XX: begin                                  end
		'b1X_X_11111111_111110XX: begin                 pal_sel  = 1;    end
		'b1X_X_11111111_111111XX: begin                 page_sel = 1;    end

		//Original
		'b0X_1_0000XXXX_XXXXXXXX: begin cpu_i = ram_o;  rom_sel  = 1;    end
		'b0X_X_1100XXXX_XXXXXXXX: begin cpu_i = ram_o;  rom_sel  = 1;    end
		'b0X_X_11110XXX_XXXXXXXX: begin cpu_i = ppi2_o; ppi2_sel = 1;    end
		'b0X_X_11111XXX_XXXXXXXX: begin cpu_i = ppi1_o; ppi1_sel = 1;    end

							  default: begin cpu_i = ram_o;  base_sel = romp; end
	endcase
end


////////////////////   CPU   ////////////////////
wire [15:0] addrbus;
reg   [7:0] cpu_i;
wire  [7:0] cpu_o;
wire        cpu_rd;
wire        cpu_wr_n;
reg         cpu_hold = 0;

k580vm80a cpu
(
   .pin_clk(clk_sys),
   .pin_f1(ce_f1),
   .pin_f2(ce_f2),
   .pin_reset(reset | rks_load),
   .pin_a(addrbus),
   .pin_dout(cpu_o),
   .pin_din(cpu_i),
   .pin_hold(cpu_hold),
   .pin_ready(~odi_load),
   .pin_int(0),
   .pin_dbin(cpu_rd),
   .pin_wr_n(cpu_wr_n)
);


////////////////////   VIDEO   ////////////////////
wire [2:0] color;
reg  [7:0] color_mx;
reg        bw_mode;
video video
(
	.*,
	.addr(addrbus),
	.din(cpu_o),
	.we(~cpu_wr_n && !page),
	.scale(status[8:7]),
	.color(mx ? color_mx : {1'b0, ~color[1], ~color[2], ~color[0], 4'b0000})
);

always @(posedge clk_sys) begin
	reg old_wr, old_key;
	old_wr <= cpu_wr_n;
	if(reset | rks_load) color_mx <= 8'hF0;
		else if(old_wr & ~cpu_wr_n & pal_sel) color_mx <= cpu_o;
	
	old_key <= color_key;
	if(~old_key & color_key) bw_mode <= ~bw_mode;
end


//////////////////   KEYBOARD   ///////////////////
wire  [5:0] row_in;
wire [11:0] col_out;
wire [11:0] col_in;
wire  [5:0] row_out;
wire        nr;
wire  [1:0] reset_key;
wire        color_key;

keyboard keyboard(.*);


////////////////////   SYS PPI   ////////////////////
wire [7:0] ppi1_o;

k580vv55 ppi1
(
	.clk_sys(clk_sys),

	.addr(addrbus[1:0]),
	.we_n(cpu_wr_n | ~ppi1_sel),
	.idata(cpu_o),
	.odata(ppi1_o),

	.ipa(col_out[7:0]),
	.ipc({4'b1111, col_out[11:8]}),
	.opb({row_in, 2'bZZ}),

	.opa(col_in[7:0]),
	.opc({color[2], color[1], spk_out, color[0], col_in[11:8]}),
	.ipb({row_out, nr, 1'b0})
);


///////////////////   MISC PPI   ////////////////////
wire [7:0] ppi2_o;
wire [7:0] ppi2_a;
wire [7:0] ppi2_b;
wire [7:0] ppi2_c;

k580vv55 ppi2
(
	.reset(reset),
	.clk_sys(clk_sys),

	.addr(addrbus[1:0]), 
	.we_n(cpu_wr_n | ~ppi2_sel),
	.idata(cpu_o), 
	.odata(ppi2_o), 
	.ipa({ppi2_a[7:1], pit_out[2]}), 
	.opa(ppi2_a),
	.ipb(ppi2_b),
	.opb(ppi2_b),
	.ipc(ppi2_c),
	.opc(ppi2_c)
);


////////////////////   SOUND   ////////////////////
reg spk_out;
assign AUDIO_R = (pit_out[0] | pit_o[2]) & ~spk_out;
assign AUDIO_L = AUDIO_R;

wire [7:0] pit_o;
wire [2:0] pit_out;

k580vi53 pit
(
	.reset(reset),
	.clk_sys(clk_sys),
	.clk_timer({ce_pit,ce_pit,pit_out[1]}),

	.addr(addrbus[1:0]),
	.wr(~cpu_wr_n & pit_sel),
	.rd(cpu_rd & pit_sel),
	.din(cpu_o),
	.dout(pit_o),
	.gate(3'b111),
	.out(pit_out)
);


/////////////////////   FDD   /////////////////////
wire  [7:0] fdd_o;
reg         fdd_drive;
reg         fdd_side;
reg         fdd_ready = 0;
wire        fdd_drq;
wire        fdd_busy;

always @(posedge clk_sys) begin
	reg old_mounted;

	old_mounted <= img_mounted;
	if(~old_mounted & img_mounted) fdd_ready <= 1;
end

wd1793 #(1) fdd
(
	.clk_sys(clk_sys),
	.ce(ce_f1),
	.reset(reset),
	.io_en(fdd_sel),
	.rd(cpu_rd),
	.wr(~cpu_wr_n),
	.addr(addrbus[1:0]),
	.din(cpu_o),
	.dout(fdd_o),
	.drq(fdd_drq),
	.busy(fdd_busy),

	.img_mounted(img_mounted),
	.img_size(img_size),
	.sd_lba(sd_lba),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr),

	.wp(0),

	.size_code(3),
	.layout(0),
	.side(fdd_side),
	.ready(~fdd_drive & fdd_ready),
	.prepare(),

	.input_active(0),
	.input_addr(0),
	.input_data(0),
	.input_wr(0),
	.buff_din(0)
);

wire fdd2_we = ~cpu_wr_n & fdd2_sel;
always @(posedge clk_sys) begin
	reg old_we;

	old_we <= fdd2_we;
	if(reset) begin
		fdd_side  <= 0;
		fdd_drive <= 0;
		cpu_hold  <= 0;
		old_we    <= 0;
	end else begin
		if(~old_we & fdd2_we) begin
			case(addrbus[1:0])
				0: cpu_hold  <= 1;
				2: fdd_side  <= cpu_o[0];
				3: fdd_drive <= cpu_o[0];
				default: ;
			endcase
		end

		if(fdd_drq | ~fdd_busy) cpu_hold <= 0;
	end
end

endmodule
