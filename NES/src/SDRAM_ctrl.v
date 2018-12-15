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


module SDRAM_ctrl(
	input reset,
	input clk,

	input CE,
	input WE,
	input [22:0] Addr,
	output reg [7:0] RdData,
	input [7:0] WrData,

	output SDRAM_WEn, SDRAM_CASn, SDRAM_RASn,
	output reg [10:0] SDRAM_A,
	output reg [1:0] SDRAM_BA,
	output reg [3:0] SDRAM_DQM = 4'b1111,
	inout [31:0] SDRAM_DQ
);

localparam [2:0] SDRAM_CMD_LOADMODE  = 3'b000;
localparam [2:0] SDRAM_CMD_REFRESH   = 3'b001;
localparam [2:0] SDRAM_CMD_PRECHARGE = 3'b010;
localparam [2:0] SDRAM_CMD_ACTIVE    = 3'b011;
localparam [2:0] SDRAM_CMD_WRITE     = 3'b100;
localparam [2:0] SDRAM_CMD_READ      = 3'b101;
localparam [2:0] SDRAM_CMD_NOP       = 3'b111;

reg [2:0] SDRAM_CMD = SDRAM_CMD_NOP;
assign {SDRAM_RASn, SDRAM_CASn, SDRAM_WEn} = SDRAM_CMD;
reg [3:0] state=4'd0;
reg [5:0] refresh;

reg [9:0] AddrL;
reg [3:0] WrReqL;
reg [7:0] WrDataL;

always @(posedge clk) begin
	if(reset) begin
		SDRAM_CMD <= SDRAM_CMD_NOP;
		SDRAM_BA <= 0;
		SDRAM_A <= 0;
		SDRAM_DQM <= 4'b1111;
		WrReqL <= 0;
		state <= 0;
	end
	else begin
		case(state)
			4'd0: begin
				if(CE) begin
					SDRAM_CMD <= SDRAM_CMD_ACTIVE;	// activate
					SDRAM_BA <= Addr[22:21];	// bank
					SDRAM_A <= Addr[20:10];		// row
					SDRAM_DQM <= 4'b1111;
					AddrL <= Addr[9:0];

					if(WE == 1'b0) WrReqL <= 4'b0000;
					else if(Addr[1:0] == 2'b00) WrReqL <= 4'b0001;
					else if(Addr[1:0] == 2'b01) WrReqL <= 4'b0010;
					else if(Addr[1:0] == 2'b10) WrReqL <= 4'b0100;
					else if(Addr[1:0] == 2'b11) WrReqL <= 4'b1000;

					WrDataL <= WrData;
					state <= 4'd1;
				end
				else
				begin
					SDRAM_CMD <= SDRAM_CMD_NOP;
					SDRAM_A <= 0;
					SDRAM_DQM <= 4'b1111;
					state <= 4'd0;
				end
			end

			4'd1: begin
				SDRAM_CMD <= WrReqL ? SDRAM_CMD_WRITE : SDRAM_CMD_READ;
				SDRAM_A <= AddrL[9:2];			// column
				SDRAM_DQM <= WrReqL ? ~WrReqL : 4'b0000;
				state <= 4'd2;
			end

			4'd2: begin
				SDRAM_CMD <= SDRAM_CMD_PRECHARGE;	// precharge
				SDRAM_A <= 11'b100_0000_0000;
				SDRAM_DQM <= 4'b1111;
				WrReqL <= 4'b0000;
				state <= 4'd3;
			end

			4'd3: begin
				SDRAM_CMD <= SDRAM_CMD_NOP;
				SDRAM_A <= 0;
				SDRAM_DQM <= 4'b1111;
				state <= 4'd4;
			end

			4'd4: begin
				if(AddrL[1:0] == 2'b00) RdData <= SDRAM_DQ[7:0];
				else if(AddrL[1:0] == 2'b01) RdData <= SDRAM_DQ[15:8];
				else if(AddrL[1:0] == 2'b10) RdData <= SDRAM_DQ[23:16];
				else if(AddrL[1:0] == 2'b11) RdData <= SDRAM_DQ[31:24];

				if(refresh) refresh <= refresh - 1'd1;
				else begin
					refresh <= 6'd53;
					SDRAM_CMD <= SDRAM_CMD_REFRESH;
				end
				SDRAM_A <= 0;
				SDRAM_DQM <= 4'b1111;
				state <= 4'd0;
			end
		endcase
	end
end

assign SDRAM_DQ = WrReqL ? {WrDataL, WrDataL, WrDataL, WrDataL} : 32'hZZZZZZZZ;

endmodule

