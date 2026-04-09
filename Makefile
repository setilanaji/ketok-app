# Ketok — Build & Package Commands
# ──────────────────────────────────────

SCHEME     = Ketok
BUILD_DIR  = build
APP_NAME   = Ketok

.PHONY: build archive dmg clean run help

help: ## Show available commands
	@echo ""
	@echo "  Ketok — Build Commands"
	@echo "  ────────────────────────────"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'
	@echo ""

build: ## Build the app (debug)
	xcodebuild build \
		-project $(SCHEME).xcodeproj \
		-scheme $(SCHEME) \
		-configuration Debug \
		-destination "platform=macOS" \
		CODE_SIGN_IDENTITY="-" \
		| xcbeautify 2>/dev/null || true

release: ## Build the app (release)
	xcodebuild build \
		-project $(SCHEME).xcodeproj \
		-scheme $(SCHEME) \
		-configuration Release \
		-destination "platform=macOS" \
		CODE_SIGN_IDENTITY="-" \
		| xcbeautify 2>/dev/null || true

dmg: ## Build and create DMG installer
	./Scripts/build_dmg.sh

dmg-notarize: ## Build, create DMG, and notarize
	./Scripts/build_dmg.sh --notarize

clean: ## Remove build artifacts
	rm -rf $(BUILD_DIR)
	xcodebuild clean \
		-project $(SCHEME).xcodeproj \
		-scheme $(SCHEME) \
		2>/dev/null || true
	@echo "✓ Cleaned"

run: ## Build and run the app
	xcodebuild build \
		-project $(SCHEME).xcodeproj \
		-scheme $(SCHEME) \
		-configuration Debug \
		-destination "platform=macOS" \
		CODE_SIGN_IDENTITY="-" \
		2>/dev/null
	@open "$(BUILD_DIR)/Build/Products/Debug/$(APP_NAME).app" 2>/dev/null || \
		open "$$(find ~/Library/Developer/Xcode/DerivedData -name '$(APP_NAME).app' -path '*/Debug/*' | head -1)" 2>/dev/null || \
		echo "⚠ Could not find built app. Run from Xcode instead."
