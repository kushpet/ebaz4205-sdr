## EBAZ4205: DAC (DATA1/2) + ADC (DATA3) + CLK + PD
## Все пины взяты из EBAZ4205-ADC-DAC.md, банки PL с VCCO=3.3В.

## DAC (DATA1, DATA2)
set_property PACKAGE_PIN H16 [get_ports DAC0]
set_property PACKAGE_PIN B19 [get_ports DAC1]
set_property PACKAGE_PIN B20 [get_ports DAC2]
set_property PACKAGE_PIN C20 [get_ports DAC3]
set_property PACKAGE_PIN D18 [get_ports DAC4]
set_property PACKAGE_PIN H17 [get_ports DAC5]
set_property PACKAGE_PIN D19 [get_ports DAC6]
set_property PACKAGE_PIN D20 [get_ports DAC7]
set_property PACKAGE_PIN E19 [get_ports DAC8]
set_property PACKAGE_PIN H18 [get_ports DAC9]
set_property PACKAGE_PIN K17 [get_ports DAC10]
set_property PACKAGE_PIN F20 [get_ports DAC11]
set_property PACKAGE_PIN F19 [get_ports DAC12]
set_property PACKAGE_PIN G20 [get_ports DAC13]

set_property PACKAGE_PIN A20 [get_ports CLK_DAC]
set_property PACKAGE_PIN J18 [get_ports PD]

## ADC (DATA3)
set_property PACKAGE_PIN N20 [get_ports ADC0]
set_property PACKAGE_PIN P18 [get_ports ADC1]
set_property PACKAGE_PIN M17 [get_ports ADC2]
set_property PACKAGE_PIN N17 [get_ports ADC3]
set_property PACKAGE_PIN R19 [get_ports ADC4]
set_property PACKAGE_PIN P20 [get_ports ADC5]
set_property PACKAGE_PIN T20 [get_ports ADC6]
set_property PACKAGE_PIN R18 [get_ports ADC7]
set_property PACKAGE_PIN T19 [get_ports ADC8]
set_property PACKAGE_PIN P19 [get_ports ADC9]
set_property PACKAGE_PIN U19 [get_ports ADC10]
set_property PACKAGE_PIN U20 [get_ports ADC11]

set_property PACKAGE_PIN V20 [get_ports OTR]
set_property PACKAGE_PIN M19 [get_ports CLK_ADC]

## IOSTANDARD для этих сигналов
set_property IOSTANDARD LVCMOS33 [get_ports { \
    DAC0 DAC1 DAC2 DAC3 DAC4 DAC5 DAC6 DAC7 DAC8 DAC9 DAC10 DAC11 DAC12 DAC13 \
    CLK_DAC PD \
    ADC0 ADC1 ADC2 ADC3 ADC4 ADC5 ADC6 ADC7 ADC8 ADC9 ADC10 ADC11 \
    OTR CLK_ADC \
}]

## EBAZ4205: GEM0 MII (через IP101GA U24, банк 34)

## TX
set_property PACKAGE_PIN W19 [get_ports GEM0_TXEN0]   	;# TXEN0
set_property PACKAGE_PIN W18 [get_ports GEM0_TXD0[0]]   	;# TXD0[0]
set_property PACKAGE_PIN Y18 [get_ports GEM0_TXD0[1]]   	;# TXD0[1]
set_property PACKAGE_PIN V18 [get_ports GEM0_TXD0[2]]   	;# TXD0[2]
set_property PACKAGE_PIN Y19 [get_ports GEM0_TXD0[3]]	;# TXD0[3]
set_property PACKAGE_PIN U15 [get_ports GEM0_TXCLK0]  	;# TXCLK0

## RX
set_property PACKAGE_PIN U14 [get_ports GEM0_RXCLK0]		;# RXCLK0
set_property PACKAGE_PIN W16 [get_ports GEM0_RXDV0]		;# RXDV0
set_property PACKAGE_PIN Y16 [get_ports GEM0_RXD0[0]]	;# RXD0[0]
set_property PACKAGE_PIN V16 [get_ports GEM0_RXD0[1]]   	;# RXD0[1]
set_property PACKAGE_PIN V17 [get_ports GEM0_RXD0[2]]   	;# RXD0[2]
set_property PACKAGE_PIN Y17 [get_ports GEM0_RXD0[3]]   	;# RXD0[3]

## MDIO/MDC
set_property PACKAGE_PIN W15 [get_ports GEM0_MDC0]    ;# MDC0
set_property PACKAGE_PIN Y14 [get_ports GEM0_MDIO0]   ;# MDIO0

## IOSTANDARD
set_property IOSTANDARD LVCMOS33 [get_ports { \
    GEM0_TXEN0 GEM0_TXD0[0] GEM0_TXD0[1] GEM0_TXD0[2] GEM0_TXD0[3] GEM0_TXCLK0 \
    GEM0_RXCLK0 GEM0_RXDV0 GEM0_RXD0[0] GEM0_RXD0[1] GEM0_RXD0[2] GEM0_RXD0[3] \
    GEM0_MDC0 GEM0_MDIO0 \
}]

## EBAZ4205: User LEDs (PL)

set_property PACKAGE_PIN W13 [get_ports LED_GREEN]   ;# зелёный LED
set_property PACKAGE_PIN W14 [get_ports LED_RED]     ;# красный LED

set_property IOSTANDARD LVCMOS33 [get_ports { LED_GREEN LED_RED }]


