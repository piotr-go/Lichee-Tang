/*
  Copyright (C) 2018 Piotr Gozdur <piotr_go>.

  This program is free software; you can redistribute it and/or
  modify it under the terms of the GNU General Public License
  as published by the Free Software Foundation; either version 2
  of the License.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.
*/


`timescale 1 ps / 1 ps

module fpga_nes (
	input  wire SYS_CLK,
//	input  wire SYS_RST,

	output  wire LED1_OUT,
	output  wire LED2_OUT,

	output wire [7:2] VGA_R,
	output wire [7:2] VGA_G,
	output wire [7:2] VGA_B,
	output wire VGA_H,
	output wire VGA_V,
	output wire VGA_CLK,

	output wire AUD_XCK,
	output wire AUD_BCLK,
	output wire AUD_DACLRCK,
	output wire AUD_DACDAT,

	input	wire [6:0] J1,
	input	wire [6:0] J2,

	input	wire PS2KD,
	input	wire PS2KC
);

assign LED2_OUT = 1'bZ;
assign LED1_OUT = 1'b0;

//******************************************************************//

	wire bufpll_lock, pclk5x, pclk, pclkx2, pclkx2d;

	pll_nes pll
	(
		.refclk		(SYS_CLK),
		.extlock	(bufpll_lock),
		.clk0_out	(pclk5x),
		.clk1_out	(pclkx2),
		.clk2_out	(pclkx2d),
		.clk3_out	(pclk)
	);

	reg [3:0] reset_cnt1, reset_cnt2;
	always @ (posedge pclk) begin
		if(~bufpll_lock)
			reset_cnt1 <= 4'd0;
		else begin
			if(reset_cnt1 < 4'd15) reset_cnt1 <= reset_cnt1 + 4'd1;
		end

		if(~bufpll_lock || (reset_cnt1 < 4'd15))
			reset_cnt2 <= 4'd0;
		else begin
			if(reset_cnt2 < 4'd15) reset_cnt2 <= reset_cnt2 + 4'd1;
		end
	end
	wire reset = (~bufpll_lock) || (reset_cnt1 < 4'd15);
	wire reset2 = (~bufpll_lock) || (reset_cnt2 < 4'd15);
	
//******************************************************************//

	// SDRAM
	wire [31:0]	SDRAM_DQ; // SDRAM Data bus 32 Bits
	wire [10:0]	SDRAM_A; // SDRAM Address bus 11 Bits
	wire [3:0]	SDRAM_DQM; // SDRAM Low-byte Data Mask
	wire		SDRAM_nWE; // SDRAM Write Enable
	wire		SDRAM_nCAS; // SDRAM Column Address Strobe
	wire		SDRAM_nRAS; // SDRAM Row Address Strobe
	wire [1:0]	SDRAM_BA; // SDRAM Bank Address

	EG_PHY_SDRAM_2M_32 U_EG_PHY_SDRAM_2M_32(
		.clk(pclkx2d),
		.ras_n(SDRAM_nRAS),
		.cas_n(SDRAM_nCAS),
		.we_n(SDRAM_nWE),
		.addr(SDRAM_A),
		.ba(SDRAM_BA),
		.dq(SDRAM_DQ),
		.cke(1'b1),
		.dm0(SDRAM_DQM[0]),
		.dm1(SDRAM_DQM[1]),
		.dm2(SDRAM_DQM[2]),
		.dm3(SDRAM_DQM[3]),
		.cs_n(1'b0)
	);

	wire [21:0] RAM_A;
	wire [7:0] RAM_DO;
	wire [7:0] RAM_DI;
	wire RAM_CE, RAM_WE;

	SDRAM_ctrl(
		.reset(reset),
		.clk(pclkx2),

		.CE(RAM_CE),
		.WE(RAM_WE),
		.Addr(RAM_A),
		.RdData(RAM_DI),
		.WrData(RAM_DO),

		// SDRAM
		.SDRAM_WEn(SDRAM_nWE),
		.SDRAM_CASn(SDRAM_nCAS),
		.SDRAM_RASn(SDRAM_nRAS),
		.SDRAM_A(SDRAM_A),
		.SDRAM_BA(SDRAM_BA),
		.SDRAM_DQM(SDRAM_DQM),
		.SDRAM_DQ(SDRAM_DQ)
	);

//******************************************************************//

	wire [7:0] joyA, joyB;

	ps2(
		.clk(pclk),
		.reset(reset),

		.PS2KD(PS2KD),
		.PS2KC(PS2KC),

		.joyA(joyA),
		.joyB(joyB)
	);


	wire [15:0] audio;
	wire VGA_HSYNC, VGA_VSYNC;
	wire [7:3] red_data, green_data, blue_data;
	//wire [10:0] hcnt, vcnt;

	NES_Nexys4 (
		.clk(pclk),
		.CPU_RESET(reset2),
		.BTN(5'b00000),
		.SW({10'b0000000000, 1'b1, 5'b11111}),

		// VGA interface
		.vga_h(VGA_HSYNC),
		.vga_v(VGA_VSYNC),
		.vga_r(red_data[7:3]),
		.vga_g(green_data[7:3]),
		.vga_b(blue_data[7:3]),
		//.vga_hcounter(hcnt),
		//.vga_vcounter(vcnt),

		// joystick interface
		.joyA(joyA),
		.joyB(joyB),

		.sample(audio),

		.MemAdr(RAM_A),
		.MemDI(RAM_DI),
		.MemDO(RAM_DO),
		.MemCE(RAM_CE),
		.MemWE(RAM_WE)
	);

	assign VGA_R[7:2] = {red_data[7:3], 1'b0};
	assign VGA_G[7:2] = {green_data[7:3], 1'b0};
	assign VGA_B[7:2] = {blue_data[7:3], 1'b0};
	assign VGA_H = VGA_HSYNC;
	assign VGA_V = VGA_VSYNC;
	assign VGA_CLK = ~pclk;

	reg [15:0] rd, ld;
	reg [7:0] a_cnt;
	reg i2s_dat;
	always @ (posedge pclk) begin
		a_cnt <= a_cnt + 1'b1;

		if(a_cnt == 8'hFF) begin
			rd <= audio-16'h8000;
			ld <= audio-16'h8000;
		end

		if(a_cnt[2:0] == 3'd7) i2s_dat <= a_cnt[7] ? ld[4'd15 - a_cnt[6:3]] : rd[4'd15 - a_cnt[6:3]];
	end

	assign AUD_XCK = a_cnt[0];
	assign AUD_BCLK = a_cnt[2];
	assign AUD_DACLRCK = a_cnt[7];
	assign AUD_DACDAT = i2s_dat;
endmodule




module pll_nes(refclk,
		extlock,
		clk0_out,
		clk1_out,
		clk2_out,
		clk3_out);

	input refclk;
	output extlock;
	output clk0_out;
	output clk1_out;
	output clk2_out;
	output clk3_out;

	wire clk0_buf;

	EG_LOGIC_BUFG bufg_feedback( .i(clk0_buf), .o(clk0_out) );

	EG_PHY_PLL #(.DPHASE_SOURCE("DISABLE"),
		.DYNCFG("DISABLE"),
		.FIN("24.000"),
		.FEEDBK_MODE("NORMAL"),
		.FEEDBK_PATH("CLKC0_EXT"),
		.STDBY_ENABLE("DISABLE"),
		.PLLRST_ENA("DISABLE"),
		.SYNC_ENABLE("ENABLE"),
		.DERIVE_PLL_CLOCKS("DISABLE"),
		.GEN_BASIC_CLOCK("DISABLE"),
		.GMC_GAIN(6),
		.ICP_CURRENT(3),
		.KVCO(6),
		.LPF_CAPACITOR(3),
		.LPF_RESISTOR(2),
		.REFCLK_DIV(14),
		.FBCLK_DIV(63),
		.CLKC0_ENABLE("ENABLE"),
		.CLKC0_DIV(8),
		.CLKC0_CPHASE(8),
		.CLKC0_FPHASE(0),
		.CLKC1_ENABLE("ENABLE"),
		.CLKC1_DIV(20),
		.CLKC1_CPHASE(20),
		.CLKC1_FPHASE(0),
		.CLKC2_ENABLE("ENABLE"),
		.CLKC2_DIV(20),
		.CLKC2_CPHASE(17),
		.CLKC2_FPHASE(4),
		.CLKC3_ENABLE("ENABLE"),
		.CLKC3_DIV(40),
		.CLKC3_CPHASE(40),
		.CLKC3_FPHASE(0)	)
	pll_inst (.refclk(refclk),
		.reset(1'b0),
		.stdby(1'b0),
		.extlock(extlock),
		.psclk(1'b0),
		.psdown(1'b0),
		.psstep(1'b0),
		.psclksel(3'b000),
		.psdone(open),
		.dclk(1'b0),
		.dcs(1'b0),
		.dwe(1'b0),
		.di(8'b00000000),
		.daddr(6'b000000),
		.do({open, open, open, open, open, open, open, open}),
		.fbclk(clk0_out),
		.clkc({open, clk3_out, clk2_out, clk1_out, clk0_buf}));

endmodule




module ps2(
	input clk,
	input reset,

	input PS2KD,
	input PS2KC,

	output [7:0] joyA,
	output [7:0] joyB
);

	reg [1:0] CKr;
	reg [3:0] bit_cnt = 4'd0;
	reg [10:0] tWord;

	reg [15:0] timeout;

	reg [15:0] data_outT1 = 16'h0;

	reg [8:0] joy = 9'h000;

	always @(posedge clk) begin
		if(reset) begin
			bit_cnt <= 4'd0;
			data_outT1 <= 16'h0;
			joy <= 9'h000;
		end
		else begin
			CKr <= {CKr[0], PS2KC};

			if(CKr[1:0]==2'b01) begin
				timeout <= 16'hFFFF;

				if(bit_cnt == 4'd10) bit_cnt <= 4'd0;
				else bit_cnt <= bit_cnt + 4'd1;

				tWord <= {PS2KD, tWord[10:1]};
				if(bit_cnt == 4'd9) begin
					if(tWord[10]) data_outT1 <= {data_outT1[7:0], tWord[10:3]};
					else begin
						if(tWord[10:3] == 8'h74) joy[7] <= (data_outT1[15:0] == 16'h00E0) ? 1'b1 : 1'b0;
						else if(tWord[10:3] == 8'h6B) joy[6] <= (data_outT1[15:0] == 16'h00E0) ? 1'b1 : 1'b0;
						else if(tWord[10:3] == 8'h72) joy[5] <= (data_outT1[15:0] == 16'h00E0) ? 1'b1 : 1'b0;
						else if(tWord[10:3] == 8'h75) joy[4] <= (data_outT1[15:0] == 16'h00E0) ? 1'b1 : 1'b0;
						else if(tWord[10:3] == 8'h2A) joy[0] <= (data_outT1[15:0] == 16'h0000) ? 1'b1 : 1'b0;
						else if(tWord[10:3] == 8'h21) joy[1] <= (data_outT1[15:0] == 16'h0000) ? 1'b1 : 1'b0;
						else if(tWord[10:3] == 8'h22) joy[3] <= (data_outT1[15:0] == 16'h0000) ? 1'b1 : 1'b0;
						else if(tWord[10:3] == 8'h1A) joy[2] <= (data_outT1[15:0] == 16'h0000) ? 1'b1 : 1'b0;
						else if(tWord[10:3] == 8'h16) joy[8] <= 1'b0;
						else if(tWord[10:3] == 8'h1E) joy[8] <= 1'b1;
						data_outT1 <= 16'h0;
					end
				end
			end
			else begin
				if(timeout) timeout <= timeout - 16'h1;
				else bit_cnt <= 4'd0;
			end
		end
	end

	assign joyA = (joy[8] == 1'b0) ? joy[7:0] : 8'h00;
	assign joyB = (joy[8] == 1'b1) ? joy[7:0] : 8'h00;
endmodule
