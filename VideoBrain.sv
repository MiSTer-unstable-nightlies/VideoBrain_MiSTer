//============================================================================
//  VideoBrain Family Computer for MiSTer
//  SPDX-License-Identifier: GPL-2.0-or-later
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);


assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;

assign VGA_F1 = progressive ? 1'b0 : vid_field;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign AUDIO_S   = 1;
assign AUDIO_MIX = 0;

assign LED_DISK  = 0;
assign LED_POWER = 0;
assign BUTTONS   = 0;


wire [1:0] ar = status[122:121];

`include "build_id.v"
localparam CONF_STR = {
	"VideoBrain;UART300:110;",
	"F1,BIN,Load Cartridge;",
	"-;",
	"d8S0,VBT,Mount Playback Tape;",
	"T[23],Rewind Playback Tape;",
	"d8S1,VBT,Mount Record Tape;",
	"T[30],Rewind Record Tape;",
	"-;",
	"P4,Keyboard;",
	"P4-;",
	"P4F4,VBK,Load Keyboard File;",
	"P4-;",
	"P4O[31],OSD Aborts VBK,On,Off;",
	"H5P4O[18],Music Mode,Playback,Record;",
	"h5D5P4O[18],Music Mode,Playback;",
	"P4O[19],Music Repeat,Off,On;",
	"P4-;",
	"P4O[29],Esc Soft Reset,On,Off;",
	"P3,Joysticks;",
	"P3-;",
	"P3O[5],Joysticks,Connected,Disconnected;",
	"D4P3R[20],Calibrate Sticks;",
	"P3-;",
	"D4P3O[15:14],Stick Preset,Auto,Tennis,Gladiator;",
	"D4P3O[38],Analog Mode,Absolute,Relative;",
	"DDP3O[40:39],Relative Speed,Slow,Normal,Fast;",
	"P3-;",
	"D4P3O[17:16],Paired Sticks,Off,1+2 / 3+4,1+3 / 2+4 (Doubles);",
	"P1,Video;",
	"P1-;",
	"P1O[42:41],Output,480i (Original),240p,480p;",
	"P1T[43],Apply Video Output;",
	"P1-;",
	"P1O[122:121],Aspect Ratio,Original,Full Screen,[ARC1],[ARC2];",
	"P1O[125:123],Scale,Normal,V-Integer,HV-Integer-,HV-Integer+,HV-Integer;",
	"P5,Printer;",
	"P5-;",
	"d6P5S2,VBP,Mount Capture Image;",
	"P5O[33],Capture Baud,300,110;",
	"P5-;",
	"d7P5T[34],Start Capture;",
	"DEP5T[35],Stop Capture and Save;",
	"DEP5T[36],Show Capture Status;",
	"P5-;",
	"P5O[37],Info. Manager Fix,Off,On;",
	"P5-;",
	"h9P5-,Printer Active;",
	"hBP5-,Printer Busy;",
	"hCP5-,Printer Error;",
	"P2,System;",
	"P2-;",
	"P2F0,BIN,Load BIOS;",
	"P2F2,BIN,Load Expander 1 ROM;",
	"P2-;",
	"P2O[22],Info Messages,On,Off;",
	"P2O[24],Reset on Load,On,Off;",
	"P2O[44],BIOS Clock,Manual,Auto (RTC);",
	"P2O[32],UART Output,Modem,Printer;",	
	"P2O[11:9],Mapper Fallback,Standard,Timeshare,Money Minder,APL/S,Info. Manager,4K RAM,BASIC;",
	"P2-;",
	"P2T[27],Master Control (Soft Reset);",
	"-;",
	"DAR[28],Unload Cartridge;",
	"R[0],Reset;",
	"J,Fire,Fire (Paired);",
	"jn,A,B;",
	"I,Keyboard entry started,Bad keyboard file,Tape error,Tape rewound,Tape busy,Tape idle,Keyboard entry finished,Keyboard entry aborted,Calibrating sticks,End of tape,Printer no image,Printer scanning,Printer ready,Printer starting,Printer active,Printer flushing,Printer stalled,Printer full,Printer error,Printer read only,Printer bad image,Printer incomplete image,Printer storage error,Printer framing error,Printer overflow,Printer media changed,Printer reset interrupted;",
	"v,1;",
	"V,v",`BUILD_DATE
};

