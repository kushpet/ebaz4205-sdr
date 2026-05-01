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
set_property -dict [list \
    CONFIG.PCW_USE_S_AXI_HP0           {1} \
    CONFIG.PCW_USE_S_AXI_HP2           {1} \
    CONFIG.PCW_USE_M_AXI_GP0           {1} \
    CONFIG.PCW_FCLK_CLK0_ENABLE        {1} \
    CONFIG.PCW_FCLK0_PERIPHERAL_CLKSRC {IO PLL} \
    CONFIG.PCW_FCLK0_PERIPHERAL_DIVISOR0 {5} \
    CONFIG.PCW_FCLK0_PERIPHERAL_DIVISOR1 {2} \
    CONFIG.PCW_USE_FABRIC_INTERRUPT    {1} \
    CONFIG.PCW_IRQ_F2P_INTR            {1} \
    CONFIG.PCW_EN_CLK0_PORT            {1} \
    CONFIG.PCW_ENET0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_ENET0_ENET0_IO          {MIO 16 .. 27} \
    CONFIG.PCW_ENET0_GRP_MDIO_ENABLE   {1} \
    CONFIG.PCW_ENET0_GRP_MII_ENABLE    {1} \
    CONFIG.PCW_UART0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_UART0_UART0_IO          {MIO 14 .. 15} \
    CONFIG.PCW_DDR_RAM_HIGHADDR        {0x1FFFFFFF} \
] $ps7

apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO,DDR"} $ps7

set fclk0     [get_bd_pins ps7/FCLK_CLK0]
set fclk_rstn [get_bd_pins ps7/FCLK_RESET0_N]

################################################################
# 2. clk_60mhz MMCM (active-high reset; invert FCLK_RESET0_N)
################################################################
set rst_inv [create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 rst_inv]
set_property -dict [list CONFIG.C_OPERATION {not} CONFIG.C_SIZE {1}] $rst_inv
connect_bd_net $fclk_rstn [get_bd_pins rst_inv/Op1]

set mmcm [create_bd_cell -type module -reference clk_60mhz mmcm]
connect_bd_net $fclk0                        [get_bd_pins mmcm/clk_in]
connect_bd_net [get_bd_pins rst_inv/Res]     [get_bd_pins mmcm/reset]

set clk60   [get_bd_pins mmcm/clk_60mhz]
set clk25   [get_bd_pins mmcm/clk_25mhz]
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
set_property -dict [list \
    CONFIG.c_include_sg               {0} \
    CONFIG.c_sg_include_stscntrl_strm {0} \
    CONFIG.c_include_mm2s             {0} \
    CONFIG.c_include_s2mm             {1} \
    CONFIG.c_s2mm_burst_size          {16} \
    CONFIG.c_m_axi_s2mm_data_width    {64} \
    CONFIG.c_s2mm_data_width          {32} \
] $dma0

set dma1 [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 dma1]
set_property -dict [list \
    CONFIG.c_include_sg               {0} \
    CONFIG.c_sg_include_stscntrl_strm {0} \
    CONFIG.c_include_mm2s             {1} \
    CONFIG.c_include_s2mm             {0} \
    CONFIG.c_mm2s_burst_size          {16} \
    CONFIG.c_m_axi_mm2s_data_width    {64} \
    CONFIG.c_mm2s_data_width          {32} \
] $dma1

connect_bd_intf_net [get_bd_intf_pins axi_ic/M00_AXI]     [get_bd_intf_pins dma0/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins axi_ic/M01_AXI]     [get_bd_intf_pins dma1/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins dma0/M_AXI_S2MM]    [get_bd_intf_pins ps7/S_AXI_HP0]
connect_bd_intf_net [get_bd_intf_pins dma1/M_AXI_MM2S]    [get_bd_intf_pins ps7/S_AXI_HP2]

