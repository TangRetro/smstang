// Board configuration for Sipeed Tang Primer 25K (GW5A-25A).
//
// Added 2026-09-22. This board only became a possible target once the exact-lock video
// path removed the 256x192x12 frame buffer: the stock build needs 77 of this device's 56
// BSRAM blocks, the exact-lock build needs 42.
//
// Two board facts drive the guards in smstang_top.sv: the package has 68 regular I/O (so
// the eight LEDs, the second USB port and O_sdram_cke, which the SDRAM PMOD ties high, are
// not brought out), and the crystal is 50 MHz, the same as Console 60K, so the exact-lock
// PLL needs no change at all.
`define PRIMER25K
