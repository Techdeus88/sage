local c = {}
c.__index = c

local autocmd = vim.api.nvim_create_autocmd

function c.run()
    autocmd("VimEnter", {
        group = vim.api.nvim_create_augroup("SageLoader", { clear = true }),
        pattern = "*",
        once = true,
        callback = function()
            local start_time = _G.Sage.start
            local time_duration = string.format("%.2f", (vim.loop.hrtime() - start_time) / 1e6)
            local api = c.api
        end
    })
    
    autocmd("UiEnter", {
        group = vim.api.nvim_create_augroup("SageLoader", { clear = true }),
        pattern = "*",
        once = true,
        callback = function()
            local start_time = _G.Sage.start
            local time_duration = string.format("%.2f", (vim.loop.hrtime() - start_time) / 1e6)
            local api = c.api
            api:track_event("uienter", time_duration)
        end
    })
    
    autocmd("PackChangedPre", {
        group = vim.api.nvim_create_augroup("SageLoader", { clear = true }),
        callback = function(event)
            local kind = event.data.kind
            local spec = event.data.spec
            local name = spec.name
            local sage_manager = c.manager
            local Pack = c.manager.packs[name]
    
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
            local sage_manager = c.manager
            local Pack = c.manager.packs[name]
    
            if not Pack then
                return -- Pack not in our system, skip
            end
    
            local n_spec = Pack.specs.normalize
            local Event = c.bus
    
            if kind == "install" then
                Pack:set_path(pack_path)
                vim.notify(string.format("✓ Installed %s", n_spec.name), vim.log.levels.INFO)
                -- NOTE: Build handling moved to install_activate_batch for consistency
                -- Manual builds should be run separately or as part of pack config
    
            elseif kind == "update" then
                Pack:set_status("updated")
                vim.notify(string.format("✓ Updated %s", n_spec.name), vim.log.levels.INFO)
                c.bus.emit("pack:updated", {
                    name = name,
                    status = "updated",
                    pack = Pack,
                })
    
            elseif kind == "delete" then
                Pack:set_status("deleted")
                vim.notify(string.format("✓ Deleted %s", n_spec.name), vim.log.levels.INFO)
                c.bus.emit("pack:deleted", {
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
            
            if c.loader and c.loader.close_all then
                pcall(function()
                    c.loader.close_all()
                end)
            end
    
            
            if c.dashboard and c.dashboard.close then
                pcall(function()
                    c.dashboard:close()
                end)
            end
    
            
            if c.bus and c.bus.clear then
                pcall(function()
                    c.bus.clear()
                end)
            end
    
            vim.notify("Sage cleanup complete before exit", vim.log.levels.INFO)
        end,
    })
end

function c.init(container)
    local self = setmetatable({}, c)
    self.contaimer = container
    self.api = container:resolve("api")
    self.dashboard = container:resolve("dashboard")
    self.loader = container:resolve("loader")
    self.bus = container:resolve("bus")

    local ok, err = pcall(c.run)
    if not ok then
        vim.notify("Base command initialization errored", vim.log.levels.ERROR)
    end
    
    return self
end

return c