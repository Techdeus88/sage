describe("Full Flow Integration #integration", function()
    local Dashboard, Renderer, elements, icons, mock_nvim

    before_each(function()
        mock_nvim = require("tests.helpers.nvim_mock")
        mock_nvim.reset()

        elements = require("sage.ui.elements")
        Dashboard = require("sage.ui.dashboard")
        Renderer = require("sage.ui.renderer")

        icons = {
            status = { loaded = "●", failed = "✗", created = "◌" },
            stage = { now = "▶", later = "▷", lazy = "◐", disabled = "○" },
            install = "󰚰",
            config = "󱁐",
        }
    end)

    it("should handle complete pack lifecycle", function()
        -- Setup
        local container = test_helpers.create_mock_container()
        local bus = test_helpers.create_mock_bus()

        container:register("bus", bus)
        container:register("manager", {
            packs = {
                ["lifecycle-pack"] = {
                    specs = {
                        normalize = {
                            data = {
                                on = { cmds = { "Test" } },
                                depends = {},
                            },
                        },
                    },
                    times = {
                        install_duration = 0,
                        config_duration = 0,
                    },
                },
            },
        })
        container:register("utils", {
            get_dep_names = function(deps)
                return {}
            end,
        })
        container:register("logger", { debug = function() end })

        -- Create dashboard
        local dashboard = setmetatable({}, Dashboard)
        dashboard:init(container, elements, icons, {})
        dashboard.content_buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(dashboard.content_buf, 0, -1, false, {})

        -- Create renderer
        local RenderQueue = {
            new = function()
                return {
                    push = function(self, fn)
                        fn()
                    end,
                    flush = function(self) end,
                }
            end,
        }
        local dm = { dashboard = dashboard }
        local renderer = Renderer.new(bus, dm, RenderQueue)
        renderer:register_listeners()

        -- Test lifecycle: created -> installing -> installed -> loading -> loaded

        -- 1. Pack created
        bus:emit(
            "pack:created",
            test_helpers.create_mock_pack({
                name = "lifecycle-pack",
                status = "created",
                stage = "now",
            })
        )

        local row = dashboard:find("lifecycle-pack")
        assert.is_not_nil(row)
        assert.equals("created", row.elements.status.value)

        -- 2. Install starts
        bus:emit("pack:install:start", {
            name = "lifecycle-pack",
            status = "installing",
            message = "Installing...",
        })

        row = dashboard:find("lifecycle-pack")
        assert.equals("installing", row.elements.status.value)

        -- 3. Install finishes
        bus:emit("pack:install:finish", {
            name = "lifecycle-pack",
            status = "installed",
            message = "Installed",
            install_duration = 15.5,
        })

        row = dashboard:find("lifecycle-pack")
        assert.equals("installed", row.elements.status.value)

        -- 4. Loading starts
        bus:emit("pack:load:start", {
            name = "lifecycle-pack",
            status = "loading",
            message = "Loading...",
        })

        row = dashboard:find("lifecycle-pack")
        assert.equals("loading", row.elements.status.value)

        -- 5. Config starts
        bus:emit("pack:config:start", {
            name = "lifecycle-pack",
            status = "configuring",
            message = "Configuring...",
        })

        row = dashboard:find("lifecycle-pack")
        assert.equals("configuring", row.elements.status.value)

        -- 6. Config finishes
        bus:emit("pack:config:finish", {
            name = "lifecycle-pack",
            status = "configured",
            message = "Configured",
            config_duration = 8.2,
        })

        row = dashboard:find("lifecycle-pack")
        assert.equals("configured", row.elements.status.value)

        -- 7. Loading completes
        bus:emit("pack:load:complete", {
            name = "lifecycle-pack",
            status = "loaded",
            message = "Loaded",
        })

        row = dashboard:find("lifecycle-pack")
        assert.equals("loaded", row.elements.status.value)

        -- Verify final state
        assert.equals("lifecycle-pack", row.name)
        assert.equals("loaded", row.elements.status.value)
        assert.equals("now", row.elements.stage.value)
    end)

    it("should handle pack failures", function()
        local container = test_helpers.create_mock_container()
        local bus = test_helpers.create_mock_bus()

        container:register("bus", bus)
        container:register("manager", {
            packs = {
                ["failing-pack"] = {
                    specs = {
                        normalize = {
                            data = { on = {}, depends = {} },
                        },
                    },
                    times = { install_duration = 0, config_duration = 0 },
                },
            },
        })
        container:register("utils", {
            get_dep_names = function(deps)
                return {}
            end,
        })
        container:register("logger", { debug = function() end })

        local dashboard = setmetatable({}, Dashboard)
        dashboard:init(container, elements, icons, {})
        dashboard.content_buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(dashboard.content_buf, 0, -1, false, {})

        local RenderQueue = {
            new = function()
                return {
                    push = function(self, fn)
                        fn()
                    end,
                    flush = function(self) end,
                }
            end,
        }
        local dm = { dashboard = dashboard }
        local renderer = Renderer.new(bus, dm, RenderQueue)
        renderer:register_listeners()

        -- Create pack
        bus:emit(
            "pack:created",
            test_helpers.create_mock_pack({
                name = "failing-pack",
                status = "created",
            })
        )

        -- Simulate failure
        bus:emit("pack:failed", {
            name = "failing-pack",
            status = "failed",
            message = "Installation failed: Network error",
        })

        local row = dashboard:find("failing-pack")
        assert.equals("failed", row.elements.status.value)
    end)

    it("should handle multiple packs simultaneously", function()
        local container = test_helpers.create_mock_container()
        local bus = test_helpers.create_mock_bus()

        container:register("bus", bus)
        container:register("manager", {
            packs = {
                ["pack-a"] = {
                    specs = { normalize = { data = { on = {}, depends = {} } } },
                    times = { install_duration = 0, config_duration = 0 },
                },
                ["pack-b"] = {
                    specs = { normalize = { data = { on = {}, depends = {} } } },
                    times = { install_duration = 0, config_duration = 0 },
                },
                ["pack-c"] = {
                    specs = { normalize = { data = { on = {}, depends = {} } } },
                    times = { install_duration = 0, config_duration = 0 },
                },
            },
        })
        container:register("utils", {
            get_dep_names = function(deps)
                return {}
            end,
        })
        container:register("logger", { debug = function() end })

        local dashboard = setmetatable({}, Dashboard)
        dashboard:init(container, elements, icons, {})
        dashboard.content_buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(dashboard.content_buf, 0, -1, false, {})

        local RenderQueue = {
            new = function()
                return {
                    push = function(self, fn)
                        fn()
                    end,
                    flush = function(self) end,
                }
            end,
        }
        local dm = { dashboard = dashboard }
        local renderer = Renderer.new(bus, dm, RenderQueue)
        renderer:register_listeners()

        -- Create multiple packs
        bus:emit("pack:created", test_helpers.create_mock_pack({ name = "pack-a" }))
        bus:emit("pack:created", test_helpers.create_mock_pack({ name = "pack-b" }))
        bus:emit("pack:created", test_helpers.create_mock_pack({ name = "pack-c" }))

        -- Update them differently
        bus:emit("pack:install:finish", {
            name = "pack-a",
            status = "installed",
            install_duration = 10.0,
        })

        bus:emit("pack:load:complete", {
            name = "pack-b",
            status = "loaded",
        })

        bus:emit("pack:failed", {
            name = "pack-c",
            status = "failed",
        })

        -- Verify all packs tracked correctly
        assert.equals(3, #dashboard.rows)
        assert.equals("installed", dashboard:find("pack-a").elements.status.value)
        assert.equals("loaded", dashboard:find("pack-b").elements.status.value)
        assert.equals("failed", dashboard:find("pack-c").elements.status.value)
    end)
end)
