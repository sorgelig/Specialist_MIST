//
// mist_io.v
//
// mist_io for the MiST board
// http://code.google.com/p/mist-board/
//
// Copyright (c) 2014 Till Harbaum <till@harbaum.org>
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

module mist_io #(parameter STRLEN=0)
(
	input [(8*STRLEN)-1:0] conf_str,

	input         SPI_SCK,
	input         CONF_DATA0,
	input         SPI_SS2,
	output        SPI_DO,
	input         SPI_DI,
	
	output  [7:0] joystick_0,
	output  [7:0] joystick_1,
	output [15:0] joystick_analog_0,
	output [15:0] joystick_analog_1,
	output  [1:0] buttons,
	output  [1:0] switches,
	output        scandoubler_disable,

	output  [7:0] status,

	// connection to sd card emulation
	input  [31:0] sd_lba,
	input         sd_rd,
	input         sd_wr,
	output 	     sd_ack,
	input         sd_conf,
	input         sd_sdhc,
	output  [7:0] sd_dout,
	output 	     sd_dout_strobe,
	input   [7:0] sd_din,
	output  	     sd_din_strobe,
	output        sd_mounted,
	
	// ps2 keyboard emulation
	input         ps2_clk,			// 12-16khz provided by core
	output        ps2_kbd_clk,
	output        ps2_kbd_data,
	output        ps2_mouse_clk,
	output        ps2_mouse_data,

	// serial port 
	input   [7:0] serial_data,
	input         serial_strobe,
	
	// downloading
	output        io_download,    // signal indicating an active download
   output  [4:0] io_index,       // menu index used to upload the file
	input         io_clk,
	output        io_wr,
	output [24:0] io_addr,
	output  [7:0] io_dout
);

user_io #(.STRLEN(STRLEN)) user_io (.*);

data_io data_io
(
	.*,
	.downloading(io_download),
   .index(io_index),
	.clk(io_clk),
	.wr(io_wr),
	.addr(io_addr),
	.dout(io_dout)
);

endmodule

////////////////////////////////////////////////////////////////////////////////
// parameter STRLEN and the actual length of conf_str have to match
 
module user_io #(parameter STRLEN=0) (
	input [(8*STRLEN)-1:0] conf_str,

	input      		   SPI_SCK,
	input      		   CONF_DATA0,
	output            SPI_DO,
	input      		   SPI_DI,
	
	output reg  [7:0] joystick_0,
	output reg  [7:0] joystick_1,
	output reg [15:0] joystick_analog_0,
	output reg [15:0] joystick_analog_1,
	output      [1:0] buttons,
	output      [1:0] switches,
	output  				scandoubler_disable,

	output reg [7:0]  status,

	// connection to sd card emulation
	input      [31:0] sd_lba,
	input             sd_rd,
	input             sd_wr,
	output reg	      sd_ack,
	input             sd_conf,
	input             sd_sdhc,
	output reg [7:0]  sd_dout,
	output reg	      sd_dout_strobe,
	input [7:0]       sd_din,
	output reg 	      sd_din_strobe,
	output            sd_mounted,
	

	// ps2 keyboard emulation
	input 	  		   ps2_clk,				// 12-16khz provided by core
	output	 		   ps2_kbd_clk,
	output reg 		   ps2_kbd_data,
	output	 		   ps2_mouse_clk,
	output reg 		   ps2_mouse_data,

	// serial port 
	input [7:0]		   serial_data,
	input				   serial_strobe
);

reg [6:0] sbuf;
reg [7:0] cmd;
reg [2:0] bit_cnt;    // counts bits 0-7 0-7 ...
reg [7:0] byte_cnt;   // counts bytes
reg [7:0] but_sw;
reg [2:0] stick_idx;

reg    mount_strobe = 1'b0;
assign sd_mounted   = mount_strobe;

assign buttons = but_sw[1:0];
assign switches = but_sw[3:2];
assign scandoubler_disable = but_sw[4];

wire [7:0] dout = { sbuf, SPI_DI};