################################################################
# 6. DDC / DUC RTL modules (run at 60 MHz)
################################################################
set ddc [create_bd_cell -type module -reference ddc_top ddc]
set duc [create_bd_cell -type module -reference duc_top duc]

connect_bd_intf_net [get_bd_intf_pins axi_ic/M02_AXI] [get_bd_intf_pins ddc/s_axil]
connect_bd_intf_net [get_bd_intf_pins axi_ic/M03_AXI] [get_bd_intf_pins duc/s_axil]

connect_bd_net [get_bd_pins ddc/m_axis_tdata]        [get_bd_pins dma0/S_AXIS_S2MM_tdata]
connect_bd_net [get_bd_pins ddc/m_axis_tvalid]       [get_bd_pins dma0/S_AXIS_S2MM_tvalid]
connect_bd_net [get_bd_pins dma0/S_AXIS_S2MM_tready] [get_bd_pins ddc/m_axis_tready]

connect_bd_net [get_bd_pins dma1/M_AXIS_MM2S_tdata]  [get_bd_pins duc/s_axis_tdata]
connect_bd_net [get_bd_pins dma1/M_AXIS_MM2S_tvalid] [get_bd_pins duc/s_axis_tvalid]
connect_bd_net [get_bd_pins duc/s_axis_tready]       [get_bd_pins dma1/M_AXIS_MM2S_tready]

################################################################
# 7. Clocks: 100 MHz AXI fabric vs 60 MHz DSP fabric
################################################################
# 100 MHz AXI domain
foreach pin [list \
    ps7/M_AXI_GP0_ACLK ps7/S_AXI_HP0_ACLK ps7/S_AXI_HP2_ACLK \
    axi_ic/ACLK axi_ic/S00_ACLK axi_ic/M00_ACLK axi_ic/M01_ACLK \
    dma0/s_axi_lite_aclk dma0/m_axi_s2mm_aclk \
    dma1/s_axi_lite_aclk dma1/m_axi_mm2s_aclk] {
    connect_bd_net $fclk0 [get_bd_pins $pin]
}

# 60 MHz DSP/AXI-Lite domain (interconnect crosses the clock boundary)
connect_bd_net $clk60 [get_bd_pins axi_ic/M02_ACLK]
connect_bd_net $clk60 [get_bd_pins axi_ic/M03_ACLK]
connect_bd_net $clk60 [get_bd_pins ddc/clk]
connect_bd_net $clk60 [get_bd_pins duc/clk]

################################################################
# 8. Reset distribution
################################################################
foreach pin [list \
    axi_ic/ARESETN axi_ic/S00_ARESETN axi_ic/M00_ARESETN axi_ic/M01_ARESETN \
    dma0/axi_resetn dma1/axi_resetn] {
    connect_bd_net $aresetn_axi [get_bd_pins $pin]
}
connect_bd_net $aresetn_60 [get_bd_pins axi_ic/M02_ARESETN]
connect_bd_net $aresetn_60 [get_bd_pins axi_ic/M03_ARESETN]
connect_bd_net $aresetn_60 [get_bd_pins ddc/resetn]
connect_bd_net $aresetn_60 [get_bd_pins duc/resetn]

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

################################################################
# 11. External pins (physical I/O)
################################################################
make_bd_pins_external [get_bd_pins ddc/ADC]
make_bd_pins_external [get_bd_pins ddc/OTR]
make_bd_pins_external [get_bd_pins duc/DAC]
make_bd_pins_external [get_bd_pins duc/CLK_DAC]
make_bd_pins_external [get_bd_pins duc/PD]
make_bd_pins_external $clk60
make_bd_pins_external $clk25
make_bd_pins_external $locked
make_bd_pins_external $fclk_rstn

################################################################
validate_bd_design
save_bd_design
make_wrapper -files [get_files ${bd_name}.bd] -top
add_files -norecurse [glob ./[set bd_name]_wrapper.v]
set_property top sdr_top [current_fileset]
