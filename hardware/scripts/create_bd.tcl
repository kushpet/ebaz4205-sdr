# hardware/scripts/create_bd.tcl
# Block Design: PS7 + AXI DMA x2 + DDC/DUC
# DDC ports: clk, resetn, ADC[11:0], OTR, s_axil_*, m_axis_tdata[31:0], m_axis_tvalid, m_axis_tready
# DUC ports: clk, resetn, s_axis_tdata[31:0], s_axis_tvalid, s_axis_tready, s_axil_*, DAC[13:0], CLK_DAC, PD

set project_name ebaz4205_sdr
set bd_name system

create_bd_design $bd_name

################################################################
# PS7
################################################################
set ps7 [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7]
set_property -dict [list \
    CONFIG.PCW_USE_S_AXI_HP0       {1} \
    CONFIG.PCW_USE_S_AXI_HP2       {1} \
    CONFIG.PCW_USE_M_AXI_GP0       {1} \
    CONFIG.PCW_FCLK_CLK0_ENABLE    {1} \
    CONFIG.PCW_FCLK_CLK3_ENABLE    {1} \
    CONFIG.PCW_FCLK0_PERIPHERAL_CLKSRC {IO PLL} \
    CONFIG.PCW_FCLK0_PERIPHERAL_DIVISOR0 {5} \
    CONFIG.PCW_FCLK0_PERIPHERAL_DIVISOR1 {2} \
    CONFIG.PCW_FCLK3_PERIPHERAL_CLKSRC {IO PLL} \
    CONFIG.PCW_FCLK3_PERIPHERAL_DIVISOR0 {20} \
    CONFIG.PCW_FCLK3_PERIPHERAL_DIVISOR1 {2} \
    CONFIG.PCW_USE_FABRIC_INTERRUPT {1} \
    CONFIG.PCW_IRQ_F2P_INTR        {1} \
    CONFIG.PCW_EN_CLK0_PORT        {1} \
    CONFIG.PCW_EN_CLK3_PORT        {1} \
    CONFIG.PCW_ENET0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_ENET0_ENET0_IO      {MIO 16 .. 27} \
    CONFIG.PCW_ENET0_GRP_MDIO_ENABLE {1} \
    CONFIG.PCW_ENET0_GRP_MII_ENABLE {1} \
    CONFIG.PCW_UART0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_UART0_UART0_IO      {MIO 14 .. 15} \
    CONFIG.PCW_DDR_RAM_HIGHADDR    {0x1FFFFFFF} \
] $ps7

apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO,DDR"} $ps7

################################################################
# AXI Interconnect (GP0 master -> DMA control + DDC/DUC AXI-Lite)
################################################################
set axi_ic [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_ic]
set_property CONFIG.NUM_SI {1} $axi_ic
set_property CONFIG.NUM_MI {3} $axi_ic

connect_bd_intf_net [get_bd_intf_pins ps7/M_AXI_GP0] \
    [get_bd_intf_pins axi_ic/S00_AXI]

################################################################
# AXI DMA 0 — ADC path (S2MM: DDC -> DDR via HP0)
################################################################
set dma0 [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 dma0]
set_property -dict [list \
    CONFIG.c_include_sg          {0} \
    CONFIG.c_sg_include_stscntrl_strm {0} \
    CONFIG.c_include_mm2s        {0} \
    CONFIG.c_include_s2mm        {1} \
    CONFIG.c_s2mm_burst_size     {16} \
    CONFIG.c_m_axi_s2mm_data_width {64} \
    CONFIG.c_s2mm_data_width     {32} \
] $dma0

# AXI DMA 1 — DAC path (MM2S: DDR -> DUC via HP2)
set dma1 [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 dma1]
set_property -dict [list \
    CONFIG.c_include_sg          {0} \
    CONFIG.c_sg_include_stscntrl_strm {0} \
    CONFIG.c_include_mm2s        {1} \
    CONFIG.c_include_s2mm        {0} \
    CONFIG.c_mm2s_burst_size     {16} \
    CONFIG.c_m_axi_mm2s_data_width {64} \
    CONFIG.c_mm2s_data_width     {32} \
] $dma1

