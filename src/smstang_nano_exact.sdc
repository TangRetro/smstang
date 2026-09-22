// Nano 20K exact-lock timing constraints (2026-09-23): 27 MHz crystal, core 54 (27 x 2),
// pixel 27 (135 / 5), TMDS 135 (27 x 5). All three constrained, unlike upstream's sdc.
create_clock -name clk_sys   -period 18.519 -waveform {0 9.259}  [get_nets {clk_sys}]
create_clock -name clk_pixel -period 37.037 -waveform {0 18.519} [get_nets {clk_pixel}]
create_clock -name clk_5x    -period 7.407  -waveform {0 3.704}  [get_nets {clk_5x_pixel}]
set_clock_groups -asynchronous -group [get_clocks {clk_sys}] -group [get_clocks {clk_pixel clk_5x}]

// Relax T80 timing constraints -- carried over from upstream's src/smstang.sdc. The RTL
// deliberately gives the Z80 two clk_sys cycles ("allow 2 cycles for z80", upstream
// 3d36b96). Omitting this over-constrains the design; on Nano 20K it was the difference
// between one failing Z80 flag path (-0.211 ns) and closing.
set_multicycle_path 2 -setup -start -from [get_pins {system/z80_inst/**/*}] -to [get_clocks {clk_sys}]
set_multicycle_path 1 -hold -start -from [get_pins {system/z80_inst/**/*}] -to [get_clocks {clk_sys}]