wire   [1:0] buttons;
wire [127:0] status;
wire [64:0] RTC;
wire [55:0] rtc_time;
wire rtc_time_valid;
wire joystick_connected = ~status[5];
wire cart_loaded;
wire  [10:0] ps2_key;
wire  [31:0] joystick_0, joystick_1, joystick_2, joystick_3;
wire [15:0] joystick_l_analog_0, joystick_l_analog_1;
wire [15:0] joystick_l_analog_2, joystick_l_analog_3;
wire [15:0] joystick_r_analog_0, joystick_r_analog_1;
wire [15:0] joystick_r_analog_2, joystick_r_analog_3;

wire        ioctl_download;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire [15:0] ioctl_index;
wire [31:0] tape_lba[2], disk_lba[3];
wire [2:0] disk_rd, disk_wr, disk_ack, disk_mounted;
wire [7:0] disk_buff_din[3];
wire printer_busy, printer_active, printer_stalled, printer_mounted;
wire [3:0] printer_error, printer_status;
assign tape_mounted = disk_mounted[1:0];
assign tape_ack = disk_ack[1:0];
assign disk_rd[1:0] = tape_rd;
assign disk_wr[1:0] = tape_wr;
genvar drive;
generate for (drive=0; drive<2; drive=drive+1) begin : tape_bus
    assign disk_lba[drive] = tape_lba[drive];
    assign disk_buff_din[drive] = tape_buff_din[drive];
