set script_dir [file normalize [file dirname [info script]]]
set hw_dir [file normalize [file join $script_dir ".."]]
set proj_name "ebaz4205_sdr"
set proj_dir [file join $hw_dir "ebaz4205_sdr_vivado"]
set rtl_dir [file join $hw_dir "rtl"]
set xdc_file [file join $hw_dir "constraints" "ebaz4205.xdc"]

file mkdir $proj_dir
create_project $proj_name $proj_dir -part xc7z010clg400-1 -force
set_property target_language Verilog [current_project]

set rtl_files [glob -nocomplain -directory $rtl_dir *.v]
if {[llength $rtl_files] > 0} {
    add_files $rtl_files
}

if {[file exists $xdc_file]} {
    add_files -fileset constrs_1 $xdc_file
}

set_property top sdr_top [current_fileset]
update_compile_order -fileset sources_1
close_project
exit
