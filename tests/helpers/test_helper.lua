-- Test helper that sets up the testing environment
local mock_nvim = require("tests.helpers.nvim_mock")

-- Setup before all tests
_G.before_each(function()
    -- Mock vim global
    _G.vim = mock_nvim.create_vim_mock()
end)

-- Cleanup after each test
_G.after_each(function()
    -- Reset mocks
    if package.loaded["sage.ui.dashboard"] then
        package.loaded["sage.ui.dashboard"] = nil
    end
    if package.loaded["sage.ui.elements"] then
        package.loaded["sage.ui.elements"] = nil
    end
    if package.loaded["sage.ui.renderer"] then
        package.loaded["sage.ui.renderer"] = nil
    end
end)

-- Helper functions
_G.test_helpers = {
    -- Create a minimal pack object for testing
    create_mock_pack = function(overrides)
        local pack = {
            name = overrides.name or "test-pack",
            status = overrides.status or "created",
            stage = overrides.stage or "now",
            message = overrides.message or "Test pack",
            path = overrides.path or "/test/path",
            pack = {
                specs = {
                    normalize = {
                        data = {
                            on = overrides.triggers or {},
                            depends = overrides.depends or {},
                        },
                    },
                },
                times = {
                    install_duration = overrides.install_duration or 0,
                    config_duration = overrides.config_duration or 0,
                },
            },
        }
        return pack
    end,

    -- Create a mock container
    create_mock_container = function()
        local container = {
            services = {},
            resolve = function(self, name)
                return self.services[name]
            end,
            register = function(self, name, service)
                self.services[name] = service
            end,
        }
        return container
    end,

    -- Create a mock event bus
    create_mock_bus = function()
        local bus = {
            handlers = {},
            on = function(self, event, handler)
                self.handlers[event] = self.handlers[event] or {}
                table.insert(self.handlers[event], handler)
            end,
            emit = function(self, event, data)
                if self.handlers[event] then
                    for _, handler in ipairs(self.handlers[event]) do
                        handler(data)
                    end
                end
            end,
            clear = function(self)
                self.handlers = {}
            end,
        }
        return bus
    end,
}
