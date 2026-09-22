// Exact-lock timing constraints (2026-09-22).
//
// Upstream's smstang.sdc constrains clk_sys ONLY, so the 74.25 MHz pixel clock and the
// 371.25 MHz TMDS bit clock are both unconstrained in the stock build -- their timing is
// simply never checked. This file constrains all three real clocks of the exact-lock
// build, so "0 violations" means something.
//
//   clk_sys       53.750 MHz  (FVCO 806.25 / 15)
//   clk_pixel     26.875 MHz  (/30) -- exactly clk_sys / 2
//   clk_5x_pixel 134.375 MHz  (/6)  -- exactly clk_pixel x 5, and 2.8x lower than the
//                                      371.25 MHz the 720p build has to serialise at
create_clock -name clk_sys   -period 18.605 -waveform {0 9.302} [get_nets {clk_sys}]
create_clock -name clk_pixel -period 37.209 -waveform {0 18.605} [get_nets {clk_pixel}]
create_clock -name clk_5x    -period 7.442  -waveform {0 3.721} [get_nets {clk_5x_pixel}]
set_clock_groups -asynchronous -group [get_clocks {clk_sys}] -group [get_clocks {clk_pixel clk_5x}]

// Relax T80 timing constraints -- carried over from upstream's src/smstang.sdc. The RTL
// deliberately gives the Z80 two clk_sys cycles ("allow 2 cycles for z80", upstream
// 3d36b96). Omitting this over-constrains the design; on Nano 20K it was the difference
// between one failing Z80 flag path (-0.211 ns) and closing.
set_multicycle_path 2 -setup -start -from [get_pins {system/z80_inst/**/*}] -to [get_clocks {clk_sys}]
set_multicycle_path 1 -hold -start -from [get_pins {system/z80_inst/**/*}] -to [get_clocks {clk_sys}]
