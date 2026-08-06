APP_NAME   := WhatsAppSandbox
BUILD_DIR  := build
APP_DIR    := $(BUILD_DIR)/$(APP_NAME).app
CONTENTS   := $(APP_DIR)/Contents
MACOS_DIR  := $(CONTENTS)/MacOS
RES_DIR    := $(CONTENTS)/Resources
BIN        := $(MACOS_DIR)/$(APP_NAME)
PLIST_SRC  := src/Info.plist
ENT_SRC    := src/app.entitlements
ICNS_SRC   := src/AppIcon.icns
DMG_NAME   := WhatsAppSandbox-1.0.10.dmg

.PHONY: all icon dmg run install uninstall clean verify

all: $(APP_DIR)

$(APP_DIR): $(BIN) $(PLIST_SRC) $(ENT_SRC) $(ICNS_SRC)
	@cp $(PLIST_SRC) $(CONTENTS)/Info.plist
	@mkdir -p $(RES_DIR)
	@cp $(ICNS_SRC) $(RES_DIR)/AppIcon.icns
	@codesign --force --sign - --entitlements $(ENT_SRC) $(APP_DIR)

$(BIN): src/main.swift
	@mkdir -p $(MACOS_DIR)
	@swiftc -O -framework AppKit -framework WebKit -o $@ src/main.swift

icon: build/icon_1024.png build/AppIcon.iconset
	@iconutil -c icns build/AppIcon.iconset -o src/AppIcon.icns

build/icon_1024.png: scripts/AppIcon.swift
	@mkdir -p $(BUILD_DIR)
	@swift scripts/AppIcon.swift $@

build/AppIcon.iconset: build/icon_1024.png
	@rm -rf $@
	@mkdir -p $@
	@for s in 16 32 64 128 256 512; do sips -z $$s $$s $< --out $@/icon_$${s}x$${s}.png >/dev/null; done
	@for s in 16 32 128 256 512; do s2=$$((s*2)); sips -z $$s2 $$s2 $< --out $@/icon_$${s}x$${s}@2x.png >/dev/null; done

dmg: all src/ReadMe.txt
	@rm -rf $(BUILD_DIR)/staging dist
	@mkdir -p $(BUILD_DIR)/staging dist
	@cp -R $(APP_DIR) $(BUILD_DIR)/staging/
	@cp src/ReadMe.txt $(BUILD_DIR)/staging/ReadMe.txt
	@ln -s /Applications $(BUILD_DIR)/staging/Applications
	@hdiutil create -volname "WhatsApp Sandbox" -srcfolder $(BUILD_DIR)/staging -ov -format UDZO -fs HFS+ dist/$(DMG_NAME) >/dev/null
	@rm -rf $(BUILD_DIR)/staging
	@echo "Built dist/$(DMG_NAME)"

run: all
	@open $(APP_DIR)

install: all
	@rm -rf "/Applications/$(APP_NAME).app"
	@cp -R $(APP_DIR) /Applications/
	@echo "Installed to /Applications/$(APP_NAME).app"

uninstall:
	@rm -rf "/Applications/$(APP_NAME).app"
	@echo "Removed /Applications/$(APP_NAME).app"

verify: all
	@codesign --verify --deep --strict $(APP_DIR)
	@codesign -d --entitlements - $(APP_DIR)
	@echo "Signature and entitlements OK"

clean:
	@rm -rf $(BUILD_DIR)
	@echo "Cleaned $(BUILD_DIR)"
