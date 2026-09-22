// Modifications copyright (c) 2026 Romain Tisserand.
// Derived from this repository's own src/sms2hdmi.sv; only the changes are covered above.
// GPL-3.0-or-later, same as the file it derives from.
//
// EXACT-LOCK SMS -> HDMI, line-buffered (2026-09-22).
//
// src/sms2hdmi.sv keeps a WHOLE FRAME in block RAM (256 x 192 x 12 bits) because its
// pixel clock (74.25 MHz, 720p) has no relationship to the Master System's clock: the
// output raster and the source raster drift past each other, so the only way to show a
// coherent picture is to buffer the whole thing.
//
// Here both clocks come off ONE VCO on integer dividers (see src/plla/pll_exact.v), so:
//
//     one source line = 3420 core clocks = 2 output lines of 855 pixel clocks
//     one source frame = 262 source lines = 524 output lines
//
// Every source line is exactly two output lines, for ever. That makes a frame buffer
// pointless: three line buffers are enough, and the saving is the whole framebuffer.
// The technique is from MiSTle-Dev/c64nano (harbaum) via this author's pcetang core.
//
// Output is the real CEA 720x480p60 active area declared as VIC 2 (mode 201 in
// src/hdmi2/hdmi.sv); only the blanking differs from CEA, which is what buys the lock.
// The 256x192 picture is centred in that window: x2 vertically (384 of 480 lines) and
// scaled 256 -> 576 horizontally by a fractional counter, which is 4:3 inside a frame the
// sink already displays as 4:3.

module sms2hdmi_sd (
    input clk,                  // core clock, 53.75 MHz
    input resetn,

    // sms video signals
    input ce_pix,
    input [8:0] x,
    input [8:0] y,
    input [11:0] color,         // BGR444

    input [15:0] audio_l,
    input [15:0] audio_r,

    // overlay interface (unchanged from sms2hdmi.sv: a 256x224 character grid)
    input overlay,
    output [7:0] overlay_x,
    output [7:0] overlay_y,
    input [14:0] overlay_color, // BGR5

    // video clocks -- clk_pixel MUST be clk/2 off the same VCO, clk_5x_pixel = clk_pixel x5
    input clk_pixel,
    input clk_5x_pixel,

    // output signals
    output       tmds_clk_n,
    output       tmds_clk_p,
    output [2:0] tmds_d_n,
    output [2:0] tmds_d_p
);

localparam CLKFRQ = 26875;          // clk_pixel in kHz -- feeds the audio divider below
localparam AUDIO_BIT_WIDTH = 16;
localparam AUDIO_RATE = 48000;

localparam SRC_W      = 256;        // active source pixels per line
localparam SRC_H      = 192;        // active source lines
localparam OVL_H      = 224;        // the overlay is taller than the picture
localparam DST_W      = 576;        // 256 -> 576 keeps 4:3 inside the 720x480 window
localparam XSTART     = (720 - DST_W) / 2;          // 72
localparam YSTART     = (480 - SRC_H * 2) / 2;      // 48
localparam OVL_YSTART = (480 - OVL_H * 2) / 2;      // 16

wire [9:0]  cy;
wire [10:0] cx;

// ---------------------------------------------------------------------------------------
// Three line buffers. 3 x 256 x 12 bits = 9216 bits, about one 18 Kb block -- versus
// 256 x 192 x 12 = 589824 bits for the frame buffer this replaces.
//
// THREE, not two: the write side is a full source line ahead of the read side only on
// average. Two would need the changeover to happen inside the horizontal blanking of the
// SECOND output line of a pair, which is true only if the phase never moves; three gives
// a whole line of slack either way and costs nothing (one block either way).
// ---------------------------------------------------------------------------------------
localparam int N_LINE_BUF = 3;

reg [11:0] linebuf [0:N_LINE_BUF*SRC_W-1];
reg [1:0]  wr_sel = 2'd0;                   // buffer the core is filling
reg [8:0]  y_r    = 9'd0;

