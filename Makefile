# Gibson - build, install and preview the screen saver bundle.

BUNDLE      := Gibson
PRODUCT     := $(BUNDLE).saver
VERSION     := 1.0.2
BUILD       := build
TARGET_OS   := 14.0
ARCHS       := arm64 x86_64
SOURCES     := $(shell find Sources/Gibson -name '*.swift')
DEMO_SOURCE := Sources/Demo/main.swift
SHOT_SOURCE := Sources/Snapshot/main.swift
COVER_SOURCE := Sources/Cover/main.swift
BANNER_SOURCE := Sources/Support/GIFWriter.swift Sources/Banner/main.swift
MOTION_SOURCE := Sources/Support/GIFWriter.swift Sources/Motion/main.swift
SOCIAL_SOURCE := Sources/Social/main.swift
INSTALL_DIR := $(HOME)/Library/Screen Savers
SIGN_ID     ?= -
ZIP         := $(BUILD)/$(BUNDLE).saver.zip

# Distribution signing. DIST_ID is a Developer ID Application identity, and
# NOTARY_ARGS points notarytool at credentials: a keychain profile locally,
# --key, --key-id and --issuer in CI.
DIST_ID     ?= $(SIGN_ID)
NOTARY_ARGS ?= --keychain-profile gibson

# Tile shown by System Settings in the screen saver picker.
THUMBNAILS  := Resources/thumbnail.png Resources/thumbnail@2x.png

SWIFTC      := xcrun swiftc
COMMON      := -swift-version 5 -module-name $(BUNDLE) \
               -framework ScreenSaver -framework AppKit -framework QuartzCore
RELEASE     := -O -wmo

SLICES      := $(foreach arch,$(ARCHS),$(BUILD)/$(arch)/$(BUNDLE))

.PHONY: all clean install uninstall demo preview reinstall lint screenshot cover banner motion social dist

all: $(BUILD)/$(PRODUCT)

$(BUILD)/%/$(BUNDLE): $(SOURCES)
	@mkdir -p $(dir $@)
	$(SWIFTC) $(COMMON) $(RELEASE) -parse-as-library -emit-library \
		-target $*-apple-macos$(TARGET_OS) -o $@ $(SOURCES)

# Depends on the Makefile too: VERSION lives here, and a bump has to reach
# the bundle without a clean build.
$(BUILD)/$(PRODUCT): $(SLICES) Resources/Info.plist Makefile
	@rm -rf $@
	@mkdir -p $@/Contents/MacOS $@/Contents/Resources
	lipo -create $(SLICES) -output $@/Contents/MacOS/$(BUNDLE)
	sed -e 's/@VERSION@/$(VERSION)/g' -e 's/@TARGET_OS@/$(TARGET_OS)/g' \
		Resources/Info.plist > $@/Contents/Info.plist
	cp $(THUMBNAILS) $@/Contents/Resources/
	codesign --force --sign "$(SIGN_ID)" --timestamp=none $@
	@echo "built $@"

# Regenerate the picker tile. The PNGs are committed, so a plain build never
# needs this: run it only after changing the artwork.
cover: $(BUILD)/cover
	$(BUILD)/cover Resources/thumbnail.png

$(BUILD)/cover: $(SOURCES) $(COVER_SOURCE)
	@mkdir -p $(BUILD)
	$(SWIFTC) $(COMMON) -module-name GibsonCover -Onone \
		-target $(shell uname -m)-apple-macos$(TARGET_OS) -o $@ $(SOURCES) $(COVER_SOURCE)

# Animated README artwork. Both are committed, so a build never needs them.
banner: $(BUILD)/banner
	$(BUILD)/banner docs/images/banner.gif

$(BUILD)/banner: $(SOURCES) $(BANNER_SOURCE)
	@mkdir -p $(BUILD)
	$(SWIFTC) $(COMMON) -module-name GibsonBanner -Onone \
		-target $(shell uname -m)-apple-macos$(TARGET_OS) -o $@ $(SOURCES) $(BANNER_SOURCE)

motion: $(BUILD)/motion
	$(BUILD)/motion docs/images/dashboard.gif

$(BUILD)/motion: $(SOURCES) $(MOTION_SOURCE)
	@mkdir -p $(BUILD)
	$(SWIFTC) $(COMMON) -module-name GibsonMotion -Onone \
		-target $(shell uname -m)-apple-macos$(TARGET_OS) -o $@ $(SOURCES) $(MOTION_SOURCE)

