APP      := beacon.app
BIN      := .build/release/beacon
APPS_DIR := /Applications

.PHONY: build run release app install link unlink clean fin help

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

build: ## Build a debug binary
	swift build

run: ## Build and launch the popup (dev)
	swift run

release: ## Build an optimized release binary
	swift build -c release

app: ## Build beacon.app bundle
	./build-app.sh

install: app ## Copy beacon.app into /Applications
	rm -rf "$(APPS_DIR)/$(APP)"
	cp -r "$(APP)" "$(APPS_DIR)/$(APP)"
	@echo "Installed $(APPS_DIR)/$(APP)"

link: app ## Symlink beacon.app into /Applications (points at this build)
	rm -rf "$(APPS_DIR)/$(APP)"
	ln -s "$(CURDIR)/$(APP)" "$(APPS_DIR)/$(APP)"
	@echo "Linked $(APPS_DIR)/$(APP) -> $(CURDIR)/$(APP)"

unlink: ## Remove beacon.app from /Applications
	rm -rf "$(APPS_DIR)/$(APP)"
	@echo "Removed $(APPS_DIR)/$(APP)"

fin: ## Install the patched fin CLI from ../fin
	cd ../fin && go install .

clean: ## Remove build artifacts
	rm -rf .build "$(APP)"