end endgenerate
wire [1:0] tape_rd, tape_wr, tape_ack;
wire [13:0] tape_buff_addr;
wire [7:0] tape_buff_dout, tape_buff_din[2];
wire tape_buff_wr, tape_readonly;
wire [1:0] tape_mounted;
wire [63:0] tape_size;
wire tape_record_data, tape_record_enable, tape_playback_data, tape_playback_enable;
wire [1:0] tape_deck_busy, tape_deck_error, tape_deck_rewound;
wire [1:0] tape_deck_ended;
wire tape_ended = |tape_deck_ended;
wire tape_busy = |tape_deck_busy;
wire tape_error = |tape_deck_error;
wire tape_rewound = |tape_deck_rewound;
wire [15:0] menu_mask = {1'b0, !printer_mounted, !joystick_connected || !status[38], printer_error != 0, printer_busy && !printer_active, ~cart_loaded, printer_active, ~tape_busy,
                         !printer_busy && printer_error == 0 && printer_status == 2, !printer_busy, status[19],
                         !joystick_connected, 4'b0011};
reg info_req = 0;
reg [7:0] info = 0, pending_info = 0;
wire [5:0] sd_blk_cnt[3];
assign sd_blk_cnt[0] = 0;
assign sd_blk_cnt[1] = 0;
assign sd_blk_cnt[2] = 0;

hps_io #(.CONF_STR(CONF_STR), .CONF_STR_BRAM(1), .VDNUM(3)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(),

	.forced_scandoubler(),

	.buttons(buttons),
	.status(status),
	.RTC(RTC),
	.status_in(128'd0),
	.status_set(1'b0),
	.status_menumask(menu_mask),
	.info_req(info_req),
	.info(info),

	.img_mounted(disk_mounted),
	.img_readonly(tape_readonly),
	.img_size(tape_size),
	.sd_lba(disk_lba),
	.sd_blk_cnt(sd_blk_cnt),
	.sd_rd(disk_rd),
	.sd_wr(disk_wr),
	.sd_ack(disk_ack),
	.sd_buff_addr(tape_buff_addr),
	.sd_buff_dout(tape_buff_dout),
	.sd_buff_din(disk_buff_din),
	.sd_buff_wr(tape_buff_wr),

	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_index(ioctl_index),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.joystick_2(joystick_2),
	.joystick_3(joystick_3),
	.joystick_l_analog_0(joystick_l_analog_0),
	.joystick_l_analog_1(joystick_l_analog_1),
	.joystick_l_analog_2(joystick_l_analog_2),
	.joystick_l_analog_3(joystick_l_analog_3),
	.joystick_r_analog_0(joystick_r_analog_0),
	.joystick_r_analog_1(joystick_r_analog_1),
	.joystick_r_analog_2(joystick_r_analog_2),
	.joystick_r_analog_3(joystick_r_analog_3),
	.ps2_key(ps2_key)
);


wire clk_sys;
wire expander_modem_rxd, expander_modem_txd, expander_printer_txd;
assign UART_TXD = status[32] ? expander_printer_txd : expander_modem_txd;
assign expander_modem_rxd = status[32] ? 1'b1 : UART_RXD;
wire pll_locked;
pll pll
(
	.refclk(CLK_50M),
	.rst(1'b0),
	.outclk_0(clk_sys),
	.locked(pll_locked)
);

reg master_control = 0;
wire cart_dl = ioctl_download && (ioctl_index[7:0] == 8'd1);
// vbk downloads must not reset the machine
wire system_reset = RESET | status[0] | status[28] | buttons[1] |
                    (ioctl_download && (ioctl_index[7:0] != 8'd4) &&
                     !(status[24] && cart_dl)) | ~pll_locked;
wire power_cycle = RESET | status[0] | buttons[1] | ~pll_locked;
wire master_reset;
wire reset = system_reset | master_reset;

videobrain_reset reset_control (
    .clk(clk_sys), .reset(system_reset), .vblank(raw_vblank),
    .master_control(master_control), .menu_control(status[27]), .master_reset(master_reset)
);

wire boot_dl = ioctl_download && (ioctl_index == 16'd0);
wire source_dl = ioctl_download && (ioctl_index[7:0] == 8'd4);
wire apl_available, music_available, apl_load_error;
wire apl_symbols, source_busy, source_error, source_started, source_complete, source_aborted;
wire source_enabled = !OSD_STATUS || (status[31] && source_started);
wire source_music_playback = !status[18] || status[19];
wire apl_input_ready, apl_key_accepted;
wire [35:0] source_keys;
wire expander_dl = ioctl_download && ((ioctl_index == 16'd64) ||
                                    (ioctl_index[7:0] == 8'd2));

wire [7:0] dl_index = expander_dl           ? 8'd3 :
                      cart_dl               ? 8'd2 :
                      boot_dl               ? (ioctl_addr[11] ? 8'd1 : 8'd0) : 8'hff;

wire [15:0] dl_addr = (cart_dl | expander_dl) ? ioctl_addr[15:0] : {4'd0, ioctl_addr[11:0]};
wire        dl_wr   = (boot_dl | cart_dl | expander_dl) & ioctl_wr;


// 9 columns by 4 rows, bit = col * 4 + row, active high
reg [35:0] kbd_keys = 0;
reg [35:0] kbd_number_row = 0, kbd_number_pad = 0;
reg enter_key = 0, keypad_enter_key = 0, backspace_key = 0;
reg home_key = 0, end_key = 0, left_ctrl = 0, right_ctrl = 0;
reg enter_erase = 0, keypad_enter_erase = 0;
wire ctrl_held = left_ctrl | right_ctrl;
wire next_key = (enter_key && !enter_erase) | (keypad_enter_key && !keypad_enter_erase);
wire erase_key = (enter_key && enter_erase) | (keypad_enter_key && keypad_enter_erase);
wire [35:0] kbd_edit_keys = {backspace_key, 3'd0, home_key, 3'd0,
                            next_key, 3'd0, end_key, 7'd0, erase_key, 15'd0};
wire [35:0] kbd_matrix = kbd_keys | kbd_number_row | kbd_number_pad | kbd_edit_keys;

wire       key_pressed = ps2_key[9];
wire [8:0] key_code    = ps2_key[8:0];
reg        key_toggle  = 0;

always @(posedge clk_sys) begin
	key_toggle <= ps2_key[10];
	if (system_reset || status[29]) master_control <= 0;
	else if (key_toggle != ps2_key[10] && key_code == 'h076)
		master_control <= key_pressed;  // esc = master control
	if (system_reset) begin
		kbd_keys <= 0;
		kbd_number_row <= 0;
		kbd_number_pad <= 0;
		enter_key <= 0;
		keypad_enter_key <= 0;
		backspace_key <= 0;
		home_key <= 0;
		end_key <= 0;
		left_ctrl <= 0;
		right_ctrl <= 0;
		enter_erase <= 0;
		keypad_enter_erase <= 0;
	end
	else if (key_toggle != ps2_key[10]) begin
		case (key_code)
			'h043: kbd_keys[0]  <= key_pressed;  // i
			'h044: kbd_keys[1]  <= key_pressed;  // o
			'h04D: kbd_keys[2]  <= key_pressed;  // p
			'h04C: kbd_keys[3]  <= key_pressed;  // ;

			'h03C: kbd_keys[4]  <= key_pressed;  // u
			'h042: kbd_keys[5]  <= key_pressed;  // k
			'h04B: kbd_keys[6]  <= key_pressed;  // l
			'h041: kbd_keys[7]  <= key_pressed;  // ,

			'h035: kbd_keys[8]  <= key_pressed;  // y
			'h03B: kbd_keys[9]  <= key_pressed;  // j
			'h03A: kbd_keys[10] <= key_pressed;  // m
			'h012: kbd_keys[11] <= key_pressed;  // left shift
			'h059: kbd_keys[11] <= key_pressed;  // right shift

			'h02C: kbd_keys[12] <= key_pressed;  // t
			'h033: kbd_keys[13] <= key_pressed;  // h
			'h031: kbd_keys[14] <= key_pressed;  // n
			'h003: kbd_keys[15] <= key_pressed;  // f5 = erase/restart

			'h02D: kbd_keys[16] <= key_pressed;  // r
			'h034: kbd_keys[17] <= key_pressed;  // g
			'h032: kbd_keys[18] <= key_pressed;  // b
			'h029: kbd_keys[19] <= key_pressed;  // space = run/stop

			'h024: kbd_keys[20] <= key_pressed;  // e
			'h02B: kbd_keys[21] <= key_pressed;  // f
			'h02A: kbd_keys[22] <= key_pressed;  // v
			'h00C: kbd_keys[23] <= key_pressed;  // f4 = special/alarm

			'h01D: kbd_keys[24] <= key_pressed;  // w
			'h023: kbd_keys[25] <= key_pressed;  // d
			'h021: kbd_keys[26] <= key_pressed;  // c
			'h004: kbd_keys[27] <= key_pressed;  // f3 = next/clock

			'h015: kbd_keys[28] <= key_pressed;  // q
			'h01B: kbd_keys[29] <= key_pressed;  // s
			'h022: kbd_keys[30] <= key_pressed;  // x
			'h006: kbd_keys[31] <= key_pressed;  // f2 = previous/color

			'h01C: kbd_keys[32] <= key_pressed;  // a
			'h01A: kbd_keys[33] <= key_pressed;  // z
			'h04A: kbd_keys[34] <= key_pressed;  // / = ?
			'h005: kbd_keys[35] <= key_pressed;  // f1 = back/text
			// software controls shift and key meaning
			'h05A: begin
				enter_key <= key_pressed;
				if (key_pressed && !enter_key) enter_erase <= ctrl_held;
			end
			'h15A: begin
				keypad_enter_key <= key_pressed;
				if (key_pressed && !keypad_enter_key) keypad_enter_erase <= ctrl_held;
			end
			'h014: left_ctrl <= key_pressed;
			'h114: right_ctrl <= key_pressed;
			'h16C: home_key <= key_pressed;          // home = f2 = previous/color
			'h169: end_key <= key_pressed;           // end = f4 = special/alarm
			'h066: backspace_key <= key_pressed;     // backspace = f1 = back/text
			'h045: kbd_number_row[34] <= key_pressed;  // 0 = /
			'h070: kbd_number_pad[34] <= key_pressed;  // keypad 0 = /
			'h016: kbd_number_row[33] <= key_pressed;  // 1 = z
			'h069: kbd_number_pad[33] <= key_pressed;  // keypad 1 = z
			'h01E: kbd_number_row[30] <= key_pressed;  // 2 = x
			'h072: kbd_number_pad[30] <= key_pressed;  // keypad 2 = x
			'h026: kbd_number_row[26] <= key_pressed;  // 3 = c
			'h07A: kbd_number_pad[26] <= key_pressed;  // keypad 3 = c
			'h025: kbd_number_row[29] <= key_pressed;  // 4 = s
			'h06B: kbd_number_pad[29] <= key_pressed;  // keypad 4 = s
			'h02E: kbd_number_row[25] <= key_pressed;  // 5 = d
			'h073: kbd_number_pad[25] <= key_pressed;  // keypad 5 = d
			'h036: kbd_number_row[21] <= key_pressed;  // 6 = f
			'h074: kbd_number_pad[21] <= key_pressed;  // keypad 6 = f
			'h03D: kbd_number_row[24] <= key_pressed;  // 7 = w
			'h06C: kbd_number_pad[24] <= key_pressed;  // keypad 7 = w
			'h03E: kbd_number_row[20] <= key_pressed;  // 8 = e
			'h075: kbd_number_pad[20] <= key_pressed;  // keypad 8 = e
			'h046: kbd_number_row[16] <= key_pressed;  // 9 = r
			'h07D: kbd_number_pad[16] <= key_pressed;  // keypad 9 = r
			default: ;
		endcase
	end
end

wire [63:0] joy_pots;
wire [3:0] joy_fire;
wire [13:0] joy_timer_base;
wire [6:0] joy_timer_step;
wire joy_timer_auto;
wire joy_calibrating;

videobrain_joystick joysticks (
	.clk(clk_sys),
	.reset(reset | cart_dl | status[28]),
	.frame_tick(vid_vs && !source_vs_d),
	.calibrate(status[20]),
	.calibrating(joy_calibrating),
	.enabled(joystick_connected),
	.relative_mode(status[38]),
	.relative_speed(status[40:39]),
	.paired(status[17:16]),
	.preset(status[15:14]),
	.buttons({joystick_3, joystick_2, joystick_1, joystick_0}),
	.left_sticks({joystick_l_analog_3, joystick_l_analog_2, joystick_l_analog_1, joystick_l_analog_0}),
	.right_sticks({joystick_r_analog_3, joystick_r_analog_2, joystick_r_analog_1, joystick_r_analog_0}),
	.pots(joy_pots),
	.fire(joy_fire),
	.timer_base(joy_timer_base),
	.timer_step(joy_timer_step),
	.timer_auto(joy_timer_auto)
);


wire       ce_pix;
wire       vid_field;
wire [7:0] vid_r, vid_g, vid_b;
wire       vid_de, vid_hs, vid_vs, vid_hb, vid_vb, raw_vblank;
wire [1:0] audio_code;
wire audio_stb;

reg source_vs_d = 0;
always @(posedge clk_sys) source_vs_d <= vid_vs;

reg source_started_d = 0, source_complete_d = 0, source_error_d = 0;
reg source_aborted_d = 0, joy_calibrating_d = 0;
reg tape_busy_d = 0, tape_error_d = 0;
reg [3:0] printer_status_d = 0, printer_error_d = 0;
reg printer_notice_error = 0;
reg [7:0] printer_notice = 0;
reg printer_query_d = 0;
wire [7:0] printer_message = printer_error == 2 ? 8'd20 :
    printer_error == 3 ? 8'd21 : printer_error == 4 ? 8'd22 :
    printer_error == 5 ? 8'd23 : printer_error == 6 ? 8'd24 :
    printer_error == 7 ? 8'd25 : printer_error == 9 ? 8'd26 :
    printer_error == 10 ? 8'd27 : 8'd11 + {4'd0,printer_status};
reg [5:0] tape_info_frames = 0;
always @(posedge clk_sys) begin
    printer_status_d <= printer_status;
    printer_error_d <= printer_error;
    printer_query_d <= status[36];
    if (reset || status[22]) begin
        printer_notice <= 0;
        printer_notice_error <= 0;
    end else if ((printer_status != printer_status_d || printer_error != printer_error_d ||
                 status[36] && !printer_query_d) &&
                (!printer_notice_error || status[36] && !printer_query_d)) begin
        printer_notice <= printer_message;
        printer_notice_error <= printer_error != 0;
    end
	source_started_d <= source_started;
	source_complete_d <= source_complete;
	source_error_d <= source_error;
	source_aborted_d <= source_aborted;
	joy_calibrating_d <= joy_calibrating;
	tape_busy_d <= tape_busy;
	tape_error_d <= tape_error;
	info_req <= 0;
	if (reset || status[22]) begin
		pending_info <= 0;
		tape_info_frames <= 0;
	end else begin
		// defer until menu close
		if (!OSD_STATUS && vid_vs && !source_vs_d) begin
			if (printer_notice != 0) begin
                info <= printer_notice;
                info_req <= 1;
                printer_notice <= 0;
                printer_notice_error <= 0;
            end else if (pending_info != 0) begin
				if (pending_info != 9 || joy_calibrating) begin
					info <= pending_info;
					info_req <= 1;
				end
				pending_info <= 0;
				tape_info_frames <= 0;
			end else if (joy_calibrating || (tape_busy && !tape_error)) begin
				if (tape_info_frames == 59) begin
					info <= joy_calibrating ? 8'd9 : 8'd5;
					info_req <= 1;
					tape_info_frames <= 0;
				end else tape_info_frames <= tape_info_frames + 1'b1;
			end else tape_info_frames <= 0;
		end
		if (source_started && !source_started_d) pending_info <= 1;
		if (source_complete && !source_complete_d) pending_info <= 7;
		if (source_aborted && !source_aborted_d) pending_info <= 8;
		if (joy_calibrating && !joy_calibrating_d) pending_info <= 9;
		if (tape_busy && !tape_busy_d) pending_info <= 5;
		if (!tape_busy && tape_busy_d && !tape_error && pending_info != 10) pending_info <= 6;
		if (tape_ended) pending_info <= 10;
		if (tape_rewound) pending_info <= 4;
		if (source_error && !source_error_d) pending_info <= 2;
		if (tape_error && !tape_error_d) pending_info <= 3;
	end
end

reg [1:0] video_output = 0, requested_output = 0;
reg apply_video_d = 0, apply_video_pending = 0;
reg [2:0] startup_status_word = 0;
reg startup_status_cmd = 0, startup_video_received = 0, startup_video_applied = 0;
reg [1:0] startup_video_output = 0;
wire progressive = video_output != 0;
wire linedouble = video_output == 2;
reg field_d = 0;
always @(posedge clk_sys) begin
	if (!HPS_BUS[34]) begin
		startup_status_word <= 0;
		startup_status_cmd <= 0;
	end else if (HPS_BUS[33] && !startup_video_received) begin
		if (startup_status_word == 0) startup_status_cmd <= HPS_BUS[31:16] == 16'h001e;
		if (startup_status_word == 3 && startup_status_cmd) begin
			startup_video_output <= HPS_BUS[26:25] == 3 ? 2'd0 : HPS_BUS[26:25];
			startup_video_received <= 1;
		end
		if (startup_status_word != 7) startup_status_word <= startup_status_word + 1'b1;
	end
	field_d <= vid_field;
	apply_video_d <= status[43];
	if (RESET) begin
		video_output <= 0;
		requested_output <= 0;
		apply_video_pending <= 0;
	end else begin
		if (startup_video_received && !startup_video_applied) begin
			requested_output <= startup_video_output;
			apply_video_pending <= 1;
			startup_video_applied <= 1;
		end
		if (vid_field != field_d && apply_video_pending) begin
			video_output <= requested_output;
			apply_video_pending <= 0;
		end
		if (status[43] && !apply_video_d) begin
			requested_output <= status[42:41] == 3 ? 2'd0 : status[42:41];
			apply_video_pending <= 1;
		end
	end
end

apl_source_loader source_loader (
	.clk(clk_sys),
	.reset(reset),
	.frame_tick(vid_vs && !source_vs_d),
	.download(source_dl),
	.wr(ioctl_wr),
	.addr(ioctl_addr),
	.data(ioctl_dout),
	.available(apl_available),
	.music_available(music_available),
	.symbols(apl_symbols),
	.input_ready(apl_input_ready),
	.key_accepted(apl_key_accepted),
	.music_playback(source_music_playback),
	.auto_repeat(status[19]),
	.enabled(source_enabled),
	.cancel(|kbd_matrix),
	.rtc(RTC),
	.rtc_time(rtc_time),
	.rtc_time_valid(rtc_time_valid),
	.busy(source_busy),
	.started(source_started),
	.complete(source_complete),
	.aborted(source_aborted),
	.error(source_error),
	.keys(source_keys)
);

videobrain_printer_capture printer_capture (
    .clk(clk_sys), .reset(reset), .serial_in(expander_printer_txd),
    .baud110(status[33]), .start(status[34]), .stop(status[35]),
    .img_mounted(disk_mounted[2]), .img_readonly(tape_readonly), .img_size(tape_size),
    .busy(printer_busy), .active(printer_active), .stalled(printer_stalled), .mounted(printer_mounted),
    .error(printer_error), .status_code(printer_status),
    .sd_lba(disk_lba[2]), .sd_rd(disk_rd[2]), .sd_wr(disk_wr[2]), .sd_ack(disk_ack[2]),
    .sd_buff_addr(tape_buff_addr[8:0]), .sd_buff_dout(tape_buff_dout),
    .sd_buff_din(disk_buff_din[2]), .sd_buff_wr(tape_buff_wr)
);

videobrain_tapes tapes (
	.clk(clk_sys), .reset(reset),
	.img_mounted(tape_mounted), .img_readonly(tape_readonly), .img_size(tape_size),
	.rewind({status[30], status[23]}),
	.record_data(tape_record_data), .record_enable(tape_record_enable),
	.playback_enable(tape_playback_enable), .playback_data(tape_playback_data),
	.busy(tape_deck_busy), .error(tape_deck_error), .rewound(tape_deck_rewound),
	.ended(tape_deck_ended),
	.sd_lba(tape_lba), .sd_rd(tape_rd), .sd_wr(tape_wr), .sd_ack(tape_ack),
	.sd_buff_addr(tape_buff_addr[8:0]), .sd_buff_dout(tape_buff_dout),
	.sd_buff_din(tape_buff_din), .sd_buff_wr(tape_buff_wr)
);

videobrain_core core
(
	.clk        (clk_sys),
	.reset_na   (~reset),
	.power_cycle(power_cycle),
	.rtc_clock_enable(status[44]),
	.rtc_time_valid(rtc_time_valid),
	.rtc_time(rtc_time),
	.timing_reset_na(~system_reset),
	.progressive(progressive),

	.kbd_matrix (source_busy ? source_keys : kbd_matrix),
	.joy_fire   (joy_fire),
	.joy_pots   (joy_pots),
	.joy_connected (joystick_connected),
	.joy_timer_base (joy_timer_base),
	.joy_timer_step (joy_timer_step),
	.joy_timer_curve (1'b0),
	.joy_timer_auto (joy_timer_auto),
	.audio_code (audio_code),
	.audio_stb  (audio_stb),
	.joy_enable (),
	.expander_record_data (tape_record_data),
	.expander_record_enable (tape_record_enable),
	.expander_playback_data (tape_playback_data),
	.expander_playback_enable (tape_playback_enable),
	.expander_modem_rxd (expander_modem_rxd),
	.expander_modem_txd (expander_modem_txd),
	.expander_printer_txd (expander_printer_txd),
	.f8_po_a_n  (),
	.f8_po_b_n  (),

	.brclk_ena  (),
	.ce_pix     (ce_pix),
	.vid_idx    (),
	.vid_r      (vid_r),
	.vid_g      (vid_g),
	.vid_b      (vid_b),
	.vid_de     (vid_de),
	.vid_hs     (vid_hs),
	.vid_vs     (vid_vs),
	.vid_hb     (vid_hb),
	.vid_vb     (vid_vb),

	.fifo_valid (),
	.fifo_level (),

	.hblank     (),
	.vblank     (raw_vblank),
	.burst      (),
	.csync      (),
	.scanline   (),
	.field      (vid_field),
	.hpos       (),
	.vpos       (),

	.final_mod  (),
	.background (),
	.x_zoom     (),
	.y_zoom     (),
	.video_en   (),

	.dl_addr    (dl_addr),
	.dl_data    (ioctl_dout),
	.dl_wr      (dl_wr),
	.dl_index   (dl_index),
	.cart_unload(status[28]),
	.cart_loaded(cart_loaded),
	.unknown_cart_profile ({5'd0, status[11:9]}),
	.infoman_printer_fix(status[37]),
	.apl_available (apl_available),
	.music_available (music_available),
	.apl_load_error (apl_load_error),
	.apl_symbols (apl_symbols),
	.apl_input_ready (apl_input_ready),
	.apl_key_accepted (apl_key_accepted),

	.pc0        (),
	.pc1        (),
	.dc0        ()
);


assign CLK_VIDEO = clk_sys;

wire sd_ce, sd_hs, sd_vs, sd_hb, sd_vb;
wire [7:0] sd_r, sd_g, sd_b;
videobrain_linedoubler linedoubler (
	.clk(clk_sys),
	.reset(RESET | !linedouble),
	.ce_pix(ce_pix),
	.r(vid_r), .g(vid_g), .b(vid_b),
	.hs(vid_hs), .vs(vid_vs), .hb(vid_hb), .vb(vid_vb),
	.ce_out(sd_ce),
	.r_out(sd_r), .g_out(sd_g), .b_out(sd_b),
	.hs_out(sd_hs), .vs_out(sd_vs), .hb_out(sd_hb), .vb_out(sd_vb)
);

wire out_ce = linedouble ? sd_ce : ce_pix;
wire out_hs = linedouble ? sd_hs : vid_hs;
wire out_vs = linedouble ? sd_vs : vid_vs;
wire out_hb = linedouble ? sd_hb : vid_hb;
wire out_vb = linedouble ? sd_vb : vid_vb;
wire [7:0] out_r = linedouble ? sd_r : vid_r;
wire [7:0] out_g = linedouble ? sd_g : vid_g;
wire [7:0] out_b = linedouble ? sd_b : vid_b;

video_freak video_freak
(
	.CLK_VIDEO(CLK_VIDEO),
	.CE_PIXEL(out_ce),
	.VGA_VS(out_vs & (progressive | ~vid_field)),
	.HDMI_WIDTH(HDMI_WIDTH),
	.HDMI_HEIGHT(HDMI_HEIGHT),
	.VGA_DE(),
	.VIDEO_ARX(VIDEO_ARX),
	.VIDEO_ARY(VIDEO_ARY),
	.VGA_DE_IN(linedouble ? ~(out_hb | out_vb) : vid_de),
	.ARX(!ar ? 12'd4 : {10'd0, ar - 2'd1}),
	.ARY(!ar ? 12'd3 : 12'd0),
	.CROP_SIZE(12'd0),
	.CROP_OFF(5'd0),
	.SCALE(status[125:123])
);

assign VGA_SL = 2'b00;

video_mixer #(.GAMMA(0)) video_mixer
(
	.CLK_VIDEO(CLK_VIDEO),
	.CE_PIXEL(CE_PIXEL),
	.ce_pix(out_ce),

	.scandoubler(1'b0),
	.hq2x(1'b0),

	.gamma_bus(),

	.R(out_r),
	.G(out_g),
	.B(out_b),

	.HSync(out_hs),
	.VSync(out_vs),
	.HBlank(out_hb),
	.VBlank(out_vb),

	.VGA_R(VGA_R),
	.VGA_G(VGA_G),
	.VGA_B(VGA_B),
	.VGA_VS(VGA_VS),
	.VGA_HS(VGA_HS),
	.VGA_DE(VGA_DE)
);


wire [15:0] audio_sample;

videobrain_audio audio
(
	.clk(clk_sys),
	.reset(reset),
	.code(audio_code),
	.stb(audio_stb),
	.sample(audio_sample)
);

assign AUDIO_L = audio_sample;
assign AUDIO_R = audio_sample;

assign LED_USER = ioctl_download | source_busy | tape_busy | printer_busy;

endmodule
