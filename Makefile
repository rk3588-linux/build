COMPILER_PATH ?= $(PWD)/../compiler
UBOOT_PATH ?= $(PWD)/../u-boot
LINUX_PATH ?= $(PWD)/../linux

NPROC = $(shell nproc)

export ARCH = arm
export CROSS_COMPILER ?= $(PWD)/../compiler/aarch64-linux-gnu/bin/aarch64-linux-gnu-

all: fetch build image



.PHONY: fetch
fetch: $(UBOOT_PATH) $(LINUX_PATH) $(COMPILER_PATH)

$(COMPILER_PATH):
	git clone git@github.com:AlexLanzano/compiler.git $@

$(UBOOT_PATH):
	git clone git@github.com:rk3588-linux/u-boot.git $@

$(LINUX_PATH):
	git clone git@github.com:rk3588-linux/linux.git $@



.PHONY: build build-u-boot build-linux build-compiler
build: build-u-boot build-linux
build-u-boot: $(UBOOT_PATH)/.config
	cd $(UBOOT_PATH); \
	$(MAKE) ARCH=arm CROSS_COMPILE=$(CROSS_COMPILER) -j$(NPROC) BL31=../build/prebuilt/rk3588_bl31_v1.27.elf spl/u-boot-spl.bin u-boot.dtb u-boot.itb

$(UBOOT_PATH)/.config: $(UBOOT_PATH)/configs/rk3588_defconfig
	cd $(UBOOT_PATH); \
	$(MAKE) rk3588_defconfig

build-linux: $(LINUX_PATH)/.config
	cd $(LINUX_PATH); \
	$(MAKE) -j$(NPROC)

$(LINUX_PATH)/.config: config/rk3588-linux.config
	cp config/rk3588-linux.config $(LINUX_PATH)

build-compiler: config/aarch64-linux-gnu-config.mk
	cd $(COMPILER_PATH); \
	$(MAKE) all-linux CONFIG=../build/$^


.PHONY: image
image: boot.img linux.img

loader1.img: $(UBOOT_PATH)/spl/u-boot-spl.bin
	mkimage -n rk3588 -T rksd -d prebuilt/rk3588_ddr_lp4_2112MHz_lp5_2736MHz_v1.08.bin:$(UBOOT_PATH)/spl/u-boot-spl.bin $@

boot.img: loader1.img $(UBOOT_PATH)/u-boot.itb
	dd if=/dev/zero of=$@ bs=1M count=0 seek=16
	parted -s $@ mklabel gpt
	parted -s $@ unit s mkpart idbloader 64 7167
	parted -s $@ unit s mkpart vnvm 7168 7679
	parted -s $@ unit s mkpart reserved_space 7680 8063
	parted -s $@ unit s mkpart reserved1 8064 8127
	parted -s $@ unit s mkpart uboot_env 8128 8191
	parted -s $@ unit s mkpart reserved2 8192 16383
	parted -s $@ unit s mkpart uboot 16384 32734
	dd if=loader1.img of=$@ seek=64 conv=notrunc
	dd if=$(UBOOT_PATH)/u-boot.itb of=$@ seek=16384 conv=notrunc

linux.img:
	echo "TODO"
