if {$argc == 0} {
    puts "Usage: $argv0 <device>"
    puts "          device: console60k console138k"
    puts "Currently supports ds2 and usb controller"
    exit 1
}

set dev [lindex $argv 0]

# EXACT LOCK (2026-09-22): same board as console60k, but the video clocks come off the
# core's own VCO so every source line is exactly two output lines and the HDMI frame
# buffer is not needed. See src/plla/pll_exact.v, src/sms2hdmi_sd.sv, hdmi2 mode 201.
set exact 0
if {$dev eq "console60k_exact"} {
    set exact 1
    set dev "console60k"
    set_option -output_base_name smstang_console60k_exact
}
if {$dev eq "nano20k_exact"} {
    set exact 1
    set dev "nano20k"
    set_option -output_base_name smstang_nano20k_exact
}
if {$dev eq "primer25k_exact"} {
    set exact 1
    set dev "primer25k"
    set_option -output_base_name smstang_primer25k_exact
}

if {$dev eq "console60k"} {
    set_device GW5AT-LV60PG484AC1/I0 -device_version B
    add_file -type cst "src/boards/console.cst"
    add_file -type verilog "src/plla/pll_12.v"
    if {$exact} {
        add_file -type verilog "src/config_exact.v"
        add_file -type verilog "src/plla/pll_exact.v"
    } else {
        add_file -type verilog "src/plla/pll_27.v"
        add_file -type verilog "src/plla/pll_53.v"
        add_file -type verilog "src/plla/pll_74.v"
    }
} elseif {$dev eq "nano20k"} {
    # Nano 20K (GW2AR-18C). EXACT LOCK ONLY. Different FPGA family from the other boards:
    # rPLLs from a 27 MHz crystal (src/pllr/pll_nano_exact.v), in-package 32-bit SDRAM
    # (src/sdram.v NANO20K mapping), and pcetang's pin file. pll_12 / USB are not used.
    if {!$exact} { error "nano20k is exact-lock only: the stock frame buffer alone exceeds its 46 BSRAM." }
    set_device GW2AR-LV18QN88C8/I7 -device_version C
    add_file -type verilog "src/boards/nano20k.v"
    add_file -type cst "src/boards/nano20k.cst"
    add_file -type verilog "src/config_exact.v"
    add_file -type verilog "src/pllr/pll_nano_exact.v"
    # the same dual-purpose-pin set pcetang frees on this board
    set_option -use_mspi_as_gpio 1
    set_option -use_sspi_as_gpio 1
    set_option -use_done_as_gpio 1
    set_option -use_ready_as_gpio 1
    set_option -use_i2c_as_gpio 1
} elseif {$dev eq "primer25k"} {
    # Primer 25K (GW5A-25A). Same family and the same 50 MHz crystal as Console 60K, so the
    # exact-lock PLL is used unchanged; only the pin file and the I/O guards differ.
    # EXACT LOCK ONLY: the stock video path needs 77 BSRAM blocks and this device has 56.
    if {!$exact} { error "primer25k has 56 BSRAM; the stock video path needs 77. Use primer25k_exact." }
    set_device GW5A-LV25MG121NC1/I0 -device_version A
    add_file -type verilog "src/boards/primer25k.v"
    add_file -type cst "src/boards/primer25k.cst"
    add_file -type verilog "src/plla/pll_12.v"
    add_file -type verilog "src/config_exact.v"
    add_file -type verilog "src/plla/pll_exact.v"
    # This package has 68 regular I/O and the design needs more, so the dual-purpose pins
    # are freed as GPIO -- the same set pcetang uses on this board. Without these, the
    # crystal and part of the SDRAM bus land on dedicated pins and placement fails.
    set_option -use_mspi_as_gpio 1
    set_option -use_sspi_as_gpio 1
    set_option -use_done_as_gpio 1
    set_option -use_cpu_as_gpio 1
    set_option -use_ready_as_gpio 1
    set_option -use_i2c_as_gpio 1
    set_option -use_jtag_as_gpio 1
} elseif {$dev eq "console138k"} {
    set_device GW5AST-LV138PG484AC1/I0 -device_version B
    add_file -type cst "src/boards/console.cst"
    add_file -type verilog "src/pll/pll_12.v"
    add_file -type verilog "src/pll/pll_27.v"
    add_file -type verilog "src/pll/pll_53.v"
    add_file -type verilog "src/pll/pll_74.v"
} else {
    error "Unknown device $dev"
}
if {!$exact} { set_option -output_base_name smstang_${dev} }

