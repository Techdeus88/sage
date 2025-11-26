-- ============================================================================
-- api.lua (FIXED & ENHANCED)
-- ============================================================================

local API = {}
API.__index = API

function API.new(container)
    local self = setmetatable({}, API)

    self.container = container
    self.manager = self.container:resolve("manager")
    self.utils = self.container:resolve("utils")
    self.metrics = self.container:resolve("metrics")

    return self
end

-- ============================================================================
-- Pack Management API
-- ============================================================================

function API:get_pack(pack_name)
    if not self.manager or not self.manager.packs then
        return nil, "Manager not initialized"
    end

    local pack = self.manager.packs[pack_name]
    if not pack then
        return nil, string.format("Pack '%s' not found", pack_name)
    end

    return pack
end

function API:get_all_packs()
    if not self.manager or not self.manager.packs then
        return {}
    end

    return self.manager.packs
end

function API:get_pack_names()
    local packs = self:get_all_packs()
    local names = {}

    for name, _ in pairs(packs) do
        table.insert(names, name)
    end

    table.sort(names)
    return names
end

-- ============================================================================
-- Pack Status API
-- ============================================================================

function API:get_pack_status(pack_name)
    if self.metrics then
        return self.metrics:get_pack_status(pack_name)
    end

    local pack, err = self:get_pack(pack_name)
    if not pack then
        return nil, err
    end

    return {
        name = pack_name,
        status = pack:get_status(),
        stage = pack:get_stage(),
        installed = pack.installed or false,
        loaded = pack.loaded or false,
    }
end

function API:get_all_status()
    if self.metrics then
        return self.metrics:get_status()
    end

    local packs = self:get_all_packs()
    local status = {}

    for name, pack in pairs(packs) do
        status[name] = {
            status = pack:get_status(),
            stage = pack:get_stage(),
            installed = pack.installed or false,
            loaded = pack.loaded or false,
        }
    end

    return status
end

-- ============================================================================
-- Stage Management API
-- ============================================================================

function API:get_stage_lists()
    if not self.manager or not self.manager.packs then
        return {
            now = {},
            lazy = {},
            later = {},
            disabled = {}
        }
    end

    local packs = self.manager.packs
    local all_packs = vim.tbl_values(packs)
    local sorted = self.utils.sort_packs(all_packs)

    return sorted
end

function API:get_packs_by_stage(stage)
    local sorted = self:get_stage_lists()
    return sorted[stage] or {}
end

function API:get_pack_stage(pack_name)
    local pack, err = self:get_pack(pack_name)
    if not pack then
        return nil, err
    end

    return pack:get_stage()
end

-- ============================================================================
-- Statistics API
-- ============================================================================

function API:get_stats()
    if self.metrics then
        return self.metrics:get_stats()
    end

    local packs = self:get_all_packs()
    local stats = {
        counts = {
            total = 0,
            loaded = 0,
            failed = 0
        }
    }

    for name, pack in pairs(packs) do
        stats.counts.total = stats.counts.total + 1

        local status = pack:get_status()
        if status == "loaded" or status == "complete" then
            stats.counts.loaded = stats.counts.loaded + 1
        elseif status == "failed" then
            stats.counts.failed = stats.counts.failed + 1
        end
    end

    return stats
end

function API:get_performance_summary()
    if self.metrics then
        return self.metrics:get_performance_summary()
    end

    return {
        message = "Metrics module not available"
    }
end

function API:get_task_summary()
    if self.metrics then
        return self.metrics:get_task_summary()
    end

    return {
        message = "Metrics module not available"
    }
end

-- ============================================================================
-- Pack Configuration API
-- ============================================================================

function API:get_pack_config(pack_name)
    if self.metrics then
        return self.metrics:get_pack_config(pack_name)
    end

    local pack, err = self:get_pack(pack_name)
    if not pack then
        return nil, err
    end

    local spec = pack.specs and pack.specs.normalize
    return {
        name = pack_name,
        status = pack:get_status(),
        stage = pack:get_stage(),
        spec = spec
    }
end

function API:get_all_configs()
    if self.metrics then
        return self.metrics:get_config()
    end

    local packs = self:get_all_packs()
    local configs = {}

    for name, pack in pairs(packs) do
        local spec = pack.specs and pack.specs.normalize
        configs[name] = {
            status = pack:get_status(),
            stage = pack:get_stage(),
            spec = spec
        }
    end

    return configs
end

-- ============================================================================
-- Pack Control API
-- ============================================================================

