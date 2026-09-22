// Board configuration for Sipeed Tang Nano 20K (GW2AR-18C), added 2026-09-23.
//
// Only reachable with the exact-lock video path (the stock frame buffer alone needs more
// BSRAM than this device's 46). Differences from the other boards, each handled where it
// matters:
//   - different FPGA family: rPLLs instead of PLLA, see src/pllr/pll_nano_exact.v
//   - 27 MHz crystal: core 54 MHz, pixel 27 MHz, TMDS 135 MHz (+0.55% core speed)
//   - SDRAM is inside the GW2AR package, 32 bits wide: src/sdram.v NANO20K mapping and
//     the width adapter in smstang_top.sv
//   - no USB host pins, two LEDs
`define NANO20K
`define SMALL_BOARD
