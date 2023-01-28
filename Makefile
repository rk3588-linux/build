COMPILER_PATH ?= $(PWD)/../compiler
UBOOT_PATH ?= $(PWD)/../u-boot
LINUX_PATH ?= $(PWD)/../linux
RKDEVELOPTOOL_PATH ?= $(PWD)/../rkdeveloptool

NPROC = $(shell nproc)

export CROSS_COMPILER ?= $(PWD)/../compiler/aarch64-linux-gnu/bin/aarch64-linux-gnu-

$(shell mkdir -p image)

all: fetch build image



.PHONY: fetch
fetch: $(UBOOT_PATH) $(LINUX_PATH) $(COMPILER_PATH)

$(COMPILER_PATH):
	git clone git@github.com:AlexLanzano/compiler.git $@

$(UBOOT_PATH):
	git clone git@github.com:rk3588-linux/u-boot.git $@

$(LINUX_PATH):
	git clone git@github.com:rk3588-linux/linux.git $@

$(RKDEVELOPTOOL_PATH):
	git clone git@github.com:radxa/rkdeveloptool.git $@


.PHONY: build build-u-boot build-linux build-compiler build-rkdeveloptool
build: build-u-boot build-linux build-rkdeveloptool
build-u-boot: $(UBOOT_PATH)/.config
	cd $(UBOOT_PATH); \
	$(MAKE) ARCH=arm CROSS_COMPILE=$(CROSS_COMPILER) -j$(NPROC) BL31=../build/prebuilt/rk3588_bl31_v1.27.elf spl/u-boot-spl.bin u-boot.dtb u-boot.itb

$(UBOOT_PATH)/.config: $(UBOOT_PATH)/configs/rk3588_defconfig
	cd $(UBOOT_PATH); \
	$(MAKE) rk3588_defconfig



build-linux: $(LINUX_PATH)/.config
	cd $(LINUX_PATH); \
	$(MAKE) ARCH=arm64 CROSS_COMPILE=$(CROSS_COMPILER) -j$(NPROC)
$(LINUX_PATH)/.config: config/rk3588-linux.config
	cp config/rk3588-linux.config $(LINUX_PATH)/.config



build-compiler: config/aarch64-linux-gnu-config.mk
	cd $(COMPILER_PATH); \
	$(MAKE) all-linux CONFIG=../build/$^



build-rkdeveloptool:
	cd $(RKDEVELOPTOOL_PATH); \
	autoreconf -i; \
	./configure; \
	$(MAKE)

.PHONY: image
image: image/boot.img image/linux.img

image/u-boot.scr: config/u-boot-script.txt
	$(UBOOT_PATH)/tools/mkimage -A arm -O arm-trusted-firmware -T script -C none -a 0 -e 0 -n "My script" -d $^ $@

image/loader1.img: $(UBOOT_PATH)/spl/u-boot-spl.bin prebuilt/rk3588_ddr_lp4_2112MHz_lp5_2736MHz_v1.08.bin
	$(UBOOT_PATH)/tools/mkimage -O arm-trusted-firmware -n rk3588 -T rksd -d prebuilt/rk3588_ddr_lp4_2112MHz_lp5_2736MHz_v1.08.bin:$(UBOOT_PATH)/spl/u-boot-spl.bin $@

image/boot.img: image/loader1.img $(UBOOT_PATH)/u-boot.itb
	dd if=/dev/zero of=$@ bs=1M count=0 seek=16
	parted -s $@ mklabel gpt
	parted -s $@ unit s mkpart idbloader 64 7167
	parted -s $@ unit s mkpart vnvm 7168 7679
	parted -s $@ unit s mkpart reserved_space 7680 8063
	parted -s $@ unit s mkpart reserved1 8064 8127
	parted -s $@ unit s mkpart uboot_env 8128 8191
	parted -s $@ unit s mkpart reserved2 8192 16383
	parted -s $@ unit s mkpart uboot 16384 32734
	dd if=image/loader1.img of=$@ seek=64 conv=notrunc
	dd if=$(UBOOT_PATH)/u-boot.itb of=$@ seek=16384 conv=notrunc

image/linux.img: image/u-boot.scr $(LINUX_PATH)/arch/arm64/boot/Image $(LINUX_PATH)/arch/arm64/boot/dts/rockchip/rk3588.dtb
	dd if=/dev/zero of=$@ bs=1M count=0 seek=10240
	parted -s $@ mklabel gpt
	parted -s $@ unit s mkpart boot fat32 2048 616447
	parted -s $@ set 1 boot on
	parted -s $@ unit s mkpart linux ext4 616448 20971486
	sudo kpartx -a $@
	sudo mkfs.fat -F 32 /dev/mapper/loop0p1
	sudo mkfs.ext4 /dev/mapper/loop0p2
	mkdir mnt
	sudo mount /dev/mapper/loop0p1 ./mnt
	sudo cp $^ mnt/
	sudo umount ./mnt
	rm -rf mnt
	sudo kpartx -d $@

.PHONY: flash-boot
flash-boot: image/boot.img
	sudo $(RKDEVELOPTOOL_PATH)/rkdeveloptool db prebuilt/rk3588_spl_loader_v1.08.111.bin
	sudo $(RKDEVELOPTOOL_PATH)/rkdeveloptool wl 0 $^

.PHONY: flash-boot-debug
flash-boot-debug: rock-5b-spi-image-g3caf61a44c2-debug.img
	sudo $(RKDEVELOPTOOL_PATH)/rkdeveloptool db prebuilt/rk3588_spl_loader_v1.08.111.bin
	sudo $(RKDEVELOPTOOL_PATH)/rkdeveloptool wl 0 $^

.PHONY: flash-linux
flash-linux: image/linux.img
	sudo dd if=$^ of=/dev/mmcblk0 bs=1M

.PHONY: clean
clean: clean-u-boot clean-linux clean-image

.PHONY: clean-u-boot
clean-u-boot:
	cd $(UBOOT_PATH); \
	$(MAKE) clean mrproper

.PHONY: clean-linux
clean-linux:
	cd $(LINUX_PATH); \
	$(MAKE) ARCH=arm64 clean mrproper

.PHONY: clean-image
clean-image:
	rm -rf image/