// this variant of user_io is for 8 bit cores (type == a4) only
wire [7:0] core_type = 8'ha4;

// command byte read by the io controller
wire [7:0] sd_cmd = { 4'h5, sd_conf, sd_sdhc, sd_wr, sd_rd };

reg spi_do;
assign SPI_DO = CONF_DATA0 ? 1'bZ : spi_do;

// drive MISO only when transmitting core id
always@(negedge SPI_SCK) begin
	if(!CONF_DATA0) begin
		// first byte returned is always core type, further bytes are 
		// command dependent
      if(byte_cnt == 0) begin
		  spi_do <= core_type[~bit_cnt];

		end else begin
			// reading serial fifo
		   if(cmd == 8'h1b) begin
				// send alternating flag byte and data
				if(byte_cnt[0]) 	spi_do <= serial_out_status[~bit_cnt];
				else					spi_do <= serial_out_byte[~bit_cnt];
			end
			
			// reading config string
		   else if(cmd == 8'h14) begin
				// returning a byte from string
				if(byte_cnt < STRLEN + 1)
					spi_do <= conf_str[{STRLEN - byte_cnt,~bit_cnt}];
				else
					spi_do <= 1'b0;
			end
			
			// reading sd card status
		   else if(cmd == 8'h16) begin
				if(byte_cnt == 1)
					spi_do <= sd_cmd[~bit_cnt];
				else if((byte_cnt >= 2) && (byte_cnt < 6))
					spi_do <= sd_lba[{5-byte_cnt, ~bit_cnt}];
				else
					spi_do <= 1'b0;
			end
			
			// reading sd card write data
		   else if(cmd == 8'h18)
				spi_do <= sd_din[~bit_cnt];
				
			else
				spi_do <= 1'b0;
		end
   end
end

// ---------------- PS2 ---------------------

// 8 byte fifos to store ps2 bytes
localparam PS2_FIFO_BITS = 3;

// keyboard
reg [7:0] ps2_kbd_fifo [(2**PS2_FIFO_BITS)-1:0];
reg [PS2_FIFO_BITS-1:0] ps2_kbd_wptr;
reg [PS2_FIFO_BITS-1:0] ps2_kbd_rptr;

// ps2 transmitter state machine
reg [3:0] ps2_kbd_tx_state;
reg [7:0] ps2_kbd_tx_byte;
reg ps2_kbd_parity;

assign ps2_kbd_clk = ps2_clk || (ps2_kbd_tx_state == 0);

// ps2 transmitter
// Takes a byte from the FIFO and sends it in a ps2 compliant serial format.
reg ps2_kbd_r_inc;
always@(posedge ps2_clk) begin
	ps2_kbd_r_inc <= 1'b0;
	
	if(ps2_kbd_r_inc)
		ps2_kbd_rptr <= ps2_kbd_rptr + 3'd1;

	// transmitter is idle?
	if(ps2_kbd_tx_state == 0) begin
		// data in fifo present?
		if(ps2_kbd_wptr != ps2_kbd_rptr) begin
			// load tx register from fifo
			ps2_kbd_tx_byte <= ps2_kbd_fifo[ps2_kbd_rptr];
			ps2_kbd_r_inc <= 1'b1;
			
			// reset parity
			ps2_kbd_parity <= 1'b1;
			
			// start transmitter
			ps2_kbd_tx_state <= 4'd1;

			// put start bit on data line
			ps2_kbd_data <= 1'b0;			// start bit is 0
		end
	end else begin
	
		// transmission of 8 data bits
		if((ps2_kbd_tx_state >= 1)&&(ps2_kbd_tx_state < 9)) begin
			ps2_kbd_data <= ps2_kbd_tx_byte[0];			  // data bits
			ps2_kbd_tx_byte[6:0] <= ps2_kbd_tx_byte[7:1]; // shift down
			if(ps2_kbd_tx_byte[0]) 
				ps2_kbd_parity <= !ps2_kbd_parity;
		end

		// transmission of parity
		if(ps2_kbd_tx_state == 9)
			ps2_kbd_data <= ps2_kbd_parity;
			
		// transmission of stop bit
		if(ps2_kbd_tx_state == 10)
			ps2_kbd_data <= 1'b1;			// stop bit is 1

		// advance state machine
		if(ps2_kbd_tx_state < 11)
			ps2_kbd_tx_state <= ps2_kbd_tx_state + 4'd1;
		else	
			ps2_kbd_tx_state <= 4'd0;
	
	end
end
  
// mouse
reg [7:0] ps2_mouse_fifo [(2**PS2_FIFO_BITS)-1:0];
reg [PS2_FIFO_BITS-1:0] ps2_mouse_wptr;
reg [PS2_FIFO_BITS-1:0] ps2_mouse_rptr;

// ps2 transmitter state machine
reg [3:0] ps2_mouse_tx_state;
reg [7:0] ps2_mouse_tx_byte;
reg ps2_mouse_parity;

assign ps2_mouse_clk = ps2_clk || (ps2_mouse_tx_state == 0);

// ps2 transmitter
// Takes a byte from the FIFO and sends it in a ps2 compliant serial format.
reg ps2_mouse_r_inc;
always@(posedge ps2_clk) begin
	ps2_mouse_r_inc <= 1'b0;
	
	if(ps2_mouse_r_inc)
		ps2_mouse_rptr <= ps2_mouse_rptr + 3'd1;

	// transmitter is idle?
	if(ps2_mouse_tx_state == 0) begin
		// data in fifo present?
		if(ps2_mouse_wptr != ps2_mouse_rptr) begin
			// load tx register from fifo
			ps2_mouse_tx_byte <= ps2_mouse_fifo[ps2_mouse_rptr];
			ps2_mouse_r_inc <= 1'b1;
			
			// reset parity
			ps2_mouse_parity <= 1'b1;
			
			// start transmitter
			ps2_mouse_tx_state <= 4'd1;

			// put start bit on data line
			ps2_mouse_data <= 1'b0;			// start bit is 0
		end
	end else begin
	
		// transmission of 8 data bits
		if((ps2_mouse_tx_state >= 1)&&(ps2_mouse_tx_state < 9)) begin
			ps2_mouse_data <= ps2_mouse_tx_byte[0];			  // data bits
			ps2_mouse_tx_byte[6:0] <= ps2_mouse_tx_byte[7:1]; // shift down
			if(ps2_mouse_tx_byte[0]) 
				ps2_mouse_parity <= !ps2_mouse_parity;
		end

		// transmission of parity
		if(ps2_mouse_tx_state == 9)
			ps2_mouse_data <= ps2_mouse_parity;
			
		// transmission of stop bit
		if(ps2_mouse_tx_state == 10)
			ps2_mouse_data <= 1'b1;			// stop bit is 1

		// advance state machine
		if(ps2_mouse_tx_state < 11)
			ps2_mouse_tx_state <= ps2_mouse_tx_state + 4'd1;
		else	
			ps2_mouse_tx_state <= 4'd0;
	
	end
end

// fifo to receive serial data from core to be forwarded to io controller

// 16 byte fifo to store serial bytes
localparam SERIAL_OUT_FIFO_BITS = 6;
reg [7:0] serial_out_fifo [(2**SERIAL_OUT_FIFO_BITS)-1:0];
reg [SERIAL_OUT_FIFO_BITS-1:0] serial_out_wptr;
reg [SERIAL_OUT_FIFO_BITS-1:0] serial_out_rptr;
 
wire serial_out_data_available = serial_out_wptr != serial_out_rptr;
wire [7:0] serial_out_byte = serial_out_fifo[serial_out_rptr] /* synthesis keep */;
wire [7:0] serial_out_status = { 7'b1000000, serial_out_data_available};

// status[0] is reset signal from io controller and is thus used to flush
// the fifo
always @(posedge serial_strobe or posedge status[0]) begin
	if(status[0] == 1) begin
		serial_out_wptr <= 0;
	end else begin 
		serial_out_fifo[serial_out_wptr] <= serial_data;
		serial_out_wptr <= serial_out_wptr + 6'd1;
	end
end 

always@(negedge SPI_SCK or posedge status[0]) begin
	if(status[0] == 1) begin
		serial_out_rptr <= 0;
	end else begin
		if((byte_cnt != 0) && (cmd == 8'h1b)) begin
			// read last bit -> advance read pointer
			if((bit_cnt == 7) && !byte_cnt[0] && serial_out_data_available)
				serial_out_rptr <= serial_out_rptr + 6'd1;
		end
	end
end

// SPI receiver
always@(posedge SPI_SCK or posedge CONF_DATA0) begin

	if(CONF_DATA0 == 1) begin
	   bit_cnt <= 3'd0;
	   byte_cnt <= 8'd0;
		sd_ack <= 1'b0;
		sd_dout_strobe <= 1'b0;
		sd_din_strobe <= 1'b0;
	end else begin
		sd_dout_strobe <= 1'b0;
		sd_din_strobe <= 1'b0;
		
		sbuf <= dout[6:0];
		bit_cnt <= bit_cnt + 3'd1;

		// finished reading command byte
      if(bit_cnt == 7) begin
			if(byte_cnt != 8'd255) byte_cnt <= byte_cnt + 8'd1;
			if(byte_cnt == 0) begin
				cmd <= dout;
			
				// fetch first byte when sectore FPGA->IO command has been seen
				if(dout == 8'h18)
					sd_din_strobe <= 1'b1;
					
				if((dout == 8'h17) || (dout == 8'h18))
					sd_ack <= 1'b1;

				mount_strobe <= 1'b0;
					
			end else begin
			
				case(cmd)
				// buttons and switches
					8'h01: but_sw <= dout; 
					8'h02: joystick_0 <= dout;
					8'h03: joystick_1 <= dout;

					// store incoming ps2 mouse bytes 
					8'h04: begin
							ps2_mouse_fifo[ps2_mouse_wptr] <= dout; 
							ps2_mouse_wptr <= ps2_mouse_wptr + 3'd1;
						end

					// store incoming ps2 keyboard bytes 
					8'h05: begin
							ps2_kbd_fifo[ps2_kbd_wptr] <= dout; 
							ps2_kbd_wptr <= ps2_kbd_wptr + 3'd1;
						end
				
					8'h15: status <= dout;
				
					// send SD config IO -> FPGA
					// flag that download begins
					// sd card knows data is config if sd_dout_strobe is asserted
					// with sd_ack still being inactive (low)
					8'h19,
					// send sector IO -> FPGA
					// flag that download begins
					8'h17: begin 
							sd_dout        <= dout;
							sd_dout_strobe <= 1'b1;
						end
				
					// send sector FPGA -> IO
					8'h18: sd_din_strobe <= 1'b1;
				
					// joystick analog
					8'h1a: begin
							// first byte is joystick index
							if(byte_cnt == 1) stick_idx <= dout[2:0];
							else if(byte_cnt == 2) begin
								// second byte is x axis
								if(stick_idx == 0) joystick_analog_0[15:8] <= dout;
									else if(stick_idx == 1) joystick_analog_1[15:8] <= dout;
							end else if(byte_cnt == 3) begin
								// third byte is y axis
								if(stick_idx == 0) joystick_analog_0[7:0] <= dout;
									else if(stick_idx == 1) joystick_analog_1[7:0] <= dout;
							end
						end

					// notify image selection
					8'h1c: mount_strobe <= 1'b1;

					default: ;
				endcase
			end
		end
	end
end
   
endmodule

////////////////////////////////////////////////////////////////////////////////////////////

module data_io
(
	// io controller spi interface
	input         SPI_SCK,
	input         SPI_SS2,
	input         SPI_DI,

	output        downloading,
   output  [4:0] index,

	// external ram interface
	input         clk,
	output reg    wr,
	output [24:0] addr,
	output  [7:0] dout
);

assign index = new_index;
assign downloading = downloading_reg || erasing;

assign dout = erasing ? 8'h00 : data;
assign addr = erasing ? eaddr : waddr;

reg  [6:0] sbuf;
reg  [7:0] cmd;
reg  [7:0] data;
reg  [4:0] cnt;
reg [24:0] laddr;
reg [24:0] waddr;
reg        downloading_reg = 0;
reg [15:0] start_addr;
reg  [4:0] new_index;
reg        rclk = 0;

localparam UIO_FILE_TX      = 8'h53;
localparam UIO_FILE_TX_DAT  = 8'h54;
localparam UIO_FILE_INDEX   = 8'h55;

// data_io has its own SPI interface to the io controller
always@(posedge SPI_SCK, posedge SPI_SS2) begin
	reg skip;

	if(SPI_SS2) cnt <= 5'd0;
	else begin
		rclk <= 0;
		erase_trigger <= 0;

		// don't shift in last bit. It is evaluated directly
		// when writing to ram
		if(cnt != 15) sbuf <= { sbuf[5:0], SPI_DI};

		// increase target address after write
		if(rclk) begin
			laddr <= laddr + 1'd1;
			if(skip & (laddr == 3)) begin
				laddr <= start_addr;
				skip <= 0;
			end
		end

		// count 0-7 8-15 8-15 ... 
		if(cnt < 15) cnt <= cnt + 1'd1;
			else cnt <= 8;

		// finished command byte
      if(cnt == 7) cmd <= {sbuf, SPI_DI};

		// prepare/end transmission
		if((cmd == UIO_FILE_TX) && (cnt == 15)) begin
			// prepare 
			if(SPI_DI) begin
				erase_trigger <= 0;
				skip <= 0;
				case(new_index)
					0: laddr <= 25'h010000;
					2: laddr <= 25'h100000;
					1: {laddr,skip} <= 1;
					default: ;
				endcase
				downloading_reg <= 1;
			end else begin
				downloading_reg <= 0;
				waddr <= laddr + 1'b1;
				if(!new_index) erase_trigger <= 1;
			end
		end

		// command 0x54: UIO_FILE_TX
		if((cmd == UIO_FILE_TX_DAT) && (cnt == 15)) begin
			case({laddr, skip})
				3'b001: {data, start_addr[15:8]} <= {8'hC3, sbuf, SPI_DI};
				3'b011: {data, start_addr[7:0]}  <= {sbuf, SPI_DI, sbuf, SPI_DI};
				3'b101:  data                    <=  start_addr[15:8];
			  default:  data                    <= {sbuf, SPI_DI};
			endcase
			waddr <= laddr;
			rclk  <= 1;
		end

      // expose file (menu) index
      if((cmd == UIO_FILE_INDEX) && (cnt == 15)) new_index <= {sbuf[3:0], SPI_DI};
	end
end

reg        erase_trigger = 0;
reg [24:0] eaddr;
reg [24:0] emask;
reg        erasing = 0;
wire[24:0] next_addr = (eaddr + 1'd1) & emask;

always@(posedge clk) begin
	reg rclkD, rclkD2;
	reg eraseD, eraseD2;
	reg  [4:0] clk_div;
	reg [24:0] end_addr;
	rclkD <= rclk;
	rclkD2 <= rclkD;
	wr <= 0;
	
	if(rclkD && !rclkD2) wr <= 1;

	eraseD <= erase_trigger;
	eraseD2 <= eraseD;

	// start erasing
	if(eraseD && !eraseD2) begin
		clk_div <= 0;
		eaddr <= waddr;
		emask <= 25'hFFFFF;
		end_addr <= 0;
		erasing <= 1;
	end else begin
		clk_div <= clk_div + 5'd1;
		if(!clk_div) begin
			if(next_addr != end_addr) begin
				eaddr <= next_addr;
				if(next_addr > 2) wr <= 1;
			end else begin
				erasing <= 0;
			end
		end
	end
end 

endmodule
