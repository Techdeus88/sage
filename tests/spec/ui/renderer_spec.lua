describe("Renderer", function()
    local Renderer
    local mock_nvim
    local bus
    local dashboard

    before_each(function()
        mock_nvim = require("tests.helpers.nvim_mock")
        mock_nvim.reset()

        -- Mock render queue
        local RenderQueue = {
            new = function()
                return {
                    queue = {},
                    push = function(self, fn)
                        table.insert(self.queue, fn)
                        fn() -- Execute immediately for tests
                    end,
                    flush = function(self)
                        self.queue = {}
                    end,
                }
            end,
        }

        bus = test_helpers.create_mock_bus()

        dashboard = {
            add_pack = spy.new(function() end),
            find = spy.new(function(name)
                return {
                    name = name,
                    elements = {
                        status = { update = function() end },
                        message = { update = function() end },
                    },
                }
            end),
            update_row = spy.new(function() end),
            apply_update_to_row = spy.new(function() end),
            debug_log = function() end,
            is_ready = true,
        }

        local dm = {
            dashboard = dashboard,
        }

        Renderer = require("sage.ui.renderer")
    end)

    describe("Pack Creation", function()
        it("should handle pack creation events", function()
            local RenderQueue = {
                new = function()
                    return {
                        queue = {},
                        push = function(self, fn)
                            fn() -- Execute immediately
                        end,
                        flush = function(self) end,
                    }
                end,
            }

            local dm = { dashboard = dashboard }
            local renderer = Renderer.new(bus, dm, RenderQueue)

            local pack_data = test_helpers.create_mock_pack({ name = "test-pack" })
            renderer:on_pack_created(pack_data)

            -- Dashboard's add_pack should be called
            assert.spy(dashboard.add_pack).was_called()
        end)

        it("should queue pending updates for non-existent rows", function()
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

            dashboard.find = spy.new(function()
                return nil
            end)

            local dm = { dashboard = dashboard }
            local renderer = Renderer.new(bus, dm, RenderQueue)

            local update_data = {
                name = "non-existent",
                status = "loaded",
            }

            renderer:render_pack_updated(update_data)

            assert.is_not_nil(renderer.pending_updates["non-existent"])
        end)

        it("should apply pending updates when row is created", function()
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

            -- Queue an update for non-existent row
            dashboard.find = spy.new(function()
                return nil
            end)
            renderer:render_pack_updated({
                name = "test-pack",
                status = "installing",
            })

            -- Now create the row
            dashboard.find = spy.new(function(name)
                return {
                    name = name,
                    elements = {},
                }
            end)

            renderer:render_pack_created(test_helpers.create_mock_pack({
                name = "test-pack",
            }))

            -- Pending update should be cleared
            assert.is_nil(renderer.pending_updates["test-pack"])
        end)
    end)

    describe("Pack Updates", function()
        it("should handle status updates", function()
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

            renderer:on_pack_updated({
                name = "test-pack",
                status = "loaded",
            })

            assert.spy(dashboard.find).was_called_with(dashboard, "test-pack")
            assert.spy(dashboard.update_row).was_called()
        end)

        it("should apply updates to row elements", function()
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

            local row = {
                elements = {
                    status = { update = spy.new(function() end) },
                    message = { update = spy.new(function() end) },
                },
            }

            local dm = {
                dashboard = {
                    find = function()
                        return row
                    end,
                    update_row = function() end,
                    apply_update_to_row = function(self, r, data)
                        if data.status then
                            r.elements.status:update(data.status)
                        end
                        if data.message then
                            r.elements.message:update(data.message)
                        end
                    end,
                    debug_log = function() end,
                },
            }

            local renderer = Renderer.new(bus, dm, RenderQueue)

            renderer:render_pack_updated({
                name = "test-pack",
                status = "loaded",
                message = "Done",
            })

            assert.spy(row.elements.status.update).was_called_with(row.elements.status, "loaded")
            assert.spy(row.elements.message.update).was_called_with(row.elements.message, "Done")
        end)
    end)

    describe("Event Listeners", function()
        it("should register all event listeners", function()
            local RenderQueue = {
                new = function()
                    return {
                        push = function(self, fn) end,
                        flush = function(self) end,
                    }
                end,
            }

            local dm = { dashboard = dashboard }
            local renderer = Renderer.new(bus, dm, RenderQueue)

            renderer:register_listeners()

            assert.is_not_nil(bus.handlers["pack:created"])
            assert.is_not_nil(bus.handlers["pack:install:start"])
            assert.is_not_nil(bus.handlers["pack:install:finish"])
            assert.is_not_nil(bus.handlers["pack:load:start"])
            assert.is_not_nil(bus.handlers["pack:load:complete"])
            assert.is_not_nil(bus.handlers["pack:config:start"])
            assert.is_not_nil(bus.handlers["pack:config:finish"])
            assert.is_not_nil(bus.handlers["pack:failed"])
        end)

        it("should respond to pack:created events", function()
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

            bus:emit("pack:created", test_helpers.create_mock_pack({ name = "new-pack" }))

            assert.spy(dashboard.add_pack).was_called()
        end)

        it("should respond to pack:failed events", function()
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

            bus:emit("pack:failed", {
                name = "test-pack",
                status = "failed",
                message = "Error occurred",
            })

            assert.spy(dashboard.update_row).was_called()
        end)
    end)

    describe("Cleanup", function()
        it("should reset state on cleanup", function()
            local RenderQueue = {
                new = function()
                    return {
                        flush = spy.new(function() end),
                    }
                end,
            }

            local dm = { dashboard = dashboard }
            local renderer = Renderer.new(bus, dm, RenderQueue)

            renderer.created_count = 10
            renderer.update_count = 20
            renderer.pending_updates = { ["test"] = {} }

            renderer:cleanup()

            assert.equals(0, renderer.created_count)
            assert.equals(0, renderer.update_count)
            assert.equals(0, vim.tbl_count(renderer.pending_updates))
        end)
    end)
end)
