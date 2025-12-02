.PHONY: test test-unit test-integration test-watch test-coverage clean

# Default target
all: test

# Run all tests
test:
	@echo "Running all tests..."
	busted --verbose

# Run only unit tests
test-unit:
	@echo "Running unit tests..."
	busted --tags=unit tests/spec/

# Run only integration tests
test-integration:
	@echo "Running integration tests..."
	busted --config=.busted integration

# Watch mode - re-run tests on file changes
test-watch:
	@echo "Running tests in watch mode..."
	while true; do \
		inotifywait -e modify -r lua/ tests/; \
		clear; \
		busted --verbose; \
	done

# Run tests with coverage
test-coverage:
	@echo "Running tests with coverage..."
	busted --config=.busted coverage
	@echo "Coverage report generated in coverage.json"

# Run specific test file
test-file:
	@if [ -z "$(FILE)" ]; then \
		echo "Usage: make test-file FILE=tests/spec/ui/elements_spec.lua"; \
	else \
		busted --verbose $(FILE); \
	fi

# Run tests matching a pattern
test-pattern:
	@if [ -z "$(PATTERN)" ]; then \
		echo "Usage: make test-pattern PATTERN='should render'"; \
	else \
		busted --verbose --filter="$(PATTERN)"; \
	fi

# Clean generated files
clean:
	@echo "Cleaning generated files..."
	rm -f coverage.json
	rm -f luacov.*.out
	rm -rf lua_modules

# Install test dependencies
install-deps:
	@echo "Installing test dependencies..."
	luarocks install busted
	luarocks install luacov
	luarocks install luacheck

# Lint code
lint:
	@echo "Running luacheck..."
	luacheck lua/ --globals vim

# Help
help:
	@echo "Available targets:"
	@echo "  test              - Run all tests"
	@echo "  test-unit         - Run unit tests only"
	@echo "  test-integration  - Run integration tests only"
	@echo "  test-watch        - Run tests in watch mode"
	@echo "  test-coverage     - Run tests with coverage"
	@echo "  test-file         - Run specific test file (use FILE=path)"
	@echo "  test-pattern      - Run tests matching pattern (use PATTERN='...')"
	@echo "  clean             - Clean generated files"
	@echo "  install-deps      - Install test dependencies"
	@echo "  lint              - Run luacheck linter"
