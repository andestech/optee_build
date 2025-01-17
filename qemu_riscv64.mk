################################################################################
# Following variables defines how the NS_USER (Non Secure User - Client
# Application), NS_KERNEL (Non Secure Kernel), S_KERNEL (Secure Kernel) and
# S_USER (Secure User - TA) are compiled
################################################################################
COMPILE_NS_USER ?= 64
override COMPILE_NS_KERNEL := 64
COMPILE_S_USER ?= 64
COMPILE_S_KERNEL ?= 64

################################################################################
# Override variables in common.mk
################################################################################
ARCH = riscv

BR2_ROOTFS_OVERLAY = $(ROOT)/build/br-ext/board/qemu_riscv64/overlay

BREXT_BOARD_PATH=$(ROOT)/build/br-ext/board/qemu_riscv64
BREXT_GENIMAGE_CONFIG=$(BREXT_BOARD_PATH)/genimage.cfg

BR2_PACKAGE_HOST_GENIMAGE=y
BR2_ROOTFS_POST_IMAGE_SCRIPT="support/scripts/genimage.sh"
BR2_ROOTFS_POST_SCRIPT_ARGS = "-c $(BREXT_GENIMAGE_CONFIG)"
BR2_TARGET_GENERIC_GETTY_PORT = ttyS0
BR2_TARGET_ROOTFS_EXT2 = y
BR2_TOOLCHAIN_EXTERNAL_HEADERS_5_10 = y

OPTEE_OS_PLATFORM = virt

# optee_test
WITH_TLS_TESTS			= n
WITH_CXX_TESTS			= n

########################################################################################
# If you change this, you MUST run `optee-os-clean` before rebuilding
########################################################################################
XEN_BOOT ?= n
include common.mk

DEBUG = 1

################################################################################
# Paths to git projects and various binaries
################################################################################
OPENSBI_PATH		?= $(ROOT)/opensbi
U-BOOT_PATH		?= $(ROOT)/u-boot
BINARIES_PATH		?= $(ROOT)/out/bin
QEMU_PATH		?= $(ROOT)/qemu
QEMU_BUILD		?= $(QEMU_PATH)/build
MODULE_OUTPUT		?= $(ROOT)/out/kernel_modules

KERNEL_IMAGE		?= $(LINUX_PATH)/arch/riscv/boot/Image

################################################################################
# Targets
################################################################################
TARGET_DEPS := opensbi linux buildroot optee-os qemu u-boot
TARGET_CLEAN := opensbi-clean linux-clean buildroot-clean optee-os-clean \
	qemu-clean u-boot-clean

TARGET_DEPS		+= $(KERNEL_IMAGE)

all: $(TARGET_DEPS)

clean: $(TARGET_CLEAN)

$(BINARIES_PATH):
	mkdir -p $@

include toolchain.mk

################################################################################
# OpenSBI
################################################################################
OPENSBI_EXPORTS ?= \
	CROSS_COMPILE="$(CCACHE)$(RISCV64_CROSS_COMPILE)"

OPENSBI_FLAGS ?= PLATFORM=generic DEBUG=$(DEBUG) -j $(nproc)

OPENSBI_OUT = $(OPENSBI_PATH)/install/usr/share/opensbi/lp64/generic/firmware/

opensbi:
	$(OPENSBI_EXPORTS) $(MAKE) -C $(OPENSBI_PATH) $(OPENSBI_FLAGS) install
	mkdir -p $(BINARIES_PATH)
	ln -sf $(OPENSBI_OUT)/fw_jump.bin $(BINARIES_PATH)
	ln -sf $(OPENSBI_OUT)/fw_dynamic.bin $(BINARIES_PATH)

opensbi-clean:
	$(OPENSBI_EXPORTS) $(MAKE) -C $(OPENSBI_PATH) $(OPENSBI_FLAGS) clean

################################################################################
# Das U-Boot
################################################################################
U-BOOT_EXPORTS ?= \
	CROSS_COMPILE="$(CCACHE)$(RISCV64_CROSS_COMPILE)"
U-BOOT_DEFCONFIG_COMMON_FILES := \
		$(U-BOOT_PATH)/configs/qemu-riscv64_spl_defconfig
U-BOOT_ITB_LOAD_ADDR ?= 0x80200000
U-BOOT_FLAGS ?= -j $(nproc)

u-boot: u-boot-defconfig optee-os opensbi
	mkdir -p $(BINARIES_PATH)
	ln -sf $(BINARIES_PATH)/fw_dynamic.bin $(U-BOOT_PATH)
	ln -sf $(BINARIES_PATH)/tee.bin $(U-BOOT_PATH)
	$(U-BOOT_EXPORTS) $(MAKE) -C $(U-BOOT_PATH) all -j $(nproc)
	$(U-BOOT_EXPORTS) $(MAKE) -C $(U-BOOT_PATH) tools
	ln -sf $(U-BOOT_PATH)/spl/u-boot-spl $(BINARIES_PATH)
	ln -sf $(U-BOOT_PATH)/u-boot.itb $(BINARIES_PATH)

