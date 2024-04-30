`timescale 1 ns/ 100 ps
module VGAController(     
	input clk, 			// 100 MHz System Clock
	input reset, 		// Reset Signal
	output hSync, 		// H Sync Signal
	output vSync, 		// Veritcal Sync Signal
	output[3:0] VGA_R,  // Red Signal Bits
	output[3:0] VGA_G,  // Green Signal Bits
	output[3:0] VGA_B,  // Blue Signal Bits
	input ps2_clk,
	input ps2_data,
	input BTNU,
	input BTNR,
	input BTND,
	input BTNL,
	output[15:0] LED);
	
	// Lab Memory Files Location
	localparam FILES_PATH = "C:/Users/Elliot/Desktop/Processor/Labs/Lab67/";

	// Clock divider 100 MHz -> 25 MHz
	wire clk25; // 25MHz clock

	reg[1:0] pixCounter = 0;      // Pixel counter to divide the clock
    assign clk25 = pixCounter[1]; // Set the clock high whenever the second bit (2) is high
	always @(posedge clk) begin
		pixCounter <= pixCounter + 1; // Since the reg is only 3 bits, it will reset every 8 cycles
	end

	// VGA Timing Generation for a Standard VGA Screen
	localparam 
		VIDEO_WIDTH = 640,  // Standard VGA Width
		VIDEO_HEIGHT = 480; // Standard VGA Height

	reg [7:0] scan_code = 0;
	wire[7:0] rx_data;
	wire read_data;
	wire busy, err;

	wire active, screenEnd;
	wire[9:0] x;
	wire[8:0] y;

	reg [9:0] topLeftX = 0; // square starts at (0, 0)
	reg [8:0] topLeftY = 0;
	wire inSquare;

	assign inSquare = (x >= topLeftX && x < (topLeftX + 50)) && (y >= topLeftY && y < (topLeftY + 50));

	always @(posedge screenEnd) begin
		if (BTNU && (topLeftY > 0)) begin
			topLeftY <= topLeftY - 1;
		end
		if (BTND && (topLeftY < (VIDEO_HEIGHT - 49))) begin
			topLeftY <= topLeftY + 1;
		end
		if (BTNL && (topLeftX > 0)) begin
			topLeftX <= topLeftX - 1;
		end
		if (BTNR && (topLeftX < (VIDEO_WIDTH - 49))) begin
			topLeftX <= topLeftX + 1;
		end
	end

	always @(posedge read_data) begin
		scan_code <= rx_data;
	end

	Ps2Interface keeb(
		.ps2_clk(ps2_clk),  	// : inout std_logic;
		.ps2_data(ps2_data), 	// : inout std_logic;

		.clk(clk),      		// : in std_logic;
		.rst(reset),     	 	// : in std_logic;

		//tx_data   : in std_logic_vector(7 downto 0);
		//write_data  : in std_logic;
		
		.rx_data(rx_data),  		// : out std_logic_vector(7 downto 0);
		.read_data(read_data),  	// : out std_logic;
		.busy(busy),     		// : out std_logic;
		.err(err)     			// : out std_logic
	);

	localparam
		BITS_PER_ASCII = 7,
		ASCII_VALUE_COUNT = 256,
		ASCII_ADDRESS_WIDTH = $clog2(ASCII_VALUE_COUNT) + 1;
	
	wire[BITS_PER_ASCII-1:0] ascii_value;

	RAM #(		
		.DEPTH(ASCII_VALUE_COUNT), 	// 256 different ascii mappings			    
		.DATA_WIDTH(BITS_PER_ASCII),     // 7 bit ascii values
		.ADDRESS_WIDTH(ASCII_ADDRESS_WIDTH), // 8 bit addresses 2^8 = 256    
		.MEMFILE({FILES_PATH, "ascii.mem"})) 
	AsciiData(
		.clk(clk), 					
		.addr(scan_code),		// input the 8 bit scan code as address			
		.dataOut(ascii_value),		// get the value at scan code + 1?		
		.wEn(1'b0)); 			// always reading

	assign LED[6:0] = ascii_value;		
	
	VGATimingGenerator #(
		.HEIGHT(VIDEO_HEIGHT), // Use the standard VGA Values
		.WIDTH(VIDEO_WIDTH))
	Display( 
		.clk25(clk25),  	   // 25MHz Pixel Clock
		.reset(reset),		   // Reset Signal
		.screenEnd(screenEnd), // High for one cycle when between two frames
		.active(active),	   // High when drawing pixels
		.hSync(hSync),  	   // Set Generated H Signal
		.vSync(vSync),		   // Set Generated V Signal
		.x(x), 				   // X Coordinate (from left)
		.y(y)); 			   // Y Coordinate (from top)	   

	// Image Data to Map Pixel Location to Color Address
	localparam 
		PIXEL_COUNT = VIDEO_WIDTH*VIDEO_HEIGHT, 	             // Number of pixels on the screen
		PIXEL_ADDRESS_WIDTH = $clog2(PIXEL_COUNT) + 1,           // Use built in log2 command
		BITS_PER_COLOR = 12, 	  								 // Nexys A7 uses 12 bits/color
		PALETTE_COLOR_COUNT = 256, 								 // Number of Colors available
		PALETTE_ADDRESS_WIDTH = $clog2(PALETTE_COLOR_COUNT) + 1; // Use built in log2 Command

	wire[PIXEL_ADDRESS_WIDTH-1:0] imgAddress;  	 // Image address for the image data
	wire[PALETTE_ADDRESS_WIDTH-1:0] colorAddr; 	 // Color address for the color palette
	assign imgAddress = x + 640*y;				 // Address calculated coordinate
 
	RAM #(		
		.DEPTH(PIXEL_COUNT), 				     // Set RAM depth to contain every pixel
		.DATA_WIDTH(PALETTE_ADDRESS_WIDTH),      // Set data width according to the color palette
		.ADDRESS_WIDTH(PIXEL_ADDRESS_WIDTH),     // Set address with according to the pixel count
		.MEMFILE({FILES_PATH, "image.mem"})) // Memory initialization
	ImageData(
		.clk(clk), 						 // Falling edge of the 100 MHz clk
		.addr(imgAddress),					 // Image data address
		.dataOut(colorAddr),				 // Color palette address
		.wEn(1'b0)); 						 // We're always reading

	// Color Palette to Map Color Address to 12-Bit Color
	wire[BITS_PER_COLOR-1:0] colorData; // 12-bit color data at current pixel

	RAM #(
		.DEPTH(PALETTE_COLOR_COUNT), 		       // Set depth to contain every color		
		.DATA_WIDTH(BITS_PER_COLOR), 		       // Set data width according to the bits per color
		.ADDRESS_WIDTH(PALETTE_ADDRESS_WIDTH),     // Set address width according to the color count
		.MEMFILE({FILES_PATH, "colors.mem"}))  // Memory initialization
	ColorPalette(
		.clk(clk), 							   	   // Rising edge of the 100 MHz clk
		.addr(colorAddr),					       // Address from the ImageData RAM
		.dataOut(colorData),				       // Color at current pixel
		.wEn(1'b0)); 						       // We're always reading
	
	wire[BITS_PER_COLOR-1:0] colorToDisplay;
	assign colorToDisplay = inSquare ? 12'd255 : colorData;

	// Assign to output color from register if active
	wire[BITS_PER_COLOR-1:0] colorOut; 			  // Output color 
	assign colorOut = active ? colorToDisplay : 12'd0; // When not active, output black

	// Quickly assign the output colors to their channels using concatenation
	assign {VGA_R, VGA_G, VGA_B} = colorOut;
endmodule