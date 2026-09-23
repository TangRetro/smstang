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

module sms2hdmi_sd #(
    // 201 + 26875 on Console 60K / Primer 25K (26.875 MHz pixel clock); 202 + 27000 on
    // Nano 20K (27.000 MHz). Same raster either way -- see hdmi.sv modes 201/202.
    parameter VIDEOID = 201,
    parameter CLKFRQ  = 26875           // clk_pixel in kHz, for the audio divider
)(
    input clk,                  // core clock, 53.75 MHz (54.0 on Nano 20K)
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
        // New source line: rotate the write buffer, and restart at buffer 0 on source line
        // 0 so that line s always lands in buffer s mod 3. Without the restart the phase
        // slips by 262 mod 3 = 1 buffer every frame against the read side, which restarts
        // at 0 every frame too.
        if (y != y_r)
            wr_sel <= (y == 9'd0 || wr_sel == N_LINE_BUF-1) ? 2'd0 : wr_sel + 2'd1;
        if (y < SRC_H && x != 0 && x <= SRC_W)
            linebuf[{wr_sel, x[7:0] - 8'd1}] <= color;
    end
end

// ---------------------------------------------------------------------------------------
// Frame phase. Under an exact lock the output raster cannot drift against the source, so
// the phase only has to be set, not servoed. A `vreset` pulse loads the HDMI raster at the
// moment the source starts line 0, with cy = YSTART - 2: source line s then starts at output
// line YSTART + 2s - 2 and is displayed on YSTART + 2s and YSTART + 2s + 1, i.e. exactly one
// source line after it was written. The writer is then filling buffer (s+1) mod 3 and
// cannot touch buffer s mod 3 until line s+3, after the display is done with it.
// (Loading cy = 0 instead, as the first version did, displays line s 24 source lines late,
// in the buffer the writer is filling at that moment.)
//
// It is NOT hdmi.sv's `reset` -- that one fans out to the serializer on the 134 MHz clock
// and costs real timing margin (learned the hard way in pcetang); `vreset` touches cx/cy
// only. It fires at power-up and again ONLY when a source frame starts somewhere other than
// where the lock puts it -- a console reset or game load restarts the VDP counters.
// The window absorbs the few clocks of the crossing.
// ---------------------------------------------------------------------------------------
localparam [9:0] VRESET_CY = YSTART - 2;
localparam [9:0] V_TOTAL   = 524;
localparam [10:0] H_TOTAL  = 855;

reg  frame_start_x = 1'b0;      // toggle in the core domain, survives the clock crossing
reg  fs_meta       = 1'b0;
reg  fs_sync       = 1'b0;
reg  fs_sync_r     = 1'b0;
reg  vreset        = 1'b0;

always @(posedge clk) begin
    if (ce_pix && y == 9'd0 && y_r != 9'd0)
        frame_start_x <= ~frame_start_x;
end

wire in_phase = (cy == VRESET_CY && cx < 11'd16) || (cy == VRESET_CY - 10'd1 && cx >= H_TOTAL - 11'd16);

always @(posedge clk_pixel) begin
    fs_meta   <= frame_start_x;
    fs_sync   <= fs_meta;
    fs_sync_r <= fs_sync;
    vreset    <= (fs_sync != fs_sync_r) && !in_phase;
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
        // advance on the FIRST output line of each pair (same parity as ytop), so source
        // line s occupies output lines ytop+2s and ytop+2s+1
        else if (v_in && cy[0] == ytop[0]) rd_sel <= (rd_sel == N_LINE_BUF-1) ? 2'd0 : rd_sel + 2'd1;
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
        .vreset_cy(VRESET_CY),
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