add_file -type verilog "src/MC8123.v"
add_file -type verilog "src/SEGASYS1_PRGDEC.v"
add_file -type vhdl "src/vm2413/vm2413.vhd"
add_file -type vhdl "src/vm2413/attacktable.vhd"
add_file -type vhdl "src/vm2413/controller.vhd"
add_file -type vhdl "src/vm2413/envelopegenerator.vhd"
add_file -type vhdl "src/vm2413/envelopememory.vhd"
add_file -type vhdl "src/vm2413/feedbackmemory.vhd"
add_file -type vhdl "src/vm2413/lineartable.vhd"
add_file -type vhdl "src/vm2413/operator.vhd"
add_file -type vhdl "src/vm2413/opll.vhd"
add_file -type vhdl "src/vm2413/outputgenerator.vhd"
add_file -type vhdl "src/vm2413/outputmemory.vhd"
add_file -type vhdl "src/vm2413/phasegenerator.vhd"
add_file -type vhdl "src/vm2413/phasememory.vhd"
add_file -type vhdl "src/vm2413/registermemory.vhd"
add_file -type vhdl "src/vm2413/sinetable.vhd"
add_file -type vhdl "src/vm2413/slotcounter.vhd"
add_file -type vhdl "src/vm2413/temporalmixer.vhd"
add_file -type vhdl "src/vm2413/voicememory.vhd"
add_file -type vhdl "src/vm2413/voicerom.vhd"
# add_file -type verilog "src/VM2413/attacktable.sv"
# add_file -type verilog "src/VM2413/controller.sv"
# add_file -type verilog "src/VM2413/envelopegenerator.sv"
# add_file -type verilog "src/VM2413/envelopememory.sv"
# add_file -type verilog "src/VM2413/feedbackmemory.sv"
# add_file -type verilog "src/VM2413/lineartable.sv"
# add_file -type verilog "src/VM2413/operator.sv"
# add_file -type verilog "src/VM2413/opll.sv"
# add_file -type verilog "src/VM2413/outputgenerator.sv"
# add_file -type verilog "src/VM2413/outputmemory.sv"
# add_file -type verilog "src/VM2413/phasegenerator.sv"
# add_file -type verilog "src/VM2413/phasememory.sv"
# add_file -type verilog "src/VM2413/registermemory.sv"
# add_file -type verilog "src/VM2413/sinetable.sv"
# add_file -type verilog "src/VM2413/slotcounter.sv"
# add_file -type verilog "src/VM2413/temporalmixer.sv"
# add_file -type verilog "src/VM2413/vm2413.sv"
# add_file -type verilog "src/VM2413/voicememory.sv"
# add_file -type verilog "src/VM2413/voicerom.sv"
add_file -type verilog "src/audiomix.v"
add_file -type verilog "src/cheatcodes.sv"
add_file -type verilog "src/compressor.sv"
add_file -type verilog "src/dpram.v"
add_file -type verilog "src/hdmi2/audio_clock_regeneration_packet.sv"
add_file -type verilog "src/hdmi2/audio_info_frame.sv"
add_file -type verilog "src/hdmi2/audio_sample_packet.sv"
add_file -type verilog "src/hdmi2/auxiliary_video_information_info_frame.sv"
add_file -type verilog "src/hdmi2/hdmi.sv"
add_file -type verilog "src/hdmi2/packet_assembler.sv"
add_file -type verilog "src/hdmi2/packet_picker.sv"
add_file -type verilog "src/hdmi2/serializer.sv"
add_file -type verilog "src/hdmi2/source_product_description_info_frame.sv"
add_file -type verilog "src/hdmi2/tmds_channel.sv"
add_file -type verilog "src/hybrid_pwm_sd.v"
add_file -type verilog "src/io.v"
add_file -type verilog "src/iosys/controller_ds2.sv"
add_file -type verilog "src/iosys/dualshock_controller.v"
add_file -type verilog "src/iosys/gowin_dpb_menu.v"
add_file -type verilog "src/iosys/iosys_bl616.v"
add_file -type verilog "src/iosys/textdisp.v"
add_file -type verilog "src/iosys/uart_fixed.v"
add_file -type verilog "src/jt89/jt89.v"
add_file -type verilog "src/jt89/jt89_mixer.v"
add_file -type verilog "src/jt89/jt89_noise.v"
add_file -type verilog "src/jt89/jt89_tone.v"
add_file -type verilog "src/jt89/jt89_vol.v"
add_file -type verilog "src/lightgun.sv"
add_file -type verilog "src/parts.v"
add_file -type verilog "src/sdram.v"
if {$exact} {
    add_file -type verilog "src/sms2hdmi_sd.sv"
} else {
    add_file -type verilog "src/sms2hdmi.sv"
}
add_file -type verilog "src/smstang_top.sv"
add_file -type verilog "src/spram.v"
add_file -type verilog "src/sprom.v"
add_file -type verilog "src/system.v"
add_file -type verilog "src/t80/t80.v"
add_file -type verilog "src/t80/t80_alu.v"
add_file -type verilog "src/t80/t80_mcode.v"
add_file -type verilog "src/t80/t80_reg.v"
add_file -type verilog "src/t80/t80pa.v"
add_file -type verilog "src/t80/t80s.v"
add_file -type verilog "src/usb_hid_host.v"
add_file -type verilog "src/vdp.v"
add_file -type verilog "src/vdp_background.v"
add_file -type verilog "src/vdp_cram.v"
add_file -type verilog "src/vdp_main.v"
add_file -type verilog "src/vdp_sprite_shifter.v"
add_file -type verilog "src/vdp_sprites.v"
add_file -type verilog "src/video.v"

if {$exact && $dev eq "nano20k"} {
    add_file -type sdc "src/smstang_nano_exact.sdc"
} elseif {$exact} {
    add_file -type sdc "src/smstang_exact.sdc"
} else {
    add_file -type sdc "src/smstang.sdc"
}

set_option -synthesis_tool gowinsynthesis
set_option -top_module smstang_top
set_option -verilog_std sysv2017
set_option -vhdl_std vhd2019
set_option -ireg_in_iob 1
set_option -oreg_in_iob 1
set_option -ioreg_in_iob 1

set_option -place_option 2

run all
