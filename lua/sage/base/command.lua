local c = {}


function c:run_commands()
    local dashboard = c.dashboard
    local logger = c.logger

    local command = vim.api.nvim_create_user_command

    command("Sage", function()
        dashboard:open()
    end, { desc = "Open Sage dashboard" })

    -- Add Logger command
    command("SageLogger", function()
        if logger then
            logger:toggle_log_window()
        else
            vim.notify("Logger not available", vim.log.levels.ERROR)
        end
    end, { desc = "Toggle Sage log window" })

    -- Add keymaps
    vim.keymap.set("n", "<leader>s", function()
        if dashboard then
            dashboard:open()
        end
    end, { desc = "Sage Dashboard (open)", silent = true })

    vim.keymap.set("n", "<leader>sl", function()
        if logger then
            logger:toggle_log_window()
        else
            vim.notify("Logger not available", vim.log.levels.ERROR)
        end
    end, { desc = "Sage Logger (toggle)", silent = true })
end

function c:run_autocmds()
    local api = c.api
    local manager = c.manager
    local bus = c.bus
    local dashboard = c.dashboard
    local loader = c.loader

    local autocmd = vim.api.nvim_create_autocmd

    autocmd("VimEnter", {
        group = vim.api.nvim_create_augroup("SageLoader", { clear = true }),
        pattern = "*",
        once = true,
        callback = function()
            local start_time = _G.Sage.start
            local time_duration = string.format("%.2f", (vim.loop.hrtime() - start_time) / 1e6)
            api:track_event("vimenter", time_duration)
        end
    })

    autocmd("UiEnter", {
        group = vim.api.nvim_create_augroup("SageLoader", { clear = true }),
        pattern = "*",
        once = true,
        callback = function()
            local start_time = _G.Sage.start
            local time_duration = string.format("%.2f", (vim.loop.hrtime() - start_time) / 1e6)
            api:track_event("uienter", time_duration)
        end
    })

    autocmd("PackChangedPre", {
        group = vim.api.nvim_create_augroup("SageLoader", { clear = true }),
        callback = function(event)
            local kind = event.data.kind
            local spec = event.data.spec
            local name = spec.name
            local Pack = manager.packs[name]

            if not Pack then
                return -- Pack not in our system., skip
            end

            local n_spec = Pack.specs.normalize

            if kind == "install" then
                local confirmed = vim.fn.confirm("Install plugin " .. n_spec.name .. "?", "&Yes\n&No", 2) == 1
                if not confirmed then
                    error("Install cancelled for " .. n_spec.name)
                end
                Pack:set_status("installing")
            elseif kind == "delete" then
                local confirmed = vim.fn.confirm("Delete plugin " .. n_spec.name .. "?", "&Yes\n&No", 2) == 1
                if not confirmed then
                    error("Deletion cancelled for " .. n_spec.name)
                end
                Pack:set_status("deleting")
            elseif kind == "update" then
                local confirmed = vim.fn.confirm("Update plugin " .. n_spec.name .. "?", "&Yes\n&No", 2) == 1
                if not confirmed then
                    error("Update cancelled for " .. n_spec.name)
                end
                Pack:set_status("updating")
            end
        end,
    })

    autocmd("PackChanged", {
        group = vim.api.nvim_create_augroup("SageLoader", { clear = true }),
        callback = function(ev)
            local kind = ev.data.kind
            local spec = ev.data.spec
            local pack_path = ev.data.path
            local name = spec.name
            local Pack = manager.packs[name]

            if not Pack then
                return -- Pack not in our system, skip
            end

            local n_spec = Pack.specs.normalize

            if kind == "install" then
                Pack:set_path(pack_path)
                vim.notify(string.format("✓ Installed %s", n_spec.name), vim.log.levels.INFO)
                -- NOTE: Build handling moved to install_activate_batch for consistency
                -- Manual builds should be run separately or as part of pack config

            elseif kind == "update" then
                Pack:set_status("updated")
                vim.notify(string.format("✓ Updated %s", n_spec.name), vim.log.levels.INFO)
                bus.emit("pack:updated", {
                    name = name,
                    status = "updated",
                    pack = Pack,
                })

            elseif kind == "delete" then
                Pack:set_status("deleted")
                vim.notify(string.format("✓ Deleted %s", n_spec.name), vim.log.levels.INFO)
                bus.emit("pack:deleted", {
                    name = name,
                    status = "deleted",
                    pack = Pack,
                })
            end
        end,
    })


    autocmd("VimLeavePre", {
        group = vim.api.nvim_create_augroup("SageLoader", { clear = true }),
        desc = "Cleanup all loaders and dashboard before exit",
        callback = function()
            if loader and loader.close_all then
                pcall(function()
                    loader.close_all()
                end)
            end


            if dashboard and dashboard.close then
                pcall(function()
                    dashboard:close()
                end)
            end


            if bus and bus.clear then
                pcall(function()
                    bus.clear()
                end)
            end

            vim.notify("Sage cleanup complete before exit", vim.log.levels.INFO)
        end,
    })
end

function c.init(container)
    c.container = container
    c.api = c.container:resolve("api")
    c.bus = c.container:resolve("bus")
    c.dashboard = c.container:resolve("dashboard")
    c.loader = c.container:resolve("loader")
    c.logger = c.container:resolve("logger")

    c.run_commands()
    c.run_autocmds()

    return c
end

return c
