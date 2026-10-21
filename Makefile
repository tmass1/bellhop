.PHONY: build test lint run probe clean

# Overridable from the shell. Developer ID keeps the Accessibility grant stable across rebuilds.
CODESIGN_IDENTITY ?= Developer ID Application: Thomas Massaro (Y5V8Y3BH9A)
export CODESIGN_IDENTITY

# Extra flags for valet-probe, e.g. make probe ARGS="--delay 5"
ARGS ?=

build:
	swift build

test:
	swift test

lint:
	swiftlint lint --strict --quiet

run:
	pkill -x Valet 2>/dev/null || true
	scripts/bundle.sh
	open dist/Valet.app

probe:
	@mkdir -p .build && xattr -w com.dropbox.ignored 1 .build 2>/dev/null || true
	swift build -c release --product valet-probe
	"$$(swift build -c release --show-bin-path)/valet-probe" $(ARGS)

clean:
	rm -rf .build dist