// Write side, core clock. The VDP emits a line's pixels at x = 1..256.
always @(posedge clk) begin
    y_r <= y;
    if (ce_pix) begin
        if (y != y_r)                       // new source line: rotate the write buffer
            wr_sel <= (wr_sel == N_LINE_BUF-1) ? 2'd0 : wr_sel + 2'd1;
        if (y < SRC_H && x != 0 && x <= SRC_W)
            linebuf[{wr_sel, x[7:0] - 8'd1}] <= color;
    end
end

// ---------------------------------------------------------------------------------------
// Frame phase. The source's first active line must land on a known output line, and under
// an exact lock that only has to be arranged ONCE: after that the two rasters cannot
// drift. A single `vreset` pulse slams the HDMI raster counters to 0,0 at the moment the
// source starts a new frame. It is NOT hdmi.sv's `reset` -- that one fans out to the
// serializer on the 134 MHz clock and costs real timing margin (learned the hard way in
// pcetang); `vreset` touches cx/cy only.
//
// Armed at power-up and re-armed if the source ever restarts its frame count from a
// different place, which is what a mode change or a reset looks like from here.
// ---------------------------------------------------------------------------------------
reg  frame_start   = 1'b0;      // core clock, one pulse at the top of a source frame
reg  frame_start_x = 1'b0;      // crossed into the pixel domain
reg  fs_meta       = 1'b0;
reg  fs_sync       = 1'b0;
reg  fs_sync_r     = 1'b0;
reg  phase_armed   = 1'b1;
reg  vreset        = 1'b0;

always @(posedge clk) begin
    frame_start <= 1'b0;
    if (ce_pix && y == 9'd0 && y_r != 9'd0) begin
        frame_start   <= 1'b1;
        frame_start_x <= ~frame_start_x;    // toggle: survives the clock crossing
    end
end

always @(posedge clk_pixel) begin
    fs_meta   <= frame_start_x;
    fs_sync   <= fs_meta;
    fs_sync_r <= fs_sync;
    vreset    <= 1'b0;
    if (phase_armed && (fs_sync != fs_sync_r)) begin
        vreset      <= 1'b1;
        phase_armed <= 1'b0;
    end
end

// ---------------------------------------------------------------------------------------
// Read side, pixel clock. Vertical: every source line is shown twice, so the source line
// index is just (cy - YSTART) >> 1. Horizontal: a fractional counter walks 256 source
// pixels across the 576-pixel window, the same arrangement sms2hdmi.sv already used for
// its 256 -> 960 scale.
// ---------------------------------------------------------------------------------------
wire [9:0]  ytop    = overlay ? OVL_YSTART[9:0] : YSTART[9:0];
wire [9:0]  yheight = overlay ? (OVL_H*2) : (SRC_H*2);
wire        v_in    = (cy >= ytop) && (cy < ytop + yheight);
wire        h_in    = (cx >= XSTART) && (cx < XSTART + DST_W);

wire [9:0]  src_line = (cy - ytop) >> 1;            // 0..191 (or 0..223 with the overlay)

reg  [8:0]  src_x  = 9'd0;
reg  [10:0] xacc   = 11'd0;
reg         active = 1'b0;
reg  [11:0] px;
reg  [23:0] rgb;

// Which buffer holds src_line. The write side rotates once per source line and the read
// side consumes one source line per two output lines, so the distance between them is
// constant once vreset has set the phase; taking src_line modulo the buffer count is
// therefore the same buffer the core wrote, one line ago.
reg  [1:0]  rd_sel;
always @(posedge clk_pixel) begin
    // src_line mod 3 without a divider: the line index only ever advances by one.
    if (cx == 0) begin
        if (cy == ytop)                 rd_sel <= 2'd0;
        else if (v_in && cy[0] == 1'b1) rd_sel <= (rd_sel == N_LINE_BUF-1) ? 2'd0 : rd_sel + 2'd1;
    end
end

always @(posedge clk_pixel) begin
    active <= v_in && h_in;

    if (cx == 0) begin
        src_x <= 9'd0;
        xacc  <= 11'd0;
    end else if (v_in && h_in) begin
        xacc <= xacc + SRC_W[10:0];                 // += 256 per output pixel
        if (xacc + SRC_W[10:0] >= DST_W[10:0]) begin
            xacc  <= xacc + SRC_W[10:0] - DST_W[10:0];
            src_x <= src_x + 9'd1;
        end
    end

    px <= linebuf[{rd_sel, src_x[7:0]}];

    if (active) begin
        if (overlay)
            rgb <= {overlay_color[4:0],3'b0,overlay_color[9:5],3'b0,overlay_color[14:10],3'b0};
        else
            rgb <= {px[3:0],4'b0, px[7:4],4'b0, px[11:8],4'b0};   // BGR4 -> RGB8
    end else
        rgb <= 24'h000000;              // letterbox/pillarbox: black, not the old grey
end

assign overlay_x = src_x[7:0];
assign overlay_y = src_line[7:0];

// ---------------------------------------------------------------------------------------
// Audio: unchanged in shape, but the divider now comes off 26.875 MHz instead of 74.25.
// ---------------------------------------------------------------------------------------
localparam AUDIO_CLK_DELAY = CLKFRQ * 1000 / AUDIO_RATE / 2;
logic [$clog2(AUDIO_CLK_DELAY)-1:0] audio_divider;
logic clk_audio;

always_ff @(posedge clk_pixel) begin
    if (audio_divider != AUDIO_CLK_DELAY - 1)
        audio_divider <= audio_divider + 1'd1;
    else begin
        clk_audio     <= ~clk_audio;
        audio_divider <= 0;
    end
end

reg [15:0] audio_sample_word [1:0], audio_sample_word0 [1:0];
always @(posedge clk_pixel) begin
    audio_sample_word0[0] <= audio_l;
    audio_sample_word[0]  <= audio_sample_word0[0];
    audio_sample_word0[1] <= audio_r;
    audio_sample_word[1]  <= audio_sample_word0[1];
end

// ---------------------------------------------------------------------------------------
// HDMI output: mode 201, the SMS exact-lock timing (855 x 524, 720x480 active, VIC 2).
// ---------------------------------------------------------------------------------------
logic [2:0] tmds;
logic       tmdsClk;

localparam VIDEOID = 201;
localparam VIDEO_REFRESH = 60.0;

hdmi #( .VIDEO_ID_CODE(VIDEOID),
        .DVI_OUTPUT(0),
        .VIDEO_REFRESH_RATE(VIDEO_REFRESH),
        .IT_CONTENT(1),
        .AUDIO_RATE(AUDIO_RATE),
        .AUDIO_BIT_WIDTH(AUDIO_BIT_WIDTH),
        .START_X(0),
        .START_Y(0) )
hdmi( .clk_pixel_x5(clk_5x_pixel),
        .clk_pixel(clk_pixel),
        .clk_audio(clk_audio),
        .rgb(rgb),
        .reset(1'b0),
        .vreset(vreset),
        .audio_sample_word(audio_sample_word),
        .tmds(tmds),
        .tmds_clock(tmdsClk),
        .cx(cx),
        .cy(cy),
        .frame_width(),
        .frame_height() );

// Gowin LVDS output buffer
ELVDS_OBUF tmds_bufds [3:0] (
    .I({clk_pixel, tmds}),
    .O({tmds_clk_p, tmds_d_p}),
    .OB({tmds_clk_n, tmds_d_n})
);

endmodule
