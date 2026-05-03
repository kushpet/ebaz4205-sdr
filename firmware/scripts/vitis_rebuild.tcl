# vitis_rebuild.tcl — incremental relink of sdr_app.
# Use after editing firmware/src/*.c when the platform/.xsa is unchanged.
# (xsct's "app build" can hang in some setups; if it does, just run
# `make all` directly in firmware/vitis_ws/sdr_app/Release/ instead.)
#
# Invoke:
#   xsct firmware/scripts/vitis_rebuild.tcl

set repo_root /home/user/GitHub/kushpet/ebaz4205-sdr
set ws_dir    $repo_root/firmware/vitis_ws
setws $ws_dir
app build -name sdr_app
exit 0