# Release archive: Developer ID signature, notarised by Apple and stapled, so
# the bundle opens on a machine that has never seen it without any quarantine
# dance. Needs DIST_ID and notarytool credentials.
dist: $(BUILD)/$(PRODUCT)
	@if [ "$(DIST_ID)" = "-" ]; then \
		echo "set DIST_ID to a Developer ID Application identity"; exit 1; fi
	codesign --force --options runtime --timestamp --sign "$(DIST_ID)" $(BUILD)/$(PRODUCT)
	codesign --verify --strict --verbose=2 $(BUILD)/$(PRODUCT)
	@rm -f $(ZIP)
	ditto -c -k --keepParent $(BUILD)/$(PRODUCT) $(ZIP)
	xcrun notarytool submit $(ZIP) $(NOTARY_ARGS) --wait
	xcrun stapler staple $(BUILD)/$(PRODUCT)
	xcrun stapler validate $(BUILD)/$(PRODUCT)
	@rm -f $(ZIP)
	ditto -c -k --keepParent $(BUILD)/$(PRODUCT) $(ZIP)
	@echo "notarised $(ZIP)"

# Card GitHub shows when a link to the repository is pasted somewhere.
social: $(BUILD)/social
	$(BUILD)/social docs/images/social-preview.png

$(BUILD)/social: $(SOURCES) $(SOCIAL_SOURCE)
	@mkdir -p $(BUILD)
	$(SWIFTC) $(COMMON) -module-name GibsonSocial -Onone \
		-target $(shell uname -m)-apple-macos$(TARGET_OS) -o $@ $(SOURCES) $(SOCIAL_SOURCE)

install: $(BUILD)/$(PRODUCT)
	@mkdir -p "$(INSTALL_DIR)"
	@rm -rf "$(INSTALL_DIR)/$(PRODUCT)"
	cp -R $(BUILD)/$(PRODUCT) "$(INSTALL_DIR)/$(PRODUCT)"
	@echo "installed to $(INSTALL_DIR)/$(PRODUCT)"
	@echo "open System Settings > Screen Saver and pick $(BUNDLE)"

reinstall: uninstall install

uninstall:
	@rm -rf "$(INSTALL_DIR)/$(PRODUCT)"
	@echo "removed $(INSTALL_DIR)/$(PRODUCT)"

# Standalone window host. Fastest way to iterate without touching System Settings.
demo: $(BUILD)/demo
	$(BUILD)/demo

$(BUILD)/demo: $(SOURCES) $(DEMO_SOURCE)
	@mkdir -p $(BUILD)
	$(SWIFTC) $(COMMON) -module-name GibsonDemo -Onone \
		-target $(shell uname -m)-apple-macos$(TARGET_OS) -o $@ $(SOURCES) $(DEMO_SOURCE)

# Renders a still offscreen, used for the README images.
screenshot: $(BUILD)/snapshot
	$(BUILD)/snapshot docs/screenshot.png 2560 1440 6

$(BUILD)/snapshot: $(SOURCES) $(SHOT_SOURCE)
	@mkdir -p $(BUILD)
	$(SWIFTC) $(COMMON) -module-name GibsonSnapshot -Onone \
		-target $(shell uname -m)-apple-macos$(TARGET_OS) -o $@ $(SOURCES) $(SHOT_SOURCE)

# Full screen preview through the system engine.
#
# ScreenSaverEngine runs hardened without a library validation exemption, so it
# is killed with "Code Signature Invalid" the moment it loads an ad hoc signed
# saver. Only useful with SIGN_ID set to a real Developer ID certificate. The
# screen saver itself is fine: at idle macOS loads it through
# legacyScreenSaver.appex, which does carry the exemption.
preview: install
	@if codesign -dvv "$(BUILD)/$(PRODUCT)" 2>&1 | grep -q adhoc; then \
		echo "warning: ad hoc signed build, ScreenSaverEngine will refuse to load it"; \
		echo "         use 'make demo' to iterate, or set SIGN_ID to a Developer ID"; \
	fi
	/System/Library/CoreServices/ScreenSaverEngine.app/Contents/MacOS/ScreenSaverEngine

lint:
	@if command -v swiftformat >/dev/null; then \
		swiftformat --lint Sources; \
	else \
		echo "swiftformat not installed, skipping"; \
	fi

clean:
	rm -rf $(BUILD)
