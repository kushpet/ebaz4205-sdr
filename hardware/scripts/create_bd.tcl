# hardware/scripts/create_bd.tcl
# Block Design: PS7 + AXI DMA x2 + DDC/DUC + MMCM clk_60mhz + 25 MHz to PHY
#
# Address map (also documented in CLAUDE.md):
#   0x4040_0000  AXI DMA0 (S2MM, ADC->DDR) lite      64 KB
#   0x4042_0000  AXI DMA1 (MM2S, DDR->DAC) lite      64 KB
#   0x43C0_0000  ddc_top  AXI-Lite                     4 KB
#   0x43C0_1000  duc_top  AXI-Lite                     4 KB
#
# Clock domains:
#   FCLK_CLK0 (100 MHz):    GP0, HP0, HP2, AXI Interconnect S00/M00/M01,
#                           DMA AXI sides
#   clk_60mhz:              DDC/DUC datapath + their AXI-Lite (M02/M03)

set project_name ebaz4205_sdr
set bd_name      system

create_bd_design $bd_name

################################################################
# 1. PS7
################################################################
set ps7 [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7]
# Use the board-agnostic preset, then override what we care about.
# GEM0 sits on MIO 16..27 (MII to IP101G) — that pin set is the MII mode.
# UART0 on MIO 14..15. FCLK0 = 100 MHz (default of the IP), FCLK3 unused
# in BD (the wrapper drives the 25 MHz refclk through the MMCM instead).
set_property -dict [list \
    CONFIG.PCW_USE_S_AXI_HP0               {1} \
    CONFIG.PCW_USE_S_AXI_HP2               {1} \
    CONFIG.PCW_USE_M_AXI_GP0               {1} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ    {100} \
    CONFIG.PCW_USE_FABRIC_INTERRUPT        {1} \
    CONFIG.PCW_IRQ_F2P_INTR                {1} \
    CONFIG.PCW_EN_CLK0_PORT                {1} \
    CONFIG.PCW_ENET0_PERIPHERAL_ENABLE   {1} \
    CONFIG.PCW_ENET0_ENET0_IO            {MIO 16 .. 27} \
    CONFIG.PCW_ENET0_GRP_MDIO_ENABLE     {1} \
    CONFIG.PCW_ENET0_GRP_MDIO_IO         {MIO 52 .. 53} \
    CONFIG.PCW_UART0_PERIPHERAL_ENABLE   {1} \
    CONFIG.PCW_UART0_UART0_IO            {MIO 14 .. 15} \
    CONFIG.PCW_DDR_RAM_HIGHADDR          {0x1FFFFFFF} \
] $ps7

apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO,DDR"} $ps7

set fclk0     [get_bd_pins ps7/FCLK_CLK0]
set fclk_rstn [get_bd_pins ps7/FCLK_RESET0_N]

################################################################
# 2. clk_wiz: 100 MHz -> 60 MHz (DSP) + 25 MHz (PHY refclk)
#    Use Xilinx IP rather than a hand-rolled MMCM module so that
#    output FREQ_HZ propagates correctly to downstream IPs.
################################################################
set mmcm [create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 mmcm]
set_property -dict [list \
    CONFIG.PRIMITIVE                {MMCM} \
    CONFIG.PRIM_IN_FREQ             {100.000} \
    CONFIG.CLKOUT1_USED             {true} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {60.000} \
    CONFIG.CLKOUT2_USED             {true} \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {25.000} \
    CONFIG.NUM_OUT_CLKS             {2} \
    CONFIG.RESET_TYPE               {ACTIVE_LOW} \
    CONFIG.RESET_PORT               {resetn} \
    CONFIG.USE_LOCKED               {true} \
] $mmcm

connect_bd_net $fclk0     [get_bd_pins mmcm/clk_in1]
connect_bd_net $fclk_rstn [get_bd_pins mmcm/resetn]

set clk60   [get_bd_pins mmcm/clk_out1]
set clk25   [get_bd_pins mmcm/clk_out2]
set locked  [get_bd_pins mmcm/locked]

################################################################
# 3. Resets
#   rst_axi  : 100 MHz domain (FCLK_CLK0)
#   rst_60   : 60 MHz domain  (clk_60mhz, gated by MMCM lock)
################################################################
set rst_axi [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_axi]
connect_bd_net $fclk0     [get_bd_pins rst_axi/slowest_sync_clk]
connect_bd_net $fclk_rstn [get_bd_pins rst_axi/ext_reset_in]
set aresetn_axi [get_bd_pins rst_axi/peripheral_aresetn]

set rst_60 [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_60]
connect_bd_net $clk60     [get_bd_pins rst_60/slowest_sync_clk]
connect_bd_net $fclk_rstn [get_bd_pins rst_60/ext_reset_in]
connect_bd_net $locked    [get_bd_pins rst_60/dcm_locked]
set aresetn_60 [get_bd_pins rst_60/peripheral_aresetn]

################################################################
# 4. AXI Interconnect
################################################################
set axi_ic [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_ic]
set_property CONFIG.NUM_SI {1} $axi_ic
set_property CONFIG.NUM_MI {4} $axi_ic
connect_bd_intf_net [get_bd_intf_pins ps7/M_AXI_GP0] [get_bd_intf_pins axi_ic/S00_AXI]

