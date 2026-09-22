// Exact-lock clocks for Tang Nano 20K (GW2AR-18C), 2026-09-23.
//
// Derived from nand2mario's nestang src/pllr/gowin_pll_nes.v (rPLL instantiation and
// the SDRAM phase) and this author's pcetang nano20k_pll.vhd (the 135 MHz + CLKDIV/5
// pixel clock). GPL-3.0-or-later.
//
// The board's crystal is 27 MHz, which makes the lock simpler than on Console 60K:
//
//   rPLL A: 27 x 5  = 135.000 MHz  TMDS bit clock  (IDIV 0, FBDIV 4, ODIV 4 -> VCO 540)
//     CLKDIV /5     =  27.000 MHz  pixel clock, edge-aligned to the TMDS clock
//   rPLL B: 27 x 2  =  54.000 MHz  core            (IDIV 0, FBDIV 1, ODIV 16 -> VCO 864)
//     CLKOUTP       =  54.000 MHz  SDRAM clock, PSDA 1010 = 225 deg (nestang's value)
//
// core / pixel = 54 / 27 = 2 EXACTLY, so a 3420-clock source line is still 2 x 855 pixel
// clocks and hdmi mode 201 is unchanged. Both PLLs lock to the same crystal, so the ratio
// cannot drift; the phase is set once by the video module's vreset.
//
// COST: the core runs at 54.000 MHz against upstream's 53.7037 (+0.55%, ~9.5 cents of
// pitch). 53.75 is not reachable from 27 MHz with this PLL's integer dividers.

module pll_nano_exact (
    input  clkin,           // 27 MHz crystal
    output clk_sys,         // 54 MHz core
    output clk_sdram,       // 54 MHz, 225 degrees, to the in-package SDRAM
    output clk_pixel,       // 27 MHz
    output clk_5x,          // 135 MHz
    output lock
);

wire gw_vcc = 1'b1;
wire gw_gnd = 1'b0;
wire lock_a, lock_b;
assign lock = lock_a & lock_b;

rPLL pll_hdmi (
    .CLKOUT(clk_5x), .LOCK(lock_a), .CLKOUTP(), .CLKOUTD(), .CLKOUTD3(),
    .RESET(gw_gnd), .RESET_P(gw_gnd), .CLKIN(clkin), .CLKFB(gw_gnd),
    .FBDSEL({6{gw_gnd}}), .IDSEL({6{gw_gnd}}), .ODSEL({6{gw_gnd}}),
    .PSDA({4{gw_gnd}}), .DUTYDA({4{gw_gnd}}), .FDLY({4{gw_vcc}})
);
defparam pll_hdmi.FCLKIN = "27";
defparam pll_hdmi.DYN_IDIV_SEL = "false";
defparam pll_hdmi.IDIV_SEL = 0;
defparam pll_hdmi.DYN_FBDIV_SEL = "false";
defparam pll_hdmi.FBDIV_SEL = 4;
defparam pll_hdmi.DYN_ODIV_SEL = "false";
defparam pll_hdmi.ODIV_SEL = 4;
defparam pll_hdmi.PSDA_SEL = "0000";
defparam pll_hdmi.DYN_DA_EN = "false";
defparam pll_hdmi.DUTYDA_SEL = "1000";
defparam pll_hdmi.CLKOUT_FT_DIR = 1'b1;
defparam pll_hdmi.CLKOUTP_FT_DIR = 1'b1;
defparam pll_hdmi.CLKOUT_DLY_STEP = 0;
defparam pll_hdmi.CLKOUTP_DLY_STEP = 0;
defparam pll_hdmi.CLKFB_SEL = "internal";
defparam pll_hdmi.CLKOUT_BYPASS = "false";
defparam pll_hdmi.CLKOUTP_BYPASS = "false";
defparam pll_hdmi.CLKOUTD_BYPASS = "false";
defparam pll_hdmi.DYN_SDIV_SEL = 2;
defparam pll_hdmi.CLKOUTD_SRC = "CLKOUT";
defparam pll_hdmi.CLKOUTD3_SRC = "CLKOUT";
defparam pll_hdmi.DEVICE = "GW2AR-18C";

// Pixel clock by dividing the TMDS clock, not from a PLL output: the serializer needs
// its two clocks edge-aligned, which a separate PLL output would not guarantee.
CLKDIV #(.DIV_MODE("5"), .GSREN("false")) div5 (
    .CLKOUT(clk_pixel), .HCLKIN(clk_5x), .RESETN(lock_a), .CALIB(gw_gnd)
);

rPLL pll_core (
    .CLKOUT(clk_sys), .LOCK(lock_b), .CLKOUTP(clk_sdram), .CLKOUTD(), .CLKOUTD3(),
    .RESET(gw_gnd), .RESET_P(gw_gnd), .CLKIN(clkin), .CLKFB(gw_gnd),
    .FBDSEL({6{gw_gnd}}), .IDSEL({6{gw_gnd}}), .ODSEL({6{gw_gnd}}),
    .PSDA({4{gw_gnd}}), .DUTYDA({4{gw_gnd}}), .FDLY({4{gw_vcc}})
);
defparam pll_core.FCLKIN = "27";
defparam pll_core.DYN_IDIV_SEL = "false";
defparam pll_core.IDIV_SEL = 0;
defparam pll_core.DYN_FBDIV_SEL = "false";
defparam pll_core.FBDIV_SEL = 1;
defparam pll_core.DYN_ODIV_SEL = "false";
defparam pll_core.ODIV_SEL = 16;
defparam pll_core.PSDA_SEL = "1010";
defparam pll_core.DYN_DA_EN = "false";
defparam pll_core.DUTYDA_SEL = "1000";
defparam pll_core.CLKOUT_FT_DIR = 1'b1;
defparam pll_core.CLKOUTP_FT_DIR = 1'b1;
defparam pll_core.CLKOUT_DLY_STEP = 0;
defparam pll_core.CLKOUTP_DLY_STEP = 0;
defparam pll_core.CLKFB_SEL = "internal";
defparam pll_core.CLKOUT_BYPASS = "false";
defparam pll_core.CLKOUTP_BYPASS = "false";
defparam pll_core.CLKOUTD_BYPASS = "false";
defparam pll_core.DYN_SDIV_SEL = 2;
defparam pll_core.CLKOUTD_SRC = "CLKOUT";
defparam pll_core.CLKOUTD3_SRC = "CLKOUT";
defparam pll_core.DEVICE = "GW2AR-18C";

endmodule