# DMA control via GP0
connect_bd_intf_net [get_bd_intf_pins axi_ic/M00_AXI] \
    [get_bd_intf_pins dma0/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins axi_ic/M01_AXI] \
    [get_bd_intf_pins dma1/S_AXI_LITE]

# DMA memory — HP0 (S2MM) и HP2 (MM2S)
connect_bd_intf_net [get_bd_intf_pins dma0/M_AXI_S2MM] \
    [get_bd_intf_pins ps7/S_AXI_HP0]
connect_bd_intf_net [get_bd_intf_pins dma1/M_AXI_MM2S] \
    [get_bd_intf_pins ps7/S_AXI_HP2]

################################################################
# DDC top (RTL module)
################################################################
set ddc [create_bd_cell -type module -reference ddc_top ddc]

# DUC top (RTL module)
set duc [create_bd_cell -type module -reference duc_top duc]

################################################################
# AXI-Lite -> DDC/DUC регистры NCO/CIC @ 0x43C0_0000
# DDC: 0x43C0_0000 (+0x10), DUC: 0x43C0_0010 (+0x10)
################################################################
connect_bd_intf_net [get_bd_intf_pins axi_ic/M02_AXI] \
    [get_bd_intf_pins ddc/s_axil]

# Для DUC — второй мастер, добавить порт в интерконнект
set_property CONFIG.NUM_MI {4} $axi_ic
connect_bd_intf_net [get_bd_intf_pins axi_ic/M03_AXI] \
    [get_bd_intf_pins duc/s_axil]

################################################################
# AXI-Stream: DDC -> DMA0 S2MM
################################################################
connect_bd_net [get_bd_pins ddc/m_axis_tdata]  [get_bd_pins dma0/S_AXIS_S2MM_tdata]
connect_bd_net [get_bd_pins ddc/m_axis_tvalid] [get_bd_pins dma0/S_AXIS_S2MM_tvalid]
connect_bd_net [get_bd_pins dma0/S_AXIS_S2MM_tready] [get_bd_pins ddc/m_axis_tready]

# AXI-Stream: DMA1 MM2S -> DUC
connect_bd_net [get_bd_pins dma1/M_AXIS_MM2S_tdata]  [get_bd_pins duc/s_axis_tdata]
connect_bd_net [get_bd_pins dma1/M_AXIS_MM2S_tvalid] [get_bd_pins duc/s_axis_tvalid]
connect_bd_net [get_bd_pins duc/s_axis_tready] [get_bd_pins dma1/M_AXIS_MM2S_tready]

################################################################
# Clocks
# FCLK_CLK0 = 100 MHz -> GP0, HP0, HP2, DMA AXI-Lite, Interconnect
# FCLK_CLK3 = 25 МГц (зарезервирован)
# DDC/DUC работают на clk=60 МГц (внешний от ADC CLK через буфер)
# Здесь для упрощения BD: ddc.clk / duc.clk -> FCLK_CLK0 (100 МГц)
# Реальная 60 МГц подаётся через top-level constraint/wrapper
################################################################
set fclk0 [get_bd_pins ps7/FCLK_CLK0]

connect_bd_net $fclk0 [get_bd_pins axi_ic/ACLK]
connect_bd_net $fclk0 [get_bd_pins axi_ic/S00_ACLK]
connect_bd_net $fclk0 [get_bd_pins axi_ic/M00_ACLK]
connect_bd_net $fclk0 [get_bd_pins axi_ic/M01_ACLK]
connect_bd_net $fclk0 [get_bd_pins axi_ic/M02_ACLK]
connect_bd_net $fclk0 [get_bd_pins axi_ic/M03_ACLK]
connect_bd_net $fclk0 [get_bd_pins ps7/M_AXI_GP0_ACLK]
connect_bd_net $fclk0 [get_bd_pins ps7/S_AXI_HP0_ACLK]
connect_bd_net $fclk0 [get_bd_pins ps7/S_AXI_HP2_ACLK]
connect_bd_net $fclk0 [get_bd_pins dma0/s_axi_lite_aclk]
connect_bd_net $fclk0 [get_bd_pins dma0/m_axi_s2mm_aclk]
connect_bd_net $fclk0 [get_bd_pins dma1/s_axi_lite_aclk]
connect_bd_net $fclk0 [get_bd_pins dma1/m_axi_mm2s_aclk]

