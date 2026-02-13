SHELL := /bin/bash

PROJECT := UsegeMacWidget.xcodeproj
XCODEGEN_SPEC := project.yml
DERIVED_DATA := .derived
HOST_SCHEME := UsegeNativeHost
HOST_BINARY := $(CURDIR)/$(DERIVED_DATA)/Build/Products/Debug/usege-native-host

.PHONY: help ensure-project build-native-host install-native-host install run-app test test-swift test-extension

help:
	@echo "Available targets:"
	@echo "  make install EXTENSION_ID=<chrome_extension_id>  # Build native host and install manifest"
	@echo "  make build-native-host                            # Build only native host"
	@echo "  make run-app                                      # Launch Usege.app"
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

install-native-host: build-native-host
	@if [[ -z "$(EXTENSION_ID)" ]]; then \
		echo "ERROR: EXTENSION_ID is required."; \
		echo "Usage: make install EXTENSION_ID=<chrome_extension_id>"; \
		exit 1; \
	fi
	./scripts/install_native_host.sh "$(HOST_BINARY)" "$(EXTENSION_ID)"

install: install-native-host
	@echo "Installed native messaging manifest for extension: $(EXTENSION_ID)"
	@echo "Next:"
	@echo "  1) Open chrome://extensions and load $(CURDIR)/chrome-extension"
	@echo "  2) Open $(CURDIR)/.derived/Build/Products/Debug/Usege.app"

run-app: ensure-project
	open "$(CURDIR)/$(DERIVED_DATA)/Build/Products/Debug/Usege.app"

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
