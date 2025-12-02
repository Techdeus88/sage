# Sage Testing Guide

## Setup

1. Install dependencies:
```bash
make install-deps
```

2. Run all tests:
```bash
make test
```

## Running Tests

- **All tests**: `make test` or `busted`
- **Unit tests only**: `make test-unit`
- **Integration tests**: `make test-integration`
- **Specific file**: `make test-file FILE=tests/spec/ui/elements_spec.lua`
- **By pattern**: `make test-pattern PATTERN='should render'`
- **With coverage**: `make test-coverage`
- **Watch mode**: `make test-watch`

## Test Structure
```
tests/
├── spec/              # Test specifications
│   ├── ui/           # UI component tests
│   ├── core/         # Core functionality tests
│   └── integration/  # Integration tests
├── helpers/          # Test utilities
└── fixtures/         # Mock data
```

## Writing Tests

Example test:
```lua
describe("MyModule", function()
    it("should do something", function()
        local result = my_function()
        assert.equals("expected", result)
    end)
end)
```

## Assertions

- `assert.equals(expected, actual)`
- `assert.is_true(value)`
- `assert.is_nil(value)`
- `assert.has_error(function)`
- `assert.spy(spy_obj).was_called()`
