/* lscript.ld -- Zynq-7010 / EBAZ4205 SDR firmware linker script.
 *
 * DDR is 256 MB at 0x0000_0000.
 *   0x0000_0000 .. 0x0007_FFFF :  Reserved for FSBL / vector table
 *   0x0008_0000 .. 0x07FF_FFFF :  Code, RO-data, RW-data, BSS, heap, stack
 *   0x0800_0000 .. 0x0FFF_FFFF :  Non-cached DMA region (see platform_init.c)
 *
 * Heap=4 MB, stack=64 KB main / 16 KB IRQ.  Adjust if FreeRTOS heap_4
 * runs out (configTOTAL_HEAP_SIZE in FreeRTOSConfig.h is independent).
 */

_STACK_SIZE     = DEFINED(_STACK_SIZE) ? _STACK_SIZE : 0x10000;
_IRQ_STACK_SIZE = DEFINED(_IRQ_STACK_SIZE) ? _IRQ_STACK_SIZE : 0x4000;
_HEAP_SIZE      = DEFINED(_HEAP_SIZE) ? _HEAP_SIZE : 0x400000;

MEMORY
{
    ps7_ram_0_S_AXI_BASEADDR : ORIGIN = 0x00000000, LENGTH = 0x00030000
    ps7_ddr_0_S_AXI_BASEADDR : ORIGIN = 0x00100000, LENGTH = 0x07F00000
}

ENTRY(_vector_table)

SECTIONS
{
    .text : {
        KEEP (*(.vectors))
        *(.boot)
        *(.text)
        *(.text.*)
        *(.gnu.linkonce.t.*)
        *(.plt)
        *(.gnu_warning)
        *(.gcc_except_table)
        *(.glue_7)
        *(.glue_7t)
        *(.vfp11_veneer)
        *(.ARM.extab)
        *(.gnu.linkonce.armextab.*)
    } > ps7_ddr_0_S_AXI_BASEADDR

    .init : { KEEP (*(.init))  } > ps7_ddr_0_S_AXI_BASEADDR
    .fini : { KEEP (*(.fini))  } > ps7_ddr_0_S_AXI_BASEADDR

    .rodata : {
        __rodata_start = .;
        *(.rodata)
        *(.rodata.*)
        *(.gnu.linkonce.r.*)
        __rodata_end = .;
    } > ps7_ddr_0_S_AXI_BASEADDR

    .data : {
        __data_start = .;
        *(.data)
        *(.data.*)
        *(.gnu.linkonce.d.*)
        *(.jcr)
        *(.got)
        *(.got.plt)
        __data_end = .;
    } > ps7_ddr_0_S_AXI_BASEADDR

    .ARM.exidx : {
        __exidx_start = .;
        *(.ARM.exidx*)
        __exidx_end = .;
    } > ps7_ddr_0_S_AXI_BASEADDR

    .ctors : {
        __CTOR_LIST__ = .;
        ___CTORS_LIST___ = .;
        KEEP (*crtbegin.o(.ctors))
        KEEP (*(EXCLUDE_FILE(*crtend.o) .ctors))
        KEEP (*(SORT(.ctors.*)))
        KEEP (*(.ctors))
        __CTOR_END__ = .;
        ___CTORS_END___ = .;
    } > ps7_ddr_0_S_AXI_BASEADDR

    .dtors : {
        __DTOR_LIST__ = .;
        ___DTORS_LIST___ = .;
        KEEP (*crtbegin.o(.dtors))
        KEEP (*(EXCLUDE_FILE(*crtend.o) .dtors))
        KEEP (*(SORT(.dtors.*)))
        KEEP (*(.dtors))
        __DTOR_END__ = .;
        ___DTORS_END___ = .;
    } > ps7_ddr_0_S_AXI_BASEADDR

    .bss (NOLOAD) : {
        __bss_start__ = .;
        *(.bss)
        *(.bss.*)
        *(.gnu.linkonce.b.*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end__ = .;
    } > ps7_ddr_0_S_AXI_BASEADDR

    _SDA_BASE_ = . + 0x8000;
    _SDA2_BASE_ = . + 0x8000;

    .heap (NOLOAD) : {
        . = ALIGN(16);
        _heap = .;
        HeapBase = .;
        _heap_start = .;
        . += _HEAP_SIZE;
        _heap_end = .;
        HeapLimit = .;
    } > ps7_ddr_0_S_AXI_BASEADDR

    .stack (NOLOAD) : {
        . = ALIGN(16);
        _stack_end = .;
        . += _STACK_SIZE;
        . = ALIGN(16);
        _stack = .;
        __stack = _stack;
        . = ALIGN(16);
        _irq_stack_end = .;
        . += _IRQ_STACK_SIZE;
        . = ALIGN(16);
        __irq_stack = .;
        _supervisor_stack_end = .;
        . += _IRQ_STACK_SIZE;
        . = ALIGN(16);
        __supervisor_stack = .;
        _abort_stack_end = .;
        . += _IRQ_STACK_SIZE;
        . = ALIGN(16);
        __abort_stack = .;
        _undef_stack_end = .;
        . += _IRQ_STACK_SIZE;
        . = ALIGN(16);
        __undef_stack = .;
    } > ps7_ddr_0_S_AXI_BASEADDR

    _end = .;
}
