SHELL := /bin/bash

PROJECT := UsegeMacWidget.xcodeproj
XCODEGEN_SPEC := project.yml
DERIVED_DATA := .derived
HOST_SCHEME := UsegeNativeHost
APP_SCHEME := UsegeApp
HOST_BINARY := $(CURDIR)/$(DERIVED_DATA)/Build/Products/Debug/usege-native-host
APP_BUNDLE := $(CURDIR)/$(DERIVED_DATA)/Build/Products/Debug/Usege.app
INSTALL_DIR ?= $(HOME)/Applications
INSTALLED_APP := $(INSTALL_DIR)/Usege.app

.PHONY: help ensure-project build-native-host build-app install-native-host install-app install run-app test test-swift test-extension

help:
	@echo "Available targets:"
	@echo "  make install EXTENSION_ID=<chrome_extension_id>  # Build host + app, install manifest + app"
	@echo "  make build-native-host                            # Build only native host"
	@echo "  make build-app                                    # Build only Usege.app"
	@echo "  make install-app [INSTALL_DIR=~/Applications]    # Copy Usege.app into INSTALL_DIR"
	@echo "  make run-app                                      # Launch installed Usege.app if present, else derived app"
	@echo "  make test                                         # Run Swift + extension tests"

ensure-project:
	@if [[ -d "$(PROJECT)" ]]; then \
		echo "Using existing $(PROJECT)"; \
	elif command -v xcodegen >/dev/null 2>&1; then \
		echo "Generating $(PROJECT) with xcodegen"; \
		xcodegen generate; \
	else \
		echo "ERROR: $(PROJECT) not found and xcodegen is not installed."; \
		echo "Install xcodegen or generate the Xcode project first."; \
		exit 1; \
	fi

build-native-host: ensure-project
	xcodebuild -project "$(PROJECT)" \
		-scheme "$(HOST_SCHEME)" \
		-configuration Debug \
		-derivedDataPath "$(DERIVED_DATA)" \
		build

build-app: ensure-project
	xcodebuild -project "$(PROJECT)" \
		-scheme "$(APP_SCHEME)" \
		-configuration Debug \
		-derivedDataPath "$(DERIVED_DATA)" \
		build

install-native-host: build-native-host
	@if [[ -z "$(EXTENSION_ID)" ]]; then \
		echo "ERROR: EXTENSION_ID is required."; \
		echo "Usage: make install EXTENSION_ID=<chrome_extension_id>"; \
		exit 1; \
	fi
	./scripts/install_native_host.sh "$(HOST_BINARY)" "$(EXTENSION_ID)"

install-app: build-app
	@mkdir -p "$(INSTALL_DIR)"
	@ditto "$(APP_BUNDLE)" "$(INSTALLED_APP)"
	@echo "Installed app: $(INSTALLED_APP)"

install: install-native-host install-app
	@echo "Installed native messaging manifest for extension: $(EXTENSION_ID)"
	@echo "Next:"
	@echo "  1) Open chrome://extensions and load $(CURDIR)/chrome-extension"
	@echo "  2) Launch $(INSTALLED_APP)"

run-app: ensure-project
	@if [[ -d "$(INSTALLED_APP)" ]]; then \
		open "$(INSTALLED_APP)"; \
	else \
		open "$(APP_BUNDLE)"; \
	fi

test: test-swift test-extension

test-swift: ensure-project
	xcodebuild -project "$(PROJECT)" \
		-scheme UsegeAppTests \
		-configuration Debug \
		-destination 'platform=macOS' \
		-derivedDataPath "$(DERIVED_DATA)" \
		test

test-extension:
	npm --prefix chrome-extension test