function API:reload_pack(pack_name)
    local pack, err = self:get_pack(pack_name)
    if not pack then
        return false, err
    end

    -- Check if pack has a reload method
    if pack.reload and type(pack.reload) == "function" then
        local ok, result = pcall(pack.reload, pack)
        if ok then
            return true, "Pack reloaded successfully"
        else
            return false, string.format("Reload failed: %s", tostring(result))
        end
    end

    return false, "Pack does not support reloading"
end

function API:disable_pack(pack_name)
    local pack, err = self:get_pack(pack_name)
    if not pack then
        return false, err
    end

    pack:set_status("disabled")
    return true, string.format("Pack '%s' disabled", pack_name)
end

function API:enable_pack(pack_name)
    local pack, err = self:get_pack(pack_name)
    if not pack then
        return false, err
    end

    if pack:get_status() == "disabled" then
        pack:set_status("pending")
        return true, string.format("Pack '%s' enabled", pack_name)
    end

    return false, "Pack is not disabled"
end

-- ============================================================================
-- Query API
-- ============================================================================

function API:find_packs(predicate)
    local packs = self:get_all_packs()
    local results = {}

    for name, pack in pairs(packs) do
        if predicate(pack) then
            table.insert(results, pack)
        end
    end

    return results
end

function API:find_packs_by_status(status)
    return self:find_packs(function(pack)
        return pack:get_status() == status
    end)
end

function API:find_packs_by_stage(stage)
    return self:find_packs(function(pack)
        return pack:get_stage() == stage
    end)
end

function API:find_failed_packs()
    return self:find_packs_by_status("failed")
end

function API:find_loaded_packs()
    return self:find_packs(function(pack)
        local status = pack:get_status()
        return status == "loaded" or status == "complete"
    end)
end

-- ============================================================================
-- Event API
-- ============================================================================

function API:get_event(event)
    if self.metrics then
        return self.metrics:get_event(event)
    end
    return nil
end

function API:track_event(event, value)
    if self.metrics then
        return self.metrics:track_event(event, value)
    end
    return false, "Metrics module not available"
end

-- ============================================================================
-- Utility API
-- ============================================================================

function API:inspect_pack(pack_name)
    local pack, err = self:get_pack(pack_name)
    if not pack then
        return nil, err
    end

    local info = {
        name = pack_name,
        status = pack:get_status(),
        stage = pack:get_stage(),
        installed = pack.installed or false,
        loaded = pack.loaded or false,
        path = pack:get_path(),
        times = pack.times or {},
    }

    -- Add lifecycle info if available
    if pack.lifecycle then
        info.lifecycle = {
            completed = pack.lifecycle.completed,
            progress = pack.lifecycle:get_progress(),
            tasks = {}
        }

        for _, task_id in ipairs(pack.lifecycle.task_order) do
            local task = pack.lifecycle:get_task(task_id)
            if task then
                table.insert(info.lifecycle.tasks, {
                    id = task.id,
                    name = task.name,
                    status = task.status,
                    duration = task.duration,
                    error = task.error
                })
            end
        end
    end

    -- Add spec info
    if pack.specs and pack.specs.normalize then
        info.spec = pack.specs.normalize
    end

    return info
end

function API:print_pack_info(pack_name)
    local info, err = self:inspect_pack(pack_name)
    if not info then
        print(string.format("Error: %s", err))
        return
    end

    print(string.format("=== Pack: %s ===", pack_name))
    print(string.format("Status: %s", info.status))
    print(string.format("Stage: %s", info.stage))
    print(string.format("Installed: %s", tostring(info.installed)))
    print(string.format("Loaded: %s", tostring(info.loaded)))

    if info.times and info.times.install_duration then
        print(string.format("Install Time: %sms", info.times.install_duration))
    end

    if info.lifecycle then
        print(string.format("\nLifecycle: %d/%d tasks completed (%.0f%%)",
            info.lifecycle.progress.completed,
            info.lifecycle.progress.total,
            info.lifecycle.progress.percentage))

        print("\nTasks:")
        for _, task in ipairs(info.lifecycle.tasks) do
            local duration_str = task.duration and string.format(" (%.2fms)", task.duration) or ""
            print(string.format("  - %s: %s%s", task.name, task.status, duration_str))
        end
    end
end

function API:print_summary()
    if self.metrics then
        self.metrics:print_summary()
        return
    end

    local stats = self:get_stats()
    print("=== Sage Pack Manager Summary ===")
    print(string.format("Total Packs: %d", stats.counts.total))
    print(string.format("Loaded: %d", stats.counts.loaded))
    print(string.format("Failed: %d", stats.counts.failed))
end

return API

