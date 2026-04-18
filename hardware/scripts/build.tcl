set script_dir [file normalize [file dirname [info script]]]
set hw_dir [file normalize [file join $script_dir ".."]]
set proj_name "ebaz4205_sdr"
set proj_dir [file join $hw_dir "ebaz4205_sdr_vivado"]
set proj_file [file join $proj_dir "$proj_name.xpr"]

if {![file exists $proj_file]} {
    puts "ERROR: project file not found: $proj_file"
    exit 1
}

open_project $proj_file
update_compile_order -fileset sources_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} {
    puts "ERROR: synth_1 failed"
    close_project
    exit 1
}
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
if {[string first "write_bitstream Complete!" $impl_status] < 0} {
    puts "ERROR: impl_1 failed"
    close_project
    exit 1
}
close_project
exit 0
