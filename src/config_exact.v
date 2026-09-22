// Selects the exact-lock video path (src/sms2hdmi_sd.sv + src/plla/pll_exact.v).
// Added FIRST by build.tcl for the `console60k_exact` target, so the macro is defined
// before smstang_top.sv is analysed. The stock `console60k` target never adds this file
// and is byte-for-byte the upstream build.
`define EXACT_LOCK 1
