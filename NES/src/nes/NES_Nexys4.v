// Copyright (c) 2012-2013 Ludvig Strigeus
// modifications Piotr Gozdur <piotr_go>
// This program is GPL Licensed. See COPYING for the full license.

`timescale 1ns / 1ps


module MemoryController(
                 input clk,
                 input run_mem,
                 input run_nes,
                 input read_a,             // Set to 1 to read from RAM
                 input read_b,             // Set to 1 to read from RAM
                 input write,              // Set to 1 to write to RAM
                 input [21:0] addr,        // Address to read / write
                 input [7:0] din,          // Data to write
                 output reg [7:0] dout_a,  // Last read data a
                 output reg [7:0] dout_b,  // Last read data b

                 output MemCE,
                 output MemWE,
                 output [21:0] MemAdr,
                 input [7:0] MemDI,
                 output [7:0] MemDO,

		input loader_done,
		input [7:0] chrOffset);

assign MemAdr = !loader_done ? addr[3:0] : addr[21] ? (addr[20:0] + {chrOffset[6:0], 14'h10}): (addr[20:0] + 20'h10);
assign MemCE = run_mem;
assign MemWE = write;
assign MemDO = din;

reg r_read_a;
  
always @(posedge clk) begin
	if(run_mem) r_read_a <= read_a;
	else if(run_nes) begin
		if(r_read_a) dout_a <= MemDI;
		else dout_b <= MemDI;
	end
end

endmodule  // MemoryController


module GameLoader(input clk, input run_nes, input reset,
                  output reg [21:0] mem_addr = 0, input [7:0] indata,
                  output [31:0] mapper_flags, output reg done = 0, output [7:0] chrOffset);

reg [3:0] ctr;
reg [7:0] ines[0:15]; // 16 bytes of iNES header
wire [7:0] prgrom = ines[4];
wire [7:0] chrrom = ines[5];

assign chrOffset = ines[4];

wire [2:0] prg_size =	prgrom <= 1  ? 0 :
			prgrom <= 2  ? 1 : 
			prgrom <= 4  ? 2 : 
			prgrom <= 8  ? 3 : 
			prgrom <= 16 ? 4 : 
			prgrom <= 32 ? 5 : 
			prgrom <= 64 ? 6 : 7;

wire [2:0] chr_size =	chrrom <= 1  ? 0 : 
			chrrom <= 2  ? 1 : 
			chrrom <= 4  ? 2 : 
			chrrom <= 8  ? 3 : 
			chrrom <= 16 ? 4 : 
			chrrom <= 32 ? 5 : 
			chrrom <= 64 ? 6 : 7;

wire [7:0] mapper = {ines[7][7:4], ines[6][7:4]};
wire has_chr_ram = (chrrom == 0);
assign mapper_flags = {16'b0, has_chr_ram, ines[6][0], chr_size, prg_size, mapper};

always @(posedge clk) begin
	if(reset) begin
		done <= 0;
		ctr <= 0;
		mem_addr <= 0;
	end
	else if(run_nes && !done) begin
		ines[ctr] <= indata;
		if(ctr == 4'b1111) done <= 1;
		ctr <= ctr + 1;
		mem_addr <= mem_addr + 1;
	end
end

endmodule


module NES_Nexys4(input clk,
                 input CPU_RESET,
                 input [4:0] BTN,
                 input [15:0] SW,
                 output [7:0] SSEG_CA,
                 output [7:0] SSEG_AN,
                 // VGA
                 output vga_v, output vga_h, output [4:0] vga_r, output [4:0] vga_g, output [4:0] vga_b, output [9:0] vga_hcounter, output [9:0] vga_vcounter,
                 // Memory
                 output MemCE,          // Output Enable. Enable when Low.
                 output MemWE,          // Write Enable. WRITE when Low.
                 output [21:0] MemAdr,
                 input [7:0] MemDI,
                 output [7:0] MemDO,

                 input [7:0] joyA,
                 input [7:0] joyB,

                 output [15:0] sample
                 );

  // NES Palette -> RGB332 conversion
  reg [14:0] pallut[0:63];
  initial $readmemh("../src/nes/nes_palette.txt", pallut);

  wire [8:0] cycle;
  wire [8:0] scanline;
//  wire [15:0] sample;
  wire [5:0] color;
  wire joypad_strobe;
  wire [1:0] joypad_clock;
  wire [21:0] memory_addr;
  wire memory_read_cpu, memory_read_ppu;
  wire memory_write;
  wire [7:0] memory_din_cpu, memory_din_ppu;
  wire [7:0] memory_dout;
  reg [7:0] joypad_bits, joypad_bits2;
  reg [1:0] last_joypad_clock;
  wire [31:0] dbgadr;
  wire [1:0] dbgctr;

  always @(posedge clk) begin
    if (joypad_strobe) begin
      joypad_bits <= joyA;
      joypad_bits2 <= joyB;
    end
    if (!joypad_clock[0] && last_joypad_clock[0])
      joypad_bits <= {1'b0, joypad_bits[7:1]};
    if (!joypad_clock[1] && last_joypad_clock[1])
      joypad_bits2 <= {1'b0, joypad_bits2[7:1]};
    last_joypad_clock <= joypad_clock;
  end
  
  reg [1:0] nes_ce;
  wire run_mem = (nes_ce == 0);
  wire run_nes = (nes_ce == 3);

  wire [21:0] loader_addr;
  wire loader_reset = CPU_RESET;
  wire [31:0] mapper_flags;
  wire loader_done;
  wire [7:0] chrOffset;

  GameLoader loader(clk, run_nes, loader_reset,
		loader_addr, MemDI,
		mapper_flags, loader_done, chrOffset);

  // NES is clocked at every 4th cycle.
  always @(posedge clk) begin
	if(CPU_RESET) nes_ce <= 0;
	nes_ce <= nes_ce + 1;
  end
    
  NES nes(clk, !loader_done, run_nes,
          mapper_flags,
          sample, color,
          joypad_strobe, joypad_clock, {joypad_bits2[0], joypad_bits[0]},
          SW[4:0],
          memory_addr,
          memory_read_cpu, memory_din_cpu,
          memory_read_ppu, memory_din_ppu,
          memory_write, memory_dout,
          cycle, scanline,
          dbgadr,
          dbgctr);

  // This is the memory controller to access the board's SDRAM
  MemoryController memory(clk, run_mem, run_nes,
                          memory_read_cpu && run_mem, 
                          memory_read_ppu && run_mem,
                          memory_write && run_mem,
                          loader_done ? memory_addr : loader_addr,
                          memory_dout,
                          memory_din_cpu,
                          memory_din_ppu,
                          MemCE, MemWE, MemAdr, MemDI, MemDO, loader_done, chrOffset);

  wire [14:0] doubler_pixel;
  wire doubler_sync;
  wire [9:0] doubler_x;
  
  VgaDriver vga(clk, vga_h, vga_v, vga_r, vga_g, vga_b, vga_hcounter, vga_vcounter, doubler_x, doubler_pixel, doubler_sync, SW[6]);
  
  wire [14:0] pixel_in = pallut[color];
  Hq2x hq2x(clk, pixel_in, SW[5], 
            scanline[8],        // reset_frame
            (cycle[8:3] == 42), // reset_line
            doubler_x,          // 0-511 for line 1, or 512-1023 for line 2.
            doubler_sync,       // new frame has just started
            doubler_pixel);     // pixel is outputted

endmodule
