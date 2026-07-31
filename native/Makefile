# Same shape as veduta's Makefile. SwiftPM builds the binary; `build` wraps it
# in a .app with Info.plist and icon, then signs it.
APP_NAME    := Beacon
BUILD_DIR   := .build
RELEASE_DIR := $(BUILD_DIR)/release
APP_BUNDLE  := $(BUILD_DIR)/$(APP_NAME).app
INSTALL_DIR := /Applications
DIST_DIR    := $(BUILD_DIR)/dist
DIST_APP    := $(DIST_DIR)/$(APP_NAME).app
DIST_DMG    := $(DIST_DIR)/$(APP_NAME).dmg
DMG_STAGING := $(BUILD_DIR)/dmg-staging
ICON_SOURCE := Resources/command-icon-v2.png

# Homebrew tap that ships the cask. `make release` bumps the cask here so
# users can `brew upgrade --cask beacon`.
TAP_REPO  ?= giraphant/homebrew-tap
CASK_PATH := Casks/beacon.rb

# Per-developer signing config lives in Makefile.local (gitignored). It
# defines DEVELOPER_ID_IDENTITY and NOTARY_PROFILE for your Apple account.
# If absent, the placeholders below stand in and the codesign step falls back
# to ad-hoc — that works, but the signature changes on every rebuild, so the
# keychain's "Always Allow" for the relay token never sticks.
-include Makefile.local

DEVELOPER_ID_IDENTITY ?= Developer ID Application: <Your Name> (<TEAMID>)
NOTARY_PROFILE        ?= <YourNotaryProfile>

CODESIGN_IDENTITY ?= $(DEVELOPER_ID_IDENTITY)
CODESIGN_OPTIONS  ?= --options runtime

# XCTest only ships inside Xcode.app; a CommandLineTools-selected toolchain
# fails with "no such module 'XCTest'" without the override.
XCODE_DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

.PHONY: all build run install dist notarize release update-cask test clean

all: build

build:
	swift build -c release --product $(APP_NAME)
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS $(APP_BUNDLE)/Contents/Resources
	@cp $(RELEASE_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	@cp Resources/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	@# The icon only shows on notification banners — LSUIElement means no Dock
	@# tile. Built from the source PNG to keep .icns out of git.
	@iconset=$$(mktemp -d)/AppIcon.iconset; mkdir -p "$$iconset"; \
	sips -z 512 512 $(ICON_SOURCE) --out "$$iconset/icon_512x512.png" >/dev/null; \
	sips -z 1024 1024 $(ICON_SOURCE) --out "$$iconset/icon_512x512@2x.png" >/dev/null; \
	iconutil -c icns "$$iconset" -o $(APP_BUNDLE)/Contents/Resources/AppIcon.icns
	@if security find-identity -v -p codesigning | grep -F "$(CODESIGN_IDENTITY)" >/dev/null 2>&1; then \
		codesign --force $(CODESIGN_OPTIONS) --sign "$(CODESIGN_IDENTITY)" $(APP_BUNDLE); \
		echo "Built $(APP_BUNDLE) (signed: $(CODESIGN_IDENTITY))"; \
	else \
		codesign --force --sign - $(APP_BUNDLE); \
		echo "Built $(APP_BUNDLE) (ad-hoc signed — Developer ID cert missing from keychain)"; \
	fi

run: build
	open $(APP_BUNDLE)

install: build
	@rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	@cp -R $(APP_BUNDLE) "$(INSTALL_DIR)/"
	@echo "Installed to $(INSTALL_DIR)/$(APP_NAME).app"

dist:
	@$(MAKE) build CODESIGN_OPTIONS="--options runtime --timestamp"
	@rm -rf "$(DIST_DIR)" "$(DMG_STAGING)"
	@mkdir -p "$(DIST_DIR)" "$(DMG_STAGING)"
	@cp -R "$(APP_BUNDLE)" "$(DIST_APP)"
	@cp -R "$(APP_BUNDLE)" "$(DMG_STAGING)/$(APP_NAME).app"
	@ln -s /Applications "$(DMG_STAGING)/Applications"
	@hdiutil create -volname "$(APP_NAME)" -srcfolder "$(DMG_STAGING)" -ov -format UDZO "$(DIST_DMG)" >/dev/null
	@codesign --force --sign "$(DEVELOPER_ID_IDENTITY)" --timestamp "$(DIST_DMG)"
	@echo "Packaged $(DIST_DMG)"

notarize: dist
	xcrun notarytool submit "$(DIST_DMG)" --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple "$(DIST_DMG)"
	@echo "Notarized and stapled $(DIST_DMG)"

# One-shot release: assumes Resources/Info.plist already bumped to $(VERSION)
# and committed.
release:
	@if [ -z "$(VERSION)" ]; then echo "Usage: make release VERSION=1.0.0"; exit 1; fi
	@plist_v=$$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist); \
	if [ "$$plist_v" != "$(VERSION)" ]; then \
		echo "ERROR: Info.plist version $$plist_v != VERSION=$(VERSION). Bump Info.plist first."; exit 1; \
	fi
	@if ! git diff-index --quiet HEAD --; then \
		echo "ERROR: working tree has uncommitted changes. Commit the version bump first."; exit 1; \
	fi
	@$(MAKE) notarize
	gh release create "v$(VERSION)" "$(DIST_DMG)" --title "v$(VERSION)" --generate-notes
	@echo "Release v$(VERSION) published. Tag pushed by gh."
	@$(MAKE) update-cask VERSION=$(VERSION)

# Bump the Homebrew cask in $(TAP_REPO) to $(VERSION) with the DMG's sha256.
update-cask:
	@if [ -z "$(VERSION)" ]; then echo "Usage: make update-cask VERSION=1.0.0"; exit 1; fi
	@if [ ! -f "$(DIST_DMG)" ]; then echo "ERROR: $(DIST_DMG) not found. Run 'make dist' first."; exit 1; fi
	@sha=$$(shasum -a 256 "$(DIST_DMG)" | awk '{print $$1}'); \
	tmp=$$(mktemp -d); \
	trap 'rm -rf "$$tmp"' EXIT; \
	echo "Cloning $(TAP_REPO)..."; \
	gh repo clone "$(TAP_REPO)" "$$tmp" -- -q || exit 1; \
	sed -i '' -E "s/^  version \".*\"/  version \"$(VERSION)\"/" "$$tmp/$(CASK_PATH)"; \
	sed -i '' -E "s/^  sha256 \".*\"/  sha256 \"$$sha\"/" "$$tmp/$(CASK_PATH)"; \
	git -C "$$tmp" add "$(CASK_PATH)"; \
	if git -C "$$tmp" diff --cached --quiet; then \
		echo "Cask already at $(VERSION) / $$sha — nothing to push."; \
	else \
		git -C "$$tmp" commit -q -m "beacon $(VERSION)"; \
		git -C "$$tmp" push -q origin HEAD; \
		echo "Cask bumped to $(VERSION) ($$sha) and pushed to $(TAP_REPO)."; \
	fi

test:
	DEVELOPER_DIR=$(XCODE_DEVELOPER_DIR) swift test

clean:
	rm -rf $(BUILD_DIR)
