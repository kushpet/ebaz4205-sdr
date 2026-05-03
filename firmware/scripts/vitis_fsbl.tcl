# vitis_fsbl.tcl — add a Zynq FSBL application alongside sdr_app.
#
# Adds a "standalone_domain" to the existing sdr_platform, sets up the
# xilffs (FAT) library required by the FSBL template, then creates and
# builds sdr_fsbl using the "Zynq FSBL" template.
#
# Run AFTER vitis_build.tcl. Invoke (from any cwd):
#   xsct firmware/scripts/vitis_fsbl.tcl
#
# Output: firmware/vitis_ws/sdr_fsbl/Release/sdr_fsbl.elf — used by
# bootgen as the bootloader partition in BOOT.bin.

set repo_root /home/user/GitHub/kushpet/ebaz4205-sdr
set ws_dir    $repo_root/firmware/vitis_ws

setws $ws_dir
platform active sdr_platform

# Create the standalone domain only if it doesn't already exist.
set has_standalone 0
foreach d [domain list] {
    set name [lindex [split $d] 0]
    if {[string match "*standalone*" $name]} { set has_standalone 1 }
}
if {!$has_standalone} {
    puts "==== Creating standalone domain on ps7_cortexa9_0 ===="
    domain create -name standalone_domain \
        -display-name standalone_domain \
        -os standalone -proc ps7_cortexa9_0 \
        -arch {32-bit}
}

# The Zynq FSBL template needs xilffs in the BSP — for reading BOOT.bin
# partitions off the FAT32 SD card.
domain active standalone_domain
bsp setlib -name xilffs

platform generate

puts "==== Creating FSBL app ===="
app create -name sdr_fsbl \
    -platform sdr_platform \
    -domain   standalone_domain \
    -template "Zynq FSBL"

app config -name sdr_fsbl build-config release

puts "==== Building FSBL ===="
app build -name sdr_fsbl

puts "==== Done ===="
exit 0