u-boot-clean: u-boot-defconfig-clean
	$(U-BOOT_EXPORTS) $(MAKE) -C $(U-BOOT_PATH) clean

u-boot-defconfig: $(U-BOOT_DEFCONFIG_COMMON_FILES)
	cd $(U-BOOT_PATH) && \
		ARCH=riscv \
		scripts/kconfig/merge_config.sh $(U-BOOT_DEFCONFIG_COMMON_FILES)

u-boot-defconfig-clean:
	rm -f $(U-BOOT_PATH)/.config

.PHONY: u-boot u-boot-clean u-boot-defconfig u-boot-defconfig-clean

################################################################################
# QEMU
################################################################################
$(QEMU_BUILD)/config-host.mak:
	cd $(QEMU_PATH); ./configure --target-list="riscv64-softmmu" --enable-slirp\
			$(QEMU_CONFIGURE_PARAMS_COMMON)

qemu: $(QEMU_BUILD)/config-host.mak
	$(MAKE) -C $(QEMU_PATH) -j $(nproc)

qemu-clean:
	$(MAKE) -C $(QEMU_PATH) clean

################################################################################
# Linux kernel
################################################################################
LINUX_DEFCONFIG_COMMON_ARCH := riscv
LINUX_DEFCONFIG_COMMON_FILES := \
		$(LINUX_PATH)/arch/riscv/configs/defconfig \
		$(CURDIR)/kconfigs/qemu_riscv64.conf

linux-defconfig: $(LINUX_PATH)/.config

LINUX_COMMON_FLAGS += ARCH=riscv -j $(nproc)

linux: linux-common buildroot
	mkdir -p $(BINARIES_PATH)
	ln -sf $(LINUX_PATH)/arch/riscv/boot/Image $(BINARIES_PATH)
	ln -sf $(LINUX_PATH)/arch/riscv/boot/Image.gz $(BINARIES_PATH)
	cp $(LINUX_PATH)/arch/riscv/boot/Image $(ROOT)/out-br/target/boot

linux-modules: linux
	$(MAKE) -C $(LINUX_PATH) $(LINUX_COMMON_FLAGS) modules
	$(MAKE) -C $(LINUX_PATH) $(LINUX_COMMON_FLAGS) INSTALL_MOD_STRIP=1 INSTALL_MOD_PATH=$(MODULE_OUTPUT) modules_install

linux-defconfig-clean: linux-defconfig-clean-common

LINUX_CLEAN_COMMON_FLAGS += ARCH=riscv

linux-clean: linux-clean-common

LINUX_CLEANER_COMMON_FLAGS += ARCH=riscv

linux-cleaner: linux-cleaner-common

################################################################################
# OP-TEE
################################################################################
OPTEE_OS_COMMON_FLAGS += ARCH=riscv
OPTEE_OS_COMMON_FLAGS += DEBUG=$(DEBUG)
OPTEE_OS_COMMON_FLAGS += CFG_TEE_CORE_NB_CORE=$(QEMU_SMP)
OPTEE_OS_COMMON_FLAGS += CFG_NUM_THREADS=$(QEMU_SMP)
OPTEE_OS_COMMON_FLAGS += CFG_TEE_CORE_LOG_LEVEL=4
OPTEE_OS_COMMON_FLAGS += CFG_TEE_TA_LOG_LEVEL=4
OPTEE_OS_COMMON_FLAGS += CFG_UNWIND=y

OPTEE_OS_LOAD_ADDRESS ?= 0xf1000000

optee-os: optee-os-common
	ln -sf $(OPTEE_OS_BIN) $(BINARIES_PATH)

optee-os-clean: optee-os-clean-common

################################################################################
# Run targets
################################################################################
.PHONY: run
# This target enforces updating root fs etc
run: all
	$(MAKE) run-only

QEMU_SMP 	?= 2
QEMU_MEM 	?= 4096
QEMU_MACHINE	?= virt
QEMU_DTB	?= qemu_rv64_virt_domain.dtb

.PHONY: run-only
run-only:
	ln -sf $(ROOT)/out-br/images/sdcard.img $(BINARIES_PATH)/
	ln -sf $(ROOT)/qemu_rv64_virt_domain.dtb $(BINARIES_PATH)/
	$(call check-terminal)
	$(call run-help)
	cd $(BINARIES_PATH) && $(QEMU_BUILD)/qemu-system-riscv64 \
			-nographic \
			-M $(QEMU_MACHINE) \
			-dtb $(QEMU_DTB) \
			-m $(QEMU_MEM) \
			-smp $(QEMU_SMP) \
			-semihosting-config enable=on,target=native \
			-serial tcp:127.0.0.1:64320,server \
			-bios u-boot-spl \
			-device loader,file=u-boot.itb,addr=$(U-BOOT_ITB_LOAD_ADDR) \
			-device virtio-blk-device,drive=hd0 \
			-drive file=sdcard.img,id=hd0 \
			-device virtio-net-pci,netdev=usernet \
			-netdev user,id=usernet,hostfwd=tcp::2200-:22
