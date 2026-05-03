# export_xsa.tcl — write the hardware handoff (.xsa) for Vitis/xsct.
# Includes the bitstream so the FSBL can load it from the SD card image.
#
# Invoke:
#   vivado -mode batch -nojournal -nolog -source export_xsa.tcl

set hw_dir [file normalize [file join [file dirname [info script]] ".."]]
open_project [file join $hw_dir ebaz4205_sdr_vivado ebaz4205_sdr.xpr]
write_hw_platform -fixed -include_bit -force \
    -file [file join $hw_dir ebaz4205_sdr.xsa]
close_project
exit
