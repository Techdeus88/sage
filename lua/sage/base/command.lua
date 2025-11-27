local c = {}

function c:run_commands()
    local dashboard = c.container:resolve("dashboard")
    local logger = c.container:resolve("logger")

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
    vim.keymap.set("n", "<leader>s", "<cmd>Sage<cr>", { desc = "Open Sage dashboard" })
    vim.keymap.set("n", "<leader>st", "<cmd>SageToggle<cr>", { desc = "Toggle Sage dashboard" })
end

function c:run_autocmds()
    local commands = require("sage.commands")

    local api = c.container:resolve("metrics")
    local bus = c.container:resolve("bus")
    local manager = c.container:resolve("manager")

    local autocmd = vim.api.nvim_create_autocmd

    autocmd("VimEnter", {
        group = vim.api.nvim_create_augroup("SageLoader", { clear = true }),
        pattern = "*",
        once = true,
        callback = function()
            local start_time = _G.Sage.start
            local time_duration = string.format("%.2f", (vim.loop.hrtime() - start_time) / 1e6)
            api:track_event("vimenter", time_duration)
        end,
    })

    autocmd("UiEnter", {
        group = vim.api.nvim_create_augroup("SageLoader", { clear = true }),
        pattern = "*",
        once = true,
        callback = function()
            local start_time = _G.Sage.start
            local time_duration = string.format("%.2f", (vim.loop.hrtime() - start_time) / 1e6)
            api:track_event("uienter", time_duration)
        end,
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
            --    local confirmed = vim.fn.confirm("Install plugin " .. n_spec.name .. "?", "&Yes\n&No", 2) == 1
              --  if not confirmed then
                --    error("Install cancelled for " .. n_spec.name)
                 -- end
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

    local group = vim.api.nvim_create_augroup("Sage", { clear = true })

    local hooks = function(ev)
        local name, kind = ev.data.spec.name, ev.data.kind
         if kind == "install" or kind == "update" then
            local spec = ev.data.spec ---@type Sage.Spec
            if spec.data and spec.data.build ~= nil then
                local name = spec.name
                local Pack = manager.packs[name]
                Pack.set_path(ev.data.path)
                commands.build({ spec }, ev.data.path)
            end
        end
    end
    
    autocmd("PackChanged", { callback = hooks, group = group })

    autocmd("PackChanged", {
        callback = function(ev)
            -- {
              -- buf = 7,
              -- data = {
                -- active = false,
                -- kind = "install",
                -- path = "/home/techdeus/.local/share/mini/site/pack/core/opt/ashen.nvim",
                -- spec = {
                  -- name = "ashen.nvim",
                 -- src = "https://github.com/ficcdaf/ashen.nvim"
               -- }
             -- },
              -- event = "PackChanged",
              -- file = "/home/techdeus/.local/share/mini/site/pack/core/opt/ashen.nvim",
              -- group = 16,
              -- id = 30,
              -- match = "/home/techdeus/.local/share/mini/site/pack/core/opt/ashen.nvim"
            -- }

            local kind = ev.data.kind
            local spec = ev.data.spec
            local pack_path = ev.data.path
            local name = spec.name
            local Pack = manager.packs[name]

            if not Pack then
                return -- Pack not in our system, skip
            end

            if kind == "update" then
                Pack:set_status("updated")
                vim.notify(string.format("✓ Updated %s", n_spec.name), vim.log.levels.INFO)
                bus.emit("pack:updated", {
                    name = name,
                    status = "updated",
                    pack = Pack,
                })
            end
            if kind == "delete" then
                Pack:set_status("deleted")
                vim.notify(string.format("✓ Deleted %s", n_spec.name), vim.log.levels.INFO)
                bus.emit("pack:deleted", {
                    name = name,
                    status = "deleted",
                    pack = Pack,
                })
            end
        end,
        group = group,
    })

    -- autocmd("VimLeavePre", {
    --     group = vim.api.nvim_create_augroup("SageLoader", { clear = true }),
    --     desc = "Cleanup all loaders and dashboard before exit",
    --     callback = function()
    --         if loader and loader.close_all then
    --             pcall(function()
    --                 loader.close_all()
    --             end)
    --         end
    --
    --         if dashboard and dashboard.close then
    --             pcall(function()
    --                 dashboard:close()
    --             end)
    --         end
    --
    --         if bus and bus.clear then
    --             pcall(function()
    --                 bus.clear()
    --             end)
    --         end
    --
    --         vim.notify("Sage cleanup complete before exit", vim.log.levels.INFO)
    --     end,
    -- })
end

function c.init(container)
    c.container = container
    return c
end

function c.setup_commands()
    c:run_commands()
    c:run_autocmds()
end

return c
