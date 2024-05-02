
module fft(
    input       clk_100mhz,     //
    input       clk_50mhz,      //
	input		vauxp3,         //
    input		vauxn3,         //
	input       vp_in,          //
	input		vn_in           //
);

    localparam
        SAMPLE_COUNT = 1024,                    // 1024 point FFT
        FIFO_ADDR_WIDTH = $clog2(SAMPLE_COUNT), // $clog(1024) = 10-bit addrs
        BITS_PER_SAMPLE = 12;                   // signed 12-bit sample data

    // ---- WIRE SETUPS -----------------------------------------------------------------

    // BRAM
    wire inFIFO_wEn;
    wire [FIFO_ADDR_WIDTH-1:0] inFrame_addr;
    wire [BITS_PER_SAMPLE-1:0] sampleIn, sampleOut;

    // XADC
    wire xadc_rdy;
    wire [15:0] xadc_data;      // use 12 MSBs !!!

    wire eoc, eos, busy, alarm; // don't care
    wire [4:0] channel;         // don't care

    // XFFT
    wire s_axis_config_tready;
    wire [15:0] s_axis_config_tdata;

    wire s_axis_data_tready;
    wire s_axis_data_tlast;
    wire [31:0] s_axis_data_tdata;

    wire m_axis_status_tvalid;
    wire [7:0] m_axis_status_tdata;

    wire m_axis_data_tvalid;
    wire m_axis_data_tlast;
    wire [31:0] m_axis_data_tdata;
    wire [15:0] m_axis_data_tuser;

    // xfft don't cares
    wire event_frame_started;
    wire event_tlast_unexpected, event_tlast_missing;
    wire event_fft_overflow, event_status_channel_halt;
    wire event_data_in_channel_halt, event_data_out_channel_halt;

    // MAIN
    reg inFrame_last = 0;
    reg [BITS_PER_SAMPLE-1:0] sampled_data;   // remember to use 12 MSB!!! [15:4]
    reg [FIFO_ADDR_WIDTH-1:0] inFrame_head_ptr = 0;
    reg [FIFO_ADDR_WIDTH-1:0] inFrame_read_counter = 10'd1023;

    // ---- BRAM SETUPS -----------------------------------------------------------------

    RAM #(  // posedge reads always allowed, negedge writes when wEn
        .DEPTH(SAMPLE_COUNT),
        .ADDRESS_WIDTH(FIFO_ADDR_WIDTH),
        .DATA_WIDTH(BITS_PER_SAMPLE)
    ) InputFIFO (
        .clk(clk_50mhz),            // I: USES 50 MHz clk
        .wEn(inFrame_last),          // I:
        .addr(inFrame_addr),        // I: [9:0]
        .dataIn(sampled_data),      // I: [11:0]
        .dataOut(sampleOut)         // O: [11:0]
    );

    // ---- XADC SETUP ------------------------------------------------------------------

    xadc_wiz_0 sampler(
        // Control Signals
        .dclk_in(clk_100mhz),   // I : 1'b,     uses 100 MHz sys clk
        .eoc_out(eoc),          // O : 1'b,     X
        .eos_out(eos),          // O : 1'b,     X
        .busy_out(busy),        // O : 1'b,     X
        .alarm_out(alarm),      // O : 1'b,     X  

        // DRP in ports
        .den_in(1'b1),          // I : 1'b1,    DRP always enabled
        .daddr_in(8'h13),       // I : 7'b,     always reading from channel vaux3
        .di_in(16'b0),          // I : 16'b0,   never writing
        .dwe_in(1'b0),          // I : 1'b0,    never writing

        // DRP out ports
        .drdy_out(xadc_rdy),    // O : 1'b      sample ready flag
        .do_out(xadc_data),     // O : 16'b     actual PCM-mapped data sample

        // XADC in ports
        .vp_in(1'b1),           // I : 1'b,     X
        .vn_in(1'b1),           // I : 1'b,     X
        .vauxp3(vauxp3),        // I : 1'b,     input from FPGA pin A13
        .vauxn3(vauxn3),        // I : 1'b,     input from FPGA pin A14

        // XADC out ports
        .channel_out(channel)   // O : 5'b, X
    );

    // ---- XFFT SETUP ------------------------------------------------------------------

    assign s_axis_config_tdata = {5'b0, 10'b10101010, 1'b1};

    /*
        need to assign:
            s_axis_data_tlast
            s_axis_data_tdata

        need to use:
            m_axis_data_tvalid
                first time = marks end of first frame's latency, frames appear b2b
            m_axis_data_tlast + m_axis_data_tdata 
                use these when writing output vals to output FIFO
            m_axis_data_tuser
                use this if we need index of output sample for some reason?
    */

    xfft_0 transform(
        // Control Signals
        .aclk(clk_50mhz),

        // -- IN  PORTS --
        // S_AXIS_CONFIG
        .s_axis_config_tvalid(1'b1),                    // (X)  I : [1'b1], doesn't matter after first, config never changes so can always input
        .s_axis_config_tready(s_axis_config_tready),    // (X)  O : [1'b ], doesn't matter after first
        
        .s_axis_config_tdata(s_axis_config_tdata),      // (!)  I : [16'b] = {5'b0 pad, 10'b10101010 SCALE_SCH, 1'b1 FWD}

        // S_AXIS_DATA
        .s_axis_data_tvalid(clk_50mhz),                 // (1)  I : [1'b1], always input samples on 50 MHz posedges
        .s_axis_data_tready(s_axis_data_tready),        // (1)  O : [1'b ], i think this is always 1 on 50 MHz posedges

        .s_axis_data_tlast(s_axis_data_tlast),          // (!)  I : [1'b ] = asserted on same posedge that 1024th sample is input
        .s_axis_data_tdata(s_axis_data_tdata),          // (!)  I : [32'b] = {4'b0 pad, 12'b0 IM, 4'b0 pad, 12'b signed REAL_SAMPLE}

        // -- OUT PORTS --
        // M_AXIS_STATUS
        .m_axis_status_tvalid(m_axis_status_tvalid),    // (X)  O : [1'b ], don't care
        .m_axis_status_tready(1'b1),                    // (X)  I : [1'b1], don't care abt these, always enable

        .m_axis_status_tdata(m_axis_status_tdata),      // (X)  O : [8'b ], don't care = {7'b0 pad, 1'b OVFLO}

        // M_AXIS_DATA
        .m_axis_data_tvalid(m_axis_data_tvalid),        // (!)  O : [1'b ], after first frame's latency, i think is always 1 on 50 MHz posedges
        .m_axis_data_tready(1'b1),                      // (1)  I : [1'b1], always output samples on 50 MHz posedges
        
        .m_axis_data_tlast(m_axis_data_tlast),          // (!)  O : [1'b ] = asserted on same posedge that 1024th sample is output
        .m_axis_data_tdata(m_axis_data_tdata),          // (!)  O : [32'b] = {4'b0 pad, 12'b signed IM_XK, 4'b0 pad, 12'b signed RE_XK}

        .m_axis_data_tuser(m_axis_data_tuser),          // (!)  O : [16'b] = {6'b0 pad, 10'b unsigned XK_INDEX}

        // DONT CARES (X)
        .event_frame_started(event_frame_started),
        .event_tlast_unexpected(event_tlast_unexpected),
        .event_tlast_missing(event_tlast_missing),
        .event_fft_overflow(event_fft_overflow),
        .event_status_channel_halt(event_status_channel_halt),
        .event_data_in_channel_halt(event_data_in_channel_halt),
        .event_data_out_channel_halt(event_data_out_channel_halt)
    );

    // ---- SAMPLE + TRANSFORM CODE -----------------------------------------------------

    
    // ---- END CODE --------------------------------------------------------------------

endmodule