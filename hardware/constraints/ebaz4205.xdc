## EBAZ4205: DAC (DATA1/2) + ADC (DATA3) + CLK + PD
## Все пины взяты из EBAZ4205-ADC-DAC.md, банки PL с VCCO=3.3В.

## DAC (DATA1, DATA2)
set_property PACKAGE_PIN H16 [get_ports DAC[13]]
set_property PACKAGE_PIN B19 [get_ports DAC[12]]
set_property PACKAGE_PIN B20 [get_ports DAC[11]]
set_property PACKAGE_PIN C20 [get_ports DAC[10]]
set_property PACKAGE_PIN D18 [get_ports DAC[9]]
set_property PACKAGE_PIN H17 [get_ports DAC[8]]
set_property PACKAGE_PIN D19 [get_ports DAC[7]]
set_property PACKAGE_PIN D20 [get_ports DAC[6]]
set_property PACKAGE_PIN E19 [get_ports DAC[5]]
set_property PACKAGE_PIN H18 [get_ports DAC[4]]
set_property PACKAGE_PIN K17 [get_ports DAC[3]]
set_property PACKAGE_PIN F20 [get_ports DAC[2]]
set_property PACKAGE_PIN F19 [get_ports DAC[1]]
set_property PACKAGE_PIN G20 [get_ports DAC[0]]

set_property PACKAGE_PIN A20 [get_ports CLK_DAC]
set_property PACKAGE_PIN J18 [get_ports PD]

## ADC (DATA3)
set_property PACKAGE_PIN N20 [get_ports ADC[0]]
set_property PACKAGE_PIN P18 [get_ports ADC[1]]
set_property PACKAGE_PIN M17 [get_ports ADC[2]]
set_property PACKAGE_PIN N17 [get_ports ADC[3]]
set_property PACKAGE_PIN R19 [get_ports ADC[4]]
set_property PACKAGE_PIN P20 [get_ports ADC[5]]
set_property PACKAGE_PIN T20 [get_ports ADC[6]]
set_property PACKAGE_PIN R18 [get_ports ADC[7]]
set_property PACKAGE_PIN T19 [get_ports ADC[8]]
set_property PACKAGE_PIN P19 [get_ports ADC[9]]
set_property PACKAGE_PIN U19 [get_ports ADC[10]]
set_property PACKAGE_PIN U20 [get_ports ADC[11]]

set_property PACKAGE_PIN V20 [get_ports OTR]
set_property PACKAGE_PIN M19 [get_ports CLK_ADC]

## IOSTANDARD для этих сигналов
set_property IOSTANDARD LVCMOS33 [get_ports { \
    DAC[0] DAC[1] DAC[2] DAC[3] DAC[4] DAC[5] DAC[6] DAC[7] DAC[8] DAC[9] DAC[10] DAC[11] DAC[12] DAC[13] \
    CLK_DAC PD \
    ADC[0] ADC[1] ADC[2] ADC[3] ADC[4] ADC[5] ADC[6] ADC[7] ADC[8] ADC[9] ADC[10] ADC[11] \
    OTR CLK_ADC \
}]

## EBAZ4205: GEM0 MII pins live on PS MIO 16..27 (data/control)
## and MIO 52..53 (MDIO) — they are PS-internal, NOT PL pins.
## PS7 routes them via FIXED_IO; no XDC entries are required here.

## EBAZ4205: User LEDs (PL)

set_property PACKAGE_PIN W13 [get_ports LED_GREEN]   ;# зелёный LED
set_property PACKAGE_PIN W14 [get_ports LED_RED]     ;# красный LED

set_property IOSTANDARD LVCMOS33 [get_ports { LED_GREEN LED_RED }]

## EBAZ4205: PHY refclk to IP101G XI (pin U18, 25 MHz)
set_property PACKAGE_PIN U18 [get_ports PHY_REFCLK_25MHZ]
set_property IOSTANDARD LVCMOS33 [get_ports PHY_REFCLK_25MHZ]

## Generated clocks (declared so timing closure is checked)
## clk_60mhz, clk_25mhz are generated inside the BD's MMCM (clk_60mhz module).
## Vivado picks them up from the MMCM primitive automatically.
