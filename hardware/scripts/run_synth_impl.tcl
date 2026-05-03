# run_synth_impl.tcl — full FPGA build: synth_1 + impl_1 → bitstream.
# Reports run status so a batch invocation can detect failure.
#
# Invoke:
#   vivado -mode batch -nojournal -nolog -source run_synth_impl.tcl

set hw_dir [file normalize [file join [file dirname [info script]] ".."]]
open_project [file join $hw_dir ebaz4205_sdr_vivado ebaz4205_sdr.xpr]
update_compile_order -fileset sources_1

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
