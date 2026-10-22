.PHONY: build test lint run probe viewer clean

# Overridable from the shell. Developer ID keeps the Accessibility grant stable across rebuilds.
CODESIGN_IDENTITY ?= Developer ID Application: Thomas Massaro (Y5V8Y3BH9A)
export CODESIGN_IDENTITY

# Extra flags for bellhop-probe, e.g. make probe ARGS="--delay 5"
ARGS ?=

build:
	swift build

test:
	swift test

lint:
	swiftlint lint --strict --quiet

run:
	pkill -x Bellhop 2>/dev/null || true
	scripts/bundle.sh
	open dist/Bellhop.app

probe:
	@mkdir -p .build && xattr -w com.dropbox.ignored 1 .build 2>/dev/null || true
	swift build -c release --product bellhop-probe
	"$$(swift build -c release --show-bin-path)/bellhop-probe" $(ARGS)

# Serves the repo on localhost only, for tools/probe-viewer and design/mocks.
viewer:
	@echo "Probe viewer: http://localhost:8765/tools/probe-viewer/"
	@echo "Mocks:        http://localhost:8765/design/mocks/"
	python3 -m http.server 8765 --bind 127.0.0.1

clean:
	rm -rf .build dist