# DDC/DUC clock: в BD используется FCLK_CLK0;
# фактический 60 МГц подаётся через XDC/wrapper-порт clk_60mhz
connect_bd_net $fclk0 [get_bd_pins ddc/clk]
connect_bd_net $fclk0 [get_bd_pins duc/clk]

################################################################
# Resets
################################################################
set rst_gen [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_gen]
connect_bd_net $fclk0 [get_bd_pins rst_gen/slowest_sync_clk]
connect_bd_net [get_bd_pins ps7/FCLK_RESET0_N] [get_bd_pins rst_gen/ext_reset_in]

set aresetn [get_bd_pins rst_gen/peripheral_aresetn]
connect_bd_net $aresetn [get_bd_pins axi_ic/ARESETN]
connect_bd_net $aresetn [get_bd_pins axi_ic/S00_ARESETN]
connect_bd_net $aresetn [get_bd_pins axi_ic/M00_ARESETN]
connect_bd_net $aresetn [get_bd_pins axi_ic/M01_ARESETN]
connect_bd_net $aresetn [get_bd_pins axi_ic/M02_ARESETN]
connect_bd_net $aresetn [get_bd_pins axi_ic/M03_ARESETN]
connect_bd_net $aresetn [get_bd_pins dma0/axi_resetn]
connect_bd_net $aresetn [get_bd_pins dma1/axi_resetn]
connect_bd_net $aresetn [get_bd_pins ddc/resetn]
connect_bd_net $aresetn [get_bd_pins duc/resetn]

################################################################
# Interrupts DMA -> PS GIC (IRQ_F2P[1:0])
# dma0: s2mm_introut -> IRQ_F2P[0]
# dma1: mm2s_introut -> IRQ_F2P[1]
################################################################
set irq_concat [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 irq_concat]
set_property CONFIG.NUM_PORTS {2} $irq_concat

connect_bd_net [get_bd_pins dma0/s2mm_introut] [get_bd_pins irq_concat/In0]
connect_bd_net [get_bd_pins dma1/mm2s_introut]  [get_bd_pins irq_concat/In1]
connect_bd_net [get_bd_pins irq_concat/dout]     [get_bd_pins ps7/IRQ_F2P]

################################################################
# Address map
# dma0 S_AXI_LITE  : 0x4040_0000  size 64K
# dma1 S_AXI_LITE  : 0x4042_0000  size 64K
# ddc  s_axil      : 0x43C0_0000  size 4K
# duc  s_axil      : 0x43C0_1000  size 4K
################################################################
assign_bd_address [get_bd_addr_segs dma0/S_AXI_LITE/Reg] -offset 0x40400000 -range 64K
assign_bd_address [get_bd_addr_segs dma1/S_AXI_LITE/Reg] -offset 0x40420000 -range 64K
assign_bd_address [get_bd_addr_segs ddc/s_axil/reg0]     -offset 0x43C00000 -range 4K
assign_bd_address [get_bd_addr_segs duc/s_axil/reg0]     -offset 0x43C01000 -range 4K

################################################################
# External ports (ADC/DAC физические пины — через wrapper)
################################################################
make_bd_pins_external [get_bd_pins ddc/ADC]
make_bd_pins_external [get_bd_pins ddc/OTR]
make_bd_pins_external [get_bd_pins duc/DAC]
make_bd_pins_external [get_bd_pins duc/CLK_DAC]
make_bd_pins_external [get_bd_pins duc/PD]

################################################################
validate_bd_design
save_bd_design
make_wrapper -files [get_files ${bd_name}.bd] -top
add_files -norecurse [glob ./[set bd_name]_wrapper.v]
set_property top ${bd_name}_wrapper [current_fileset]
