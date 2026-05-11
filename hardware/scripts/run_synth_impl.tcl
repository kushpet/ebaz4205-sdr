# run_synth_impl.tcl — full FPGA build: synth_1 + impl_1 → bitstream.
# Reports run status so a batch invocation can detect failure.
#
# Invoke:
#   vivado -mode batch -nojournal -nolog -source run_synth_impl.tcl

set hw_dir [file normalize [file join [file dirname [info script]] ".."]]
open_project [file join $hw_dir ebaz4205_sdr_vivado ebaz4205_sdr.xpr]

# Ensure hardware/rtl/ is on the preprocessor include path so nco_direct
# can `\`include "nco_lut_init.vh"` from sibling-file. Without this OOC
# IP synthesis (which runs from .runs/system_*/) can't find the file.
# Vivado also requires the .vh file itself to be added to the project as
# a "Verilog Header" — include_dirs alone isn't enough (errors with
# filemgmt 56-591). Add idempotently.
set_property include_dirs [list [file join $hw_dir rtl]] [get_filesets sources_1]
set lut_file [file join $hw_dir rtl nco_lut_init.vh]
if {[llength [get_files -quiet [file tail $lut_file]]] == 0} {
    add_files -norecurse $lut_file
    set_property file_type "Verilog Header" [get_files $lut_file]
}

update_compile_order -fileset sources_1

# RTL inside ddc_top / duc_top is wrapped as Vivado IP and synthesized
# out-of-context. Two caches survive a plain reset_run synth_1:
#   1. Per-IP OOC runs (system_ddc_0_synth_1, system_duc_0_synth_1).
#   2. The IP synthesis cache directory (.cache/ip), keyed by hashes
#      that don't track underlying RTL files reliably.
# Without invalidating both, edits to hb_fir_decimator.v / ddc_top.v /
# adc_if.v / etc. silently don't reach the bitstream — see CLAUDE.md
# "OOC + IP-cache trap" memory. Always wipe both before rebuild.
set ip_cache [file join $hw_dir ebaz4205_sdr_vivado ebaz4205_sdr.cache ip]
if {[file isdirectory $ip_cache]} {
    puts "Wiping IP synthesis cache: $ip_cache"
    file delete -force $ip_cache
}
config_ip_cache -disable_cache
foreach run {system_ddc_0_synth_1 system_duc_0_synth_1} {
    if {[llength [get_runs -quiet $run]] > 0} {
        puts "Resetting OOC run: $run"
        reset_run $run
    }
}
reset_run impl_1
reset_run synth_1

launch_runs synth_1 -jobs 4
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
puts "synth_1 status: $synth_status"
if {$synth_status ne "synth_design Complete!"} {
    puts "ERROR: synth_1 did not complete cleanly."
    close_project
    exit 1
}

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
puts "impl_1 status: $impl_status"
if {[string first "write_bitstream Complete!" $impl_status] < 0} {
    puts "ERROR: impl_1 did not complete cleanly."
    close_project
    exit 1
}

puts "==== build OK; bit at impl_1/sdr_top.bit ===="
close_project
exit 0