################################################################
# 5. AXI DMA0 (ADC, S2MM via HP0) and DMA1 (DAC, MM2S via HP2)
################################################################
set dma0 [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 dma0]
# axi_dma 7.1 in 2022.2 uses a single clock for AXI memory and AXI-Stream
# (c_prmry_is_aclk_async is read-only). To keep DSP at 60 MHz we insert
# axis_clock_converter blocks between DDC/DUC and the DMA stream sides.
set_property -dict [list \
    CONFIG.c_include_sg                {0} \
    CONFIG.c_sg_include_stscntrl_strm  {0} \
    CONFIG.c_include_mm2s              {0} \
    CONFIG.c_include_s2mm              {1} \
    CONFIG.c_s2mm_burst_size           {16} \
    CONFIG.c_m_axi_s2mm_data_width     {64} \
    CONFIG.c_s_axis_s2mm_tdata_width   {32} \
    CONFIG.c_addr_width                {32} \
] $dma0

set dma1 [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 dma1]
set_property -dict [list \
    CONFIG.c_include_sg                {0} \
    CONFIG.c_sg_include_stscntrl_strm  {0} \
    CONFIG.c_include_mm2s              {1} \
    CONFIG.c_include_s2mm              {0} \
    CONFIG.c_mm2s_burst_size           {16} \
    CONFIG.c_m_axi_mm2s_data_width     {64} \
    CONFIG.c_m_axis_mm2s_tdata_width   {32} \
    CONFIG.c_addr_width                {32} \
] $dma1

connect_bd_intf_net [get_bd_intf_pins axi_ic/M00_AXI]     [get_bd_intf_pins dma0/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins axi_ic/M01_AXI]     [get_bd_intf_pins dma1/S_AXI_LITE]

# PS7 S_AXI_HP* is AXI3, AXI DMA M_AXI is AXI4 — bridge through axi_protocol_convert
set conv0 [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_protocol_converter:2.1 conv0]
set conv1 [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_protocol_converter:2.1 conv1]

connect_bd_intf_net [get_bd_intf_pins dma0/M_AXI_S2MM] [get_bd_intf_pins conv0/S_AXI]
connect_bd_intf_net [get_bd_intf_pins conv0/M_AXI]     [get_bd_intf_pins ps7/S_AXI_HP0]
connect_bd_intf_net [get_bd_intf_pins dma1/M_AXI_MM2S] [get_bd_intf_pins conv1/S_AXI]
connect_bd_intf_net [get_bd_intf_pins conv1/M_AXI]     [get_bd_intf_pins ps7/S_AXI_HP2]

################################################################
# 6. DDC / DUC RTL modules (run at 60 MHz)
################################################################
set ddc [create_bd_cell -type module -reference ddc_top ddc]
set duc [create_bd_cell -type module -reference duc_top duc]

connect_bd_intf_net [get_bd_intf_pins axi_ic/M02_AXI] [get_bd_intf_pins ddc/s_axil]
connect_bd_intf_net [get_bd_intf_pins axi_ic/M03_AXI] [get_bd_intf_pins duc/s_axil]

# AXI-Stream cross-domain crossings: DDC/DUC at 60 MHz, DMA at 100 MHz.
# axis_clock_converter has independent s_axis_aclk / m_axis_aclk inputs.
set acc0 [create_bd_cell -type ip -vlnv xilinx.com:ip:axis_clock_converter:1.1 acc_rx]
set acc1 [create_bd_cell -type ip -vlnv xilinx.com:ip:axis_clock_converter:1.1 acc_tx]

connect_bd_intf_net [get_bd_intf_pins ddc/m_axis]   [get_bd_intf_pins acc_rx/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins acc_rx/M_AXIS] [get_bd_intf_pins dma0/S_AXIS_S2MM]
connect_bd_intf_net [get_bd_intf_pins dma1/M_AXIS_MM2S] [get_bd_intf_pins acc_tx/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins acc_tx/M_AXIS] [get_bd_intf_pins duc/s_axis]

################################################################
# 7. Clocks: 100 MHz AXI fabric vs 60 MHz DSP fabric
################################################################
# 100 MHz AXI fabric domain (PS, interconnect, DMAs, protocol converters,
# stream-side of clock converters that face the DMA)
foreach pin [list \
    ps7/M_AXI_GP0_ACLK ps7/S_AXI_HP0_ACLK ps7/S_AXI_HP2_ACLK \
    axi_ic/ACLK axi_ic/S00_ACLK axi_ic/M00_ACLK axi_ic/M01_ACLK \
    dma0/s_axi_lite_aclk dma0/m_axi_s2mm_aclk \
    dma1/s_axi_lite_aclk dma1/m_axi_mm2s_aclk \
    conv0/aclk conv1/aclk \
    acc_rx/m_axis_aclk acc_tx/s_axis_aclk] {
    connect_bd_net $fclk0 [get_bd_pins $pin]
}

