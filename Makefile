# OpenFang OS — Main Build System
# Requires: Docker 24+, qemu-system-x86_64

SHELL := /bin/bash
.ONESHELL:

# Version
VERSION     ?= 0.1.0
ARCH        ?= x86_64
ALPINE_VER  ?= 3.19

# Paths
BUILD_DIR   := build/output
WORK_DIR    := build/work
ISO_NAME    := openfang-os-$(VERSION)-$(ARCH).iso
IMG_NAME    := openfang-os-$(VERSION)-$(ARCH).img

# Docker
BUILDER_IMG := openfang-builder:$(VERSION)
BUILD_ARGS  := --build-arg ALPINE_VER=$(ALPINE_VER) \
               --build-arg VERSION=$(VERSION) \
               --build-arg ARCH=$(ARCH)

.PHONY: all iso image run clean builder rootfs aish openfang-ctl \
        dev-shell test lint check-deps help

## Default target
all: iso

## Show help
help:
	@echo "OpenFang OS Build System"
	@echo ""
	@echo "Targets:"
	@echo "  make iso          Build a bootable ISO image"
	@echo "  make image        Build a flashable disk image (for USB/SD)"
	@echo "  make run          Run the ISO in QEMU"
	@echo "  make builder      Build the Docker build environment"
	@echo "  make aish         Build the AI Shell binary"
	@echo "  make openfang-ctl Build the openfang-ctl binary"
	@echo "  make dev-shell    Drop into the build container shell"
	@echo "  make clean        Remove all build artifacts"
	@echo "  make lint         Run linters"
	@echo "  make check-deps   Verify build dependencies"
	@echo ""
	@echo "Variables:"
	@echo "  VERSION=$(VERSION)"
	@echo "  ARCH=$(ARCH)"
	@echo "  ALPINE_VER=$(ALPINE_VER)"

## Check build dependencies
check-deps:
	@echo "[*] Checking dependencies..."
	@command -v docker >/dev/null 2>&1 || { echo "ERROR: docker not found"; exit 1; }
	@command -v qemu-system-x86_64 >/dev/null 2>&1 || \
		echo "WARN: qemu-system-x86_64 not found (needed for 'make run')"
	@echo "[+] Dependencies OK"

## Build the Docker build environment
builder: check-deps
	@echo "[*] Building Docker build environment..."
	docker build $(BUILD_ARGS) -t $(BUILDER_IMG) -f build/Dockerfile build/
	@echo "[+] Builder image ready: $(BUILDER_IMG)"

## Build the AI Shell (aish)
aish:
	@echo "[*] Building aish (AI Shell)..."
	cd aish && cargo build --release
	mkdir -p $(BUILD_DIR)/bin
	cp aish/target/release/aish $(BUILD_DIR)/bin/
	@echo "[+] aish built: $(BUILD_DIR)/bin/aish"

## Build the control tool (openfang-ctl)
openfang-ctl:
	@echo "[*] Building openfang-ctl..."
	cd openfang-ctl && cargo build --release
	mkdir -p $(BUILD_DIR)/bin
	cp openfang-ctl/target/release/openfang-ctl $(BUILD_DIR)/bin/
	@echo "[+] openfang-ctl built: $(BUILD_DIR)/bin/openfang-ctl"

## Assemble the root filesystem overlay
rootfs: aish openfang-ctl
	@echo "[*] Assembling rootfs overlay..."
	bash build/rootfs.sh $(BUILD_DIR) $(WORK_DIR)
	@echo "[+] Rootfs assembled"

## Build the bootable ISO
iso: builder rootfs
	@echo "[*] Building ISO: $(ISO_NAME)..."
	mkdir -p $(BUILD_DIR)
	docker run --rm --privileged \
		-v "$(PWD)/build/output:/output" \
		-v "$(PWD)/rootfs:/rootfs:ro" \
		-v "$(PWD)/kernel:/kernel:ro" \
		-e ISO_NAME=$(ISO_NAME) \
		-e VERSION=$(VERSION) \
		-e ARCH=$(ARCH) \
		$(BUILDER_IMG) bash /scripts/iso.sh
	@echo "[+] ISO ready: $(BUILD_DIR)/$(ISO_NAME)"

## Build flashable disk image
image: iso
	@echo "[*] Building disk image: $(IMG_NAME)..."
	docker run --rm --privileged \
		-v "$(PWD)/build/output:/output" \
		-e ISO_NAME=$(ISO_NAME) \
		-e IMG_NAME=$(IMG_NAME) \
		$(BUILDER_IMG) bash /scripts/image.sh
	@echo "[+] Image ready: $(BUILD_DIR)/$(IMG_NAME)"

## Run in QEMU
run:
	@if [ ! -f "$(BUILD_DIR)/$(ISO_NAME)" ]; then \
		echo "ERROR: ISO not found. Run 'make iso' first."; exit 1; fi
	@echo "[*] Booting $(ISO_NAME) in QEMU..."
	qemu-system-x86_64 \
		-m 2G \
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

## Drop into build container shell
dev-shell: builder
	docker run --rm -it \
		-v "$(PWD):/workspace" \
		-w /workspace \
		$(BUILDER_IMG) /bin/bash

## Run linters
lint:
	@echo "[*] Running linters..."
	@if [ -d aish ]; then cd aish && cargo clippy -- -D warnings; fi
	@if [ -d openfang-ctl ]; then cd openfang-ctl && cargo clippy -- -D warnings; fi
	@echo "[+] Lint OK"

## Clean build artifacts
clean:
	@echo "[*] Cleaning build artifacts..."
	rm -rf $(BUILD_DIR) $(WORK_DIR)
	@if [ -d aish ]; then cd aish && cargo clean; fi
	@if [ -d openfang-ctl ]; then cd openfang-ctl && cargo clean; fi
	@echo "[+] Clean done"

## Install to a disk (interactive)
install:
	@echo "[*] Running OpenFang OS installer..."
	bash installer/install.sh
