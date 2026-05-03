# elab_check.tcl — fast RTL elaboration smoke test.
# Reads every leaf module and elaborates each in turn. Catches Verilog
# syntax errors and port-mismatch issues without building a project.
# Use this when iterating on RTL before launching a full synth.
#
# Invoke:
#   vivado -mode batch -nojournal -nolog -source elab_check.tcl

set rtl_dir [file normalize [file join [file dirname [info script]] ".." rtl]]

set rtl_files {
    clk_60mhz.v
    adc_if.v
    dac_if.v
    nco.v
    complex_mixer.v
    cic_decimator.v
    cic_interpolator.v
    hb_fir_decimator.v
    hb_fir_interpolator.v
    ddc_top.v
    duc_top.v
}

create_project -in_memory -part xc7z010clg400-1
foreach f $rtl_files {
    read_verilog [file join $rtl_dir $f]
}

# Elaborate each top in turn (sdr_top depends on the BD wrapper, skip it)
foreach top {ddc_top duc_top adc_if dac_if nco complex_mixer cic_decimator
             cic_interpolator hb_fir_decimator hb_fir_interpolator clk_60mhz} {
    puts "==== Elaborating $top ===="
    if {[catch {synth_design -rtl -top $top -name rtl_$top} err]} {
        puts "ELAB FAIL on $top: $err"
        exit 1
    }
}
puts "==== All modules elaborated cleanly ===="
exit 0
