# vitis_build.tcl — create Vitis platform + sdr_app from the .xsa.
#
# Builds a fresh workspace under firmware/vitis_ws containing:
#   - sdr_platform : freertos10_xilinx_domain (FreeRTOS 10) + lwip211
#                    (sockets API), stdout/stdin = ps7_uart_1, heap=1 MB
#   - sdr_app      : "Empty Application(C)" with our firmware/src tree
#                    soft-linked in
#
# Invoke (from any cwd):
#   xsct firmware/scripts/vitis_build.tcl
#
# After this you typically also run vitis_fsbl.tcl (adds a Zynq FSBL app
# in the same workspace), then bootgen on firmware/sd_boot/boot.bif.

set repo_root /home/user/GitHub/kushpet/ebaz4205-sdr
set xsa_file  $repo_root/hardware/ebaz4205_sdr.xsa
set ws_dir    $repo_root/firmware/vitis_ws
set src_dir   $repo_root/firmware/src

set platform_name sdr_platform
set app_name      sdr_app

file delete -force $ws_dir
file mkdir $ws_dir
setws $ws_dir

puts "==== Creating platform from $xsa_file ===="
platform create -name $platform_name \
    -hw $xsa_file \
    -proc ps7_cortexa9_0 \
    -os freertos10_xilinx \
    -no-boot-bsp

# "platform create" leaves the freertos domain active.
platform active $platform_name
set actual_domain [domain active]
puts "==== Active domain: $actual_domain ===="

puts "==== Adding lwIP and tuning the BSP ===="
bsp setlib -name lwip211
# RAW mode is the lwIP default and only works under standalone — switch
# to sockets API so it runs in its own tcpip_thread under FreeRTOS.
# NOTE: the value is the singular "SOCKET_API"; "SOCKETS_API" is wrong
# (Xilinx's BSP Tcl checks for the singular form).
bsp config api_mode SOCKET_API
bsp config use_axieth_on_zynq 0
bsp config use_emaclite_on_zynq 0

# EBAZ4205 console is UART1 (MIO 24/25), not UART0.
bsp config stdout ps7_uart_1
bsp config stdin  ps7_uart_1

# Default heap is 64 KB — way too small for FreeRTOS + lwIP + our worker
# tasks. Bump to 1 MB; we have 256 MB DDR.
bsp config total_heap_size 1048576

puts "==== Generating platform ===="
platform generate

puts "==== Creating application ===="
app create -name $app_name \
    -platform $platform_name \
    -domain   $actual_domain \
    -template "Empty Application(C)"

puts "==== Importing firmware sources ===="
importsources -name $app_name -path $src_dir -soft-link

app config -name $app_name -add include-path $src_dir
app config -name $app_name -add compiler-misc {-Wall -Wextra}
app config -name $app_name build-config release

puts "==== Building application ===="
app build -name $app_name

puts "==== Build done ===="
exit 0
