# OpenFang OS — Build System (Ubuntu 24.04 LTS)
# Requires: Docker 24+, qemu-system-x86_64

SHELL := /bin/bash
.ONESHELL:

# Version
VERSION      ?= 0.1.0
ARCH         ?= amd64
UBUNTU_VER   ?= noble   # Ubuntu 24.04 LTS

# Paths
BUILD_DIR    := build/output
WORK_DIR     := build/work
ISO_NAME     := openfang-os-$(VERSION)-$(ARCH).iso
IMG_NAME     := openfang-os-$(VERSION)-$(ARCH).img

# Docker
BUILDER_IMG  := openfang-builder:$(VERSION)
BUILD_ARGS   := --build-arg UBUNTU_VER=$(UBUNTU_VER) \
                --build-arg VERSION=$(VERSION) \
                --build-arg ARCH=$(ARCH)

.PHONY: all iso image run clean builder aish openfang-ctl \
        dev-shell lint check-deps help

## Default target
all: iso

## Show help
help:
	@echo "OpenFang OS Build System (Ubuntu 24.04 LTS)"
	@echo ""
	@echo "Targets:"
	@echo "  make iso          Build a bootable live ISO (~4GB)"
	@echo "  make image        Build a flashable encrypted disk image"
	@echo "  make run          Run the ISO in QEMU (2GB RAM)"
	@echo "  make run-gui      Run in QEMU with display (KVM accelerated)"
	@echo "  make builder      Build the Docker build environment"
	@echo "  make aish         Build the AI Shell binary"
	@echo "  make openfang-ctl Build the openfang-ctl binary"
	@echo "  make dev-shell    Drop into the build container shell"
	@echo "  make clean        Remove all build artifacts"
	@echo "  make lint         Run Rust linters"
	@echo ""
	@echo "Variables:"
	@echo "  VERSION=$(VERSION)"
	@echo "  ARCH=$(ARCH)"
	@echo "  UBUNTU_VER=$(UBUNTU_VER)"
	@echo "  BUILDER_IMG=$(BUILDER_IMG)"

## Check build dependencies
check-deps:
	@echo "[*] Checking dependencies..."
	@command -v docker >/dev/null 2>&1 || { echo "ERROR: docker not found"; exit 1; }
	@command -v qemu-system-x86_64 >/dev/null 2>&1 || \
		echo "WARN: qemu-system-x86_64 not found (needed for 'make run')"
	@echo "[+] Dependencies OK"

## Build Docker build environment
builder: check-deps
	@echo "[*] Building Docker build environment..."
	docker build $(BUILD_ARGS) -t $(BUILDER_IMG) -f build/Dockerfile build/
	@echo "[+] Builder ready: $(BUILDER_IMG)"

## Build the AI Shell
aish:
	@echo "[*] Building aish..."
	cd aish && cargo build --release
	mkdir -p $(BUILD_DIR)/bin
	cp aish/target/release/aish $(BUILD_DIR)/bin/
	@echo "[+] aish built"

## Build the control tool
openfang-ctl:
	@echo "[*] Building openfang-ctl..."
	cd openfang-ctl && cargo build --release
	mkdir -p $(BUILD_DIR)/bin
	cp openfang-ctl/target/release/openfang-ctl $(BUILD_DIR)/bin/
	@echo "[+] openfang-ctl built"

## Build ISO
iso: builder
	@echo "[*] Building ISO: $(ISO_NAME)..."
	mkdir -p $(BUILD_DIR)
	docker run --rm --privileged \
		-v "$(PWD)/$(BUILD_DIR):/output" \
		-v "$(PWD)/build/work:/build/work" \
		-v "$(PWD)/rootfs:/rootfs:ro" \
		-v "$(PWD)/$(BUILD_DIR)/bin:/output/bin:ro" \
		-e ISO_NAME=$(ISO_NAME) \
		-e VERSION=$(VERSION) \
		-e ARCH=$(ARCH) \
		-e UBUNTU_VER=$(UBUNTU_VER) \
		$(BUILDER_IMG) bash /scripts/iso.sh
	@echo "[+] ISO ready: $(BUILD_DIR)/$(ISO_NAME)"

## Build flashable disk image
image: iso
	@echo "[*] Building disk image: $(IMG_NAME)..."
	docker run --rm --privileged \
		-v "$(PWD)/$(BUILD_DIR):/output" \
		-e ISO_NAME=$(ISO_NAME) \
		-e IMG_NAME=$(IMG_NAME) \
		$(BUILDER_IMG) bash /scripts/image.sh
	@echo "[+] Image ready: $(BUILD_DIR)/$(IMG_NAME)"

## Run in QEMU (console mode)
run:
	@if [ ! -f "$(BUILD_DIR)/$(ISO_NAME)" ]; then \
		echo "ERROR: Run 'make iso' first"; exit 1; fi
	qemu-system-x86_64 \
		-m 4G \
		-smp 2 \
		-cpu host \
		-enable-kvm \
		-cdrom $(BUILD_DIR)/$(ISO_NAME) \
		-boot d \
		-nographic \
		-serial mon:stdio \
		-netdev user,id=net0,hostfwd=tcp::8080-:8080,hostfwd=tcp::2222-:22 \
		-device virtio-net-pci,netdev=net0 \
		-device virtio-rng-pci \
		-device virtio-balloon-pci

## Run in QEMU with GUI (desktop)
run-gui:
	@if [ ! -f "$(BUILD_DIR)/$(ISO_NAME)" ]; then \
		echo "ERROR: Run 'make iso' first"; exit 1; fi
	qemu-system-x86_64 \
		-m 4G \
		-smp 4 \
		-cpu host \
		-enable-kvm \
		-cdrom $(BUILD_DIR)/$(ISO_NAME) \
		-boot d \
		-vga virtio \
		-display sdl,gl=on \
		-device virtio-tablet \
		-device virtio-keyboard \
		-netdev user,id=net0,hostfwd=tcp::8080-:8080,hostfwd=tcp::2222-:22 \
		-device virtio-net-pci,netdev=net0 \
		-device virtio-rng-pci \
		-audiodev pa,id=audio0 \
		-device intel-hda \
		-device hda-duplex,audiodev=audio0

## Drop into build container shell
dev-shell: builder
	docker run --rm -it --privileged \
		-v "$(PWD):/workspace" \
		-v "$(PWD)/$(BUILD_DIR):/output" \
		-v "$(PWD)/build/work:/build/work" \
		-w /workspace \
		$(BUILDER_IMG) /bin/bash

## Lint Rust code
lint:
	@if [ -d aish ]; then cd aish && cargo clippy -- -D warnings; fi
	@if [ -d openfang-ctl ]; then cd openfang-ctl && cargo clippy -- -D warnings; fi

## Clean build artifacts
clean:
	rm -rf $(BUILD_DIR) $(WORK_DIR)
	@if [ -d aish ]; then cd aish && cargo clean; fi
	@if [ -d openfang-ctl ]; then cd openfang-ctl && cargo clean; fi
	@echo "[+] Cleaned"

## Install to disk (run on live system)
install:
	bash installer/install.sh
