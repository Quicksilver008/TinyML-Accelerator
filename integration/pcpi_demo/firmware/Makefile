SHELL := bash
PYTHON ?= python
TOOLCHAIN_PREFIX ?= riscv64-unknown-elf-
CC := $(TOOLCHAIN_PREFIX)gcc
OBJCOPY := $(TOOLCHAIN_PREFIX)objcopy
OBJDUMP := $(TOOLCHAIN_PREFIX)objdump

PICORV32_MAKEHEX ?= ../../../picorv32/firmware/makehex.py
WORDS ?= 256

all: firmware.hex

firmware.elf: firmware.S sections.lds
	$(CC) -mabi=ilp32 -march=rv32i -ffreestanding -nostdlib -o $@ \
		-Wl,--build-id=none,-Bstatic,-T,sections.lds,-Map,firmware.map,--strip-debug \
		$<

firmware.bin: firmware.elf
	$(OBJCOPY) -O binary $< $@

firmware.hex: firmware.bin $(PICORV32_MAKEHEX)
	$(PYTHON) $(PICORV32_MAKEHEX) firmware.bin $(WORDS) > $@

firmware.dis: firmware.elf
	$(OBJDUMP) -d $< > $@

clean:
	rm -f firmware.elf firmware.bin firmware.hex firmware.map firmware.dis

.PHONY: all clean