# 60 MHz domain — DSP datapath, DDC/DUC AXI-Lite, AXIS-side of clock
# converters that face the DDC/DUC.
foreach pin [list \
    axi_ic/M02_ACLK axi_ic/M03_ACLK \
    ddc/clk duc/clk \
    acc_rx/s_axis_aclk acc_tx/m_axis_aclk] {
    connect_bd_net $clk60 [get_bd_pins $pin]
}

# Tag every clock-bearing pin/interface in the 60 MHz domain so auto_cc
# children inside the AXI Interconnect (and the axis_clock_converters)
# inherit the right value instead of the 10 MHz default.
foreach pin [list \
    ddc/clk duc/clk \
    axi_ic/M02_ACLK axi_ic/M03_ACLK \
    acc_rx/s_axis_aclk acc_tx/m_axis_aclk] {
    set_property CONFIG.FREQ_HZ 60000000 [get_bd_pins $pin]
}
foreach intf [list \
    ddc/s_axil duc/s_axil \
    ddc/m_axis duc/s_axis] {
    set_property CONFIG.FREQ_HZ 60000000 [get_bd_intf_pins $intf]
}

################################################################
# 8. Reset distribution
################################################################
foreach pin [list \
    axi_ic/ARESETN axi_ic/S00_ARESETN axi_ic/M00_ARESETN axi_ic/M01_ARESETN \
    dma0/axi_resetn dma1/axi_resetn \
    conv0/aresetn conv1/aresetn \
    acc_rx/m_axis_aresetn acc_tx/s_axis_aresetn] {
    connect_bd_net $aresetn_axi [get_bd_pins $pin]
}
foreach pin [list \
    axi_ic/M02_ARESETN axi_ic/M03_ARESETN \
    ddc/resetn duc/resetn \
    acc_rx/s_axis_aresetn acc_tx/m_axis_aresetn] {
    connect_bd_net $aresetn_60 [get_bd_pins $pin]
}

################################################################
# 9. Interrupts
################################################################
set irq_concat [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 irq_concat]
set_property CONFIG.NUM_PORTS {2} $irq_concat
connect_bd_net [get_bd_pins dma0/s2mm_introut] [get_bd_pins irq_concat/In0]
connect_bd_net [get_bd_pins dma1/mm2s_introut] [get_bd_pins irq_concat/In1]
connect_bd_net [get_bd_pins irq_concat/dout]   [get_bd_pins ps7/IRQ_F2P]

################################################################
# 10. Address map
################################################################
assign_bd_address [get_bd_addr_segs dma0/S_AXI_LITE/Reg] -offset 0x40400000 -range 64K
assign_bd_address [get_bd_addr_segs dma1/S_AXI_LITE/Reg] -offset 0x40420000 -range 64K
assign_bd_address [get_bd_addr_segs ddc/s_axil/reg0]     -offset 0x43C00000 -range 4K
assign_bd_address [get_bd_addr_segs duc/s_axil/reg0]     -offset 0x43C01000 -range 4K

# Map PS DDR into both DMAs' address spaces (whole 512 MB low region)
assign_bd_address [get_bd_addr_segs ps7/S_AXI_HP0/HP0_DDR_LOWOCM] \
    -target_address_space /dma0/Data_S2MM -offset 0x00000000 -range 512M
assign_bd_address [get_bd_addr_segs ps7/S_AXI_HP2/HP2_DDR_LOWOCM] \
    -target_address_space /dma1/Data_MM2S -offset 0x00000000 -range 512M

################################################################
# 11. External pins (physical I/O)
################################################################
make_bd_pins_external [get_bd_pins ddc/ADC]
make_bd_pins_external [get_bd_pins ddc/OTR]
make_bd_pins_external [get_bd_pins duc/DAC]
make_bd_pins_external [get_bd_pins duc/CLK_DAC]
make_bd_pins_external [get_bd_pins duc/PD]

# Internal-driver pins (clk60/clk25/locked/fclk_resetn) need explicit BD
# ports — make_bd_pins_external silently skips pins that are already
# driving something inside the BD.
create_bd_port -dir O clk_60mhz_0
create_bd_port -dir O clk_25mhz_0
create_bd_port -dir O mmcm_locked_0
create_bd_port -dir O fclk_resetn_0
connect_bd_net $clk60     [get_bd_ports clk_60mhz_0]
connect_bd_net $clk25     [get_bd_ports clk_25mhz_0]
connect_bd_net $locked    [get_bd_ports mmcm_locked_0]
connect_bd_net $fclk_rstn [get_bd_ports fclk_resetn_0]

################################################################
validate_bd_design
save_bd_design
make_wrapper -files [get_files ${bd_name}.bd] -top
# Wrapper sits under <proj>.gen/sources_1/bd/<bd_name>/hdl/<bd_name>_wrapper.v
set proj_dir [get_property DIRECTORY [current_project]]
set wrap_file [file join $proj_dir [get_property NAME [current_project]].gen \
                  sources_1 bd $bd_name hdl ${bd_name}_wrapper.v]
add_files -norecurse $wrap_file
set_property top sdr_top [current_fileset]
update_compile_order -fileset sources_1
