module AudioController(
	// Inputs from FPGA
    input        clk, 		  // [used directly] FROM FPGA: E3 = System Clock Input 100 Mhz
    input        micData,	  // FROM FPGA: H5 = Microphone Output PWM signal
    input[3:0]   switches,	  // [used directly] FROM FPGA: R15, M13, L16, J15 = Tone control switches

	// Outputs to FPGA Microphone Ports
    output       micClk, 	  // [1 MHz] INTO FPGA: J5 = Mic clock [THIS IS SAMPLING FREQ]
    output       chSel,		  // [1'b0]  INTO FPGA: Channel select; 0 for rising edge, 1 for falling edge

	// Outputs to FPGA Mono Audio Output Ports
    output       audioOut,	  // [toneAudio] INTO FPGA: PWM signal to the audio jack	
    output       audioEn,	  // [1'b1]      INTO FPGA: Audio Enable

	output[8:0]		 LED 		  //
);

	localparam MHz = 1000000;
	localparam SYSTEM_FREQ = 100*MHz; // System clock frequency

	assign chSel   = 1'b0;  // Collect Mic Data on the rising edge 
	assign audioEn = 1'b1;  // Enable Audio Output

	// Initialize the frequency array. FREQs[0] = 261
	reg[10:0] FREQs[0:15];
	initial begin
		$readmemh("C:/Users/Elliot/Desktop/Processor/Labs/Lab8/FREQs.mem", FREQs);
	end
	
	// Duty cycle varies in order to represent the different signal amplitudes
	// Duty cycle's are more abt "probability (%) in time" (w.r.t. system clock?) to read a high or low imo 
	
	/*
		// CLOCK FREQUENCIES:
		// clk = (100 MHz)
		//		System clock that everything runs on
		// micClk = (1 MHz)
		//		1.) THIS IS THE SAMPLING RATE OF THE INPUT ANALOG AUDIO SIGNAL
		//			I.e., 1 full MHz clock cycle takes 1 microsecond (us) => 128 us to get 128 audio samples
		//			Where each audio sample is a PDM sample
		//
		//			a.) The 1-bit **PDM** signal (after delta-sig modulating the analog signal)
		//				is read either high or low on micClk posedge
		//				Thus, need to store this bit in a register on micClk posedge
		//
		//			b.) THIS BIT REPRESENTS A SINGLE AUDIO SAMPLE.
		//
		//				PDM encodes the amplitude as the density of 1's over a time interval
		//				THUS, need to define a time interval (typically 1 bin = 1024 samples taken @ micClk?)
		//				The density represents the average amplitude over the time interval
		//				Sooo... in other words, PDM is dogshit and need a better format
		//				
		//			c.) PCM Precision = # of different amplitude levels that can be represented by one sample
		//				7-bit precision = 2^7 = 128 possible different amplitude levels represented in the sample
		//
		//				For a task requiring 7-bit resolution = 2^7 = 128 PDM bit values for one "unit" of information
		//				THUS, for 128 samples, need 128 clock cycles @ micClk frequency
		//				I.e., 1 full MHz clock cycle takes 1 microsecond (us) = 128 us to get 128 audio samples
		//			
		//		2.) This is PWMSerializer's PULSE_FREQ, i.e., a serialized PWM clock cycle starts every 1 MHz
	*/

	// ---- Tone Generation -------------------------------------------------------------
	reg clkHz = 0;
	reg [17:0] counter = 0;
	wire [17:0] CounterLimit;
	wire [6:0] tone_duty_cycle;
	wire toneAudio;

	// Clock Divider part. Gets the duty cycle at the interval of clkHz
	// Based on fastest system clock (100 MHz), clkHz will be (FREQs[switches] Hz)
	// clkHz is the square wave clock toggle representing the actual audio signal frequency
	// System Freq : Desired Freq ratio, where counterlimit = halfway point to swap
	assign CounterLimit = SYSTEM_FREQ / (FREQs[switches] * 2) - 1; 

	always @(posedge clk) begin
		if (counter < CounterLimit)
			counter <= counter + 1;
		else begin
			counter <= 0;
			clkHz <= ~clkHz;
		end
	end

	assign tone_duty_cycle = clkHz ? 7'd100 : 7'd0;

	// Serializes into PWM signal with the duty cycle given by clkHz square wave
	PWMSerializer s(
		.clk(clk),               // System Clock
		.reset(1'b0),            // Reset the counter
		.duty_cycle(tone_duty_cycle), // Duty Cycle of the Wave, between 0 and 99
		.signal(toneAudio)
	);

	// Outputs to FPGA audio
	// assign audioOut = toneAudio;

	// ---- Microphone Code -------------------------------------------------------------

	reg clk1MHz = 0; // microphone clock freq
	reg pdm_micData = 0;
	reg [17:0] counter1MHz = 0;
	wire [17:0] CounterLimit1MHz;

	reg clk10kHz = 0;
	reg [6:0] pwm_duty_cycle = 0;
	reg [17:0] counter10kHz = 0;
	wire [17:0] CounterLimit10kHz;
	wire [6:0] pdm_duty_cycle;

	reg micAudio = 0;
	wire mic_pwm;

	assign CounterLimit1MHz = SYSTEM_FREQ / (MHz * 2) - 1;

	always @(posedge clk) begin
		if (counter1MHz < CounterLimit1MHz)
			counter1MHz <= counter1MHz + 1;
		else begin
			counter1MHz <= 0;
			clk1MHz <= ~clk1MHz;
		end
	end

	assign micClk = clk1MHz;

	// input micData = 1'b input PDM sample bit value
	// micData available and stable on posedge of micClk, saved in pdm_micData
	// so I store a new pdm bit on the posedge of every 49th sys clk cycle

	// data stored on the nth clk posedge:
	// 49, 147, 245, 343, 441, 539, 637, 735, 833, 931 = 10 PDM samples
	// so then, 10,050'th clk posedge is the 101st PDM sample
	// and here is where we want to reset
	always @(posedge micClk) begin
		pdm_micData <= micData;
	end

	assign LED[7] = (pdm_micData == 1'b0) ? 1'b1 : 1'b0;
	assign LED[8] = (pdm_micData == 1'b1) ? 1'b1 : 1'b0;
	
	PWMDeserializer d(
		.clk(clk),  
		.reset(1'b0),
		.signal(pdm_micData), 
		.duty_cycle(pdm_duty_cycle)
	);

	assign CounterLimit10kHz = SYSTEM_FREQ / (10000 * 2) - 1;

	always @(posedge clk) begin
		if (counter10kHz < CounterLimit10kHz)
			counter10kHz <= counter10kHz + 1;
		else begin
			counter10kHz <= 0;
			clk10kHz <= ~clk10kHz;
		end
	end

	always @(negedge clk10kHz) begin
		pwm_duty_cycle <= pdm_duty_cycle;
	end

	wire [6:0] additive_duty_cycle;
	wire additive_out;

	assign additive_duty_cycle = ((50 + (pwm_duty_cycle - 50)/2) + (50 + (tone_duty_cycle - 50)/2))/2;
	assign LED[6:0] = pwm_duty_cycle;

	PWMSerializer s2(
		.clk(clk),               	 // System Clock
		.reset(1'b0),            	 // Reset the counter
		.duty_cycle(pwm_duty_cycle), // Duty Cycle of the Wave, between 0 and 99
		.signal(additive_out)
	);

	// ---- Output Mono Audio ----
	assign audioOut = (pdm_micData == 1'b0) ? 1'b0 : 1'bz;

endmodule