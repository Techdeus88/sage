
vim.api.nvim_create_autocmd("VimEnter", {
    pattern = "*",
    once = true,
    callback = function()
        local time_duration = string.format("%.2f", (vim.loop.hrtime() - SageGlobal.start) / 1e6)
        local api = require("sage.api")
        api:track_event("vimenter", time_duration)
    end,
})

vim.api.nvim_create_autocmd("UiEnter", {
    pattern = "*",
    once = true,
    callback = function()
        local time_duration = string.format("%.2f", (vim.loop.hrtime() - SageGlobal.start) / 1e6)
        local api = require("sage.api")
        api:track_event("uienter", time_duration)
    end,
})

vim.api.nvim_create_autocmd("PackChangedPre", {
    group = vim.api.nvim_create_augroup("SageLoader", { clear = true }),
    callback = function(event)
        local bus = require("sage.core.bus")
        local kind = event.data.kind
        local spec = event.data.spec
        local name = spec.name

        local sage_manager = require("sage.manager")
        local Pack = sage_manager.packs[name]
        local n_spec = Pack.specs.normalize

        if kind == "install" then
            Pack:set_status("installing")
            bus:emit("pack:install:start", {
                name = n_spec.name,
                status = Pack:get_status(),
                message = "Installing",
            }, "manager:install")
        elseif kind == "delete" then
            local confirmed = vim.fn.confirm("Delete plugin " .. n_spec.name .. "?", "&Yes\n&No", s2) == 1
            if not confirmed then
                error("Deletion cancelled for " .. n_spec.name) -- Aborts the delete
            end

            Pack:set_status("deleting")
            bus:emit("pack:delete:start", {
                name = n_spec.name,
                status = Pack:get_status(),
                message = "Deleting",
            }, "manager:delete")
            vim.notify("Deleting: " .. n_spec.name .. " at " .. event.data.path, vim.log.levels.WARN)
        elseif kind == "update" then
            local confirmed = vim.fn.confirm("Update plugin " .. n_spec.name .. "?", "&Yes\n&No", 2) == 1
            if not confirmed then
                error("Update cancelled for " .. n_spec.name) -- Aborts the delete
            end

            Pack:set_status("updating")
            bus:emit("pack:update:start", {
                name = n_spec.name,
                status = Pack:get_status(),
                message = "Updating",
            }, "manager:update")
            vim.notify("Updating: " .. n_spec.name .. " at " .. event.data.path, vim.log.levels.WARN)
        end

        vim.notify(string.format("Processed Pre %s: %s", n_spec.name, kind), vim.log.levels.INFO)
    end,
})

vim.api.nvim_create_autocmd("PackChanged", {
    group = vim.api.nvim_create_augroup("SageLoader", { clear = true }),
    callback = function(ev)
        local bus = require("sage.core.bus")
        local kind = ev.data.kind
        local spec = ev.data.spec
        local pack_path = ev.data.path
        local name = spec.name
        local sage_manager = require("sage.manager")
        local Pack = sage_manager.packs[name]
        local n_spec = Pack.specs.normalize

        if kind == "install" then
            vim.notify("Install complete: ", spec.name, vim.log.levels.DEBUG, { title = "Sage Debug" })
            Pack:set_status("installed")
            Pack:set_path(pack_path)

            bus:emit("pack:install:finish", {
                name = n_spec.name,
                status = Pack:get_status(),
                message = "Install completed",
            }, "manager:install")

            -- temporarily change directory
            local old_cwd = vim.fn.getcwd()
            pcall(vim.fn.chdir, pack_path)

            if n_spec and n_spec.data.build then
                local ok, _ = pcall(n_spec.data.build)
                if not ok then
                    vim.notify(string.format("Failed to build %s", n_spec.name), vim.log.levels.ERROR)
                end
                if ok then
                    vim.notify(string.format("Built %s", n_spec.name), vim.log.levels.INFO)
                end
            end
            -- restore
            pcall(vim.fn.chdir, old_cwd)
        elseif kind == "update" then
            Pack:set_status("updated")
            bus:emit("pack:update:finish", {
                name = n_spec.name,
                message = "Update completed",
                status = "Update complete",
            }, "manager:update")
        elseif kind == "delete" then
            Pack:set_status("deleted")
            bus:emit("pack:delete:finish", {
                name = n_spec.name,
                status = Pack:get_status(),
                message = "Delete completed',
            }, "manager:delete")
        end

        vim.notify(string.format("Processed %s: %s", n_spec.name, kind), vim.log.levels.INFO)
    end,
})

vim.api.nvim_create_autocmd("VimLeavePre", {
    desc = "Cleanup all loaders and dashboard before exit",
    callback = function()
        local ok1, loader = pcall(require, "sage.core.loader")
        if ok1 and loader and loader.close_all then
            pcall(function()
                loader.close_all()
            end)
        end

        local ok2, dashboard = pcall(require, "sage.ui.dashboard")
        if ok2 and dashboard and dashboard.close then
            pcall(function()
                dashboard:close()
            end)
        end

        local ok3, Event = pcall(require, "sage.core.bus")
        if ok3 and Event and Event.clear then
            pcall(function()
                Event.clear()
            end)
        end

        vim.notify("Sage cleanup complete before exit", vim.log.levels.INFO)
    end,
})
