APP      := TodoPop
CONFIG   := release
BIN      := .build/$(CONFIG)/$(APP)
BUNDLE   := $(APP).app
CONTENTS := $(BUNDLE)/Contents
VERSION  := $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist 2>/dev/null || echo dev)

.PHONY: build test bundle run relaunch dist clean

## Compile the executable.
build:
	swift build -c $(CONFIG)

## Run the headless logic tests (plain executable; no XCTest needed).
test:
	swift run TodoPopCheck

## Assemble a double-clickable .app bundle (menu-bar-only via LSUIElement).
bundle: build
	rm -rf $(BUNDLE)
	mkdir -p $(CONTENTS)/MacOS
	mkdir -p $(CONTENTS)/Resources
	cp $(BIN) $(CONTENTS)/MacOS/$(APP)
	cp Resources/Info.plist $(CONTENTS)/Info.plist
	@echo "Built $(BUNDLE)"

## Build the bundle and launch it (appears in the menu bar).
run: bundle
	open $(BUNDLE)

## Kill any running instance, then rebuild and relaunch.
relaunch:
	-pkill -x $(APP) || true
	$(MAKE) run

## Build a distributable zip of the .app (ad-hoc signed; not notarized).
dist: bundle
	codesign --force --deep --sign - $(BUNDLE) || true
	rm -f $(APP)-$(VERSION).zip
	ditto -c -k --sequesterRsrc --keepParent $(BUNDLE) $(APP)-$(VERSION).zip
	@echo "Created $(APP)-$(VERSION).zip"

clean:
	rm -rf .build $(BUNDLE) $(APP)-*.zip
