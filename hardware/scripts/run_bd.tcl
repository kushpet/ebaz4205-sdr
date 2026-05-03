# run_bd.tcl — open the Vivado project that create_project.tcl made,
# source create_bd.tcl into it (which builds the Block Design + wrapper),
# then close. Must be run AFTER create_project.tcl.
#
# Invoke:
#   vivado -mode batch -nojournal -nolog -source run_bd.tcl

set hw_dir [file normalize [file join [file dirname [info script]] ".."]]
set proj_file [file join $hw_dir ebaz4205_sdr_vivado ebaz4205_sdr.xpr]

open_project $proj_file
cd [file join $hw_dir ebaz4205_sdr_vivado]
source [file join $hw_dir scripts create_bd.tcl]
update_compile_order -fileset sources_1
close_project
exit
