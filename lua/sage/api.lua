- ============================================================================
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

return API._singleton
end

function Metrics.new(container)
    local self = setmetatable({}, Metrics)

    self.container = container
    self.manager = self.container:resolve("manager")
    self.utils = self.container:resolve("utils")
    self.bus = self.container:resolve("bus")

    -- Initialize stats structure
    self.stats = {
        times = {
            events = {},
            loads = {},
            installs = {},
            tasks = {},
            stages = {}
        },
        counts = {
            total = 0,
            loaded = 0,
            failed = 0,
            installing = 0,
            pending = 0,
            disabled = 0
        },
        session = {
            start_time = vim.loop.hrtime(),
            total_duration = 0
        }
    }

    -- Setup event listeners for automatic tracking
    self:setup_event_listeners()

    return self
end

-- ============================================================================
-- Event Listeners for Automatic Tracking
-- ============================================================================

function Metrics:setup_event_listeners()
    if not self.bus then
        return
    end

    -- Track installation events
    self.bus.on("pack:install:start", function(data)
        self:track_event("install:start:" .. data.name, vim.loop.hrtime())
    end)

    self.bus.on("pack:install:finish", function(data)
        self:track_event("install:finish:" .. data.name, vim.loop.hrtime())
        if data.install_duration then
            self:track_install_time(data.name, data.install_duration)
        end
    end)

    -- Track task events
    self.bus.on("pack:task:complete", function(data)
        self:track_task(data.name, data.task_id, {
            status = data.status,
            duration = data.duration,
            error = data.error
        })
    end)

    -- Track load events
    self.bus.on("pack:load:complete", function(data)
        self:track_event("load:complete:" .. data.name, vim.loop.hrtime())
    end)

    -- Track completion
    self.bus.on("pack:run_complete", function(data)
        self.stats.session.total_duration = data.total_duration or 0
        self:track_event("run:complete", vim.loop.hrtime())
    end)
end

-- ============================================================================
-- Event Tracking
-- ============================================================================

function Metrics:track_event(event, value)
    if not self.stats.times or not self.stats.times.events then
        return false, "Stats not initialized"
    end

    self.stats.times.events[event] = value
    return true, string.format("Event '%s' tracked", event)
end

function Metrics:track_install_time(pack_name, duration)
    if not self.stats.times.installs then
        self.stats.times.installs = {}
    end
    self.stats.times.installs[pack_name] = duration
end

function Metrics:track_task(pack_name, task_id, task_data)
    if not self.stats.times.tasks then
        self.stats.times.tasks = {}
    end
    if not self.stats.times.tasks[pack_name] then
        self.stats.times.tasks[pack_name] = {}
    end
    self.stats.times.tasks[pack_name][task_id] = task_data
end

function Metrics:get_event(event)
    if self.stats and self.stats.times and self.stats.times.events then
        return self.stats.times.events[event]
    end
    return nil
end

-- ============================================================================
-- Stats Collection
-- ============================================================================

function Metrics:get_stats()
    if not self.manager or not self.manager.packs then
        return self.stats
    end

    local packs = self.manager.packs

    -- Reset counts
    self.stats.counts = {
        total = 0,
        loaded = 0,
        failed = 0,
        installing = 0,
        pending = 0,
        disabled = 0,
        by_stage = {
            now = 0,
            lazy = 0,
            later = 0,
            disabled = 0
        }
    }

    -- Collect per-pack times
    if not self.stats.times then
        self.stats.times = {}
    end

    -- Count packs by status and stage
    for name, pack in pairs(packs) do
        self.stats.counts.total = self.stats.counts.total + 1

        -- Count by status
        local status = pack:get_status()
        if status == "loaded" or status == "complete" then
            self.stats.counts.loaded = self.stats.counts.loaded + 1
        elseif status == "failed" then
            self.stats.counts.failed = self.stats.counts.failed + 1
        elseif status == "installing" then
            self.stats.counts.installing = self.stats.counts.installing + 1
        elseif status == "pending" then
            self.stats.counts.pending = self.stats.counts.pending + 1
        elseif status == "disabled" then
            self.stats.counts.disabled = self.stats.counts.disabled + 1
        end

        -- Count by stage
        local stage = pack:get_stage()
        if self.stats.counts.by_stage[stage] then
            self.stats.counts.by_stage[stage] = self.stats.counts.by_stage[stage] + 1
        end

        -- Store pack times
        if pack.times then
            self.stats.times[name] = pack.times
        end
    end

    -- Calculate session duration
    local current_time = vim.loop.hrtime()
    local elapsed = (current_time - self.stats.session.start_time) / 1e6
    self.stats.session.elapsed_ms = string.format("%.2f", elapsed)

    return self.stats
end

-- ============================================================================
-- Pack Status Information
-- ============================================================================

function Metrics:get_status()
    if not self.manager or not self.manager.packs then
        return {}
    end

    local packs = self.manager.packs
    local status = {}

    for name, pack in pairs(packs) do
        status[name] = {
            name = name,
            status = pack:get_status(),
            stage = pack:get_stage(),
            installed = pack.installed or false,
            loaded = pack.loaded or false,
            failed = pack.failed or false,
            times = pack.times or {},
            path = pack:get_path(),
        }
    end

    return status
end

function Metrics:get_pack_status(pack_name)
    if not self.manager or not self.manager.packs then
        return nil
    end

    local pack = self.manager.packs[pack_name]
    if not pack then
        return nil
    end

    return {
        name = pack_name,
        status = pack:get_status(),
        stage = pack:get_stage(),
        installed = pack.installed or false,
        loaded = pack.loaded or false,
        failed = pack.failed or false,
        times = pack.times or {},
        path = pack:get_path(),
        lifecycle = pack.lifecycle and {
            completed = pack.lifecycle.completed,
            progress = pack.lifecycle:get_progress()
        } or nil
    }
end

-- ============================================================================
-- Configuration Information
-- ============================================================================

function Metrics:get_config()
    if not self.manager or not self.manager.packs then
        return {}
    end

    local packs = self.manager.packs
    local config = {}

    for name, pack in pairs(packs) do
        local spec = pack.specs and pack.specs.normalize
        config[name] = {
            name = name,
            status = pack:get_status(),
            stage = pack:get_stage(),
            installed = pack.installed or false,
            loaded = pack.loaded or false,
            failed = pack.failed or false,
            times = pack.times or {},
            path = pack:get_path(),
            spec = spec and {
                src = spec.src,
                name = spec.name,
                stage = spec.stage,
                data = spec.data
            } or nil
        }
    end

    return config
end

function Metrics:get_pack_config(pack_name)
    if not self.manager or not self.manager.packs then
        return nil
    end

    local pack = self.manager.packs[pack_name]
    if not pack then
        return nil
    end

    local spec = pack.specs and pack.specs.normalize
    return {
        name = pack_name,
        status = pack:get_status(),
        stage = pack:get_stage(),
        spec = spec and {
            src = spec.src,
            name = spec.name,
            stage = spec.stage,
            data = spec.data
        } or nil
    }
end

-- ============================================================================
-- Vim Pack Information
-- ============================================================================

function Metrics:get_vim_info(pack_name)
    local ok, result = pcall(vim.pack.get, { name = pack_name })
    if ok then
        return result
    end
    return nil
end

-- ============================================================================
-- Stage Lists
-- ============================================================================

function Metrics:get_stage_lists()
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

function Metrics:get_packs_by_stage(stage)
    local sorted = self:get_stage_lists()
    return sorted[stage] or {}
end

-- ============================================================================
-- Performance Metrics
-- ============================================================================

function Metrics:get_performance_summary()
    local summary = {
        session = {
            elapsed = self.stats.session.elapsed_ms or "0",
            total_duration = self.stats.session.total_duration or "0"
        },
        counts = self.stats.counts,
        slowest_installs = {},
        slowest_tasks = {},
        failed_packs = {}
    }

    -- Find slowest installs
    if self.stats.times.installs then
        local installs = {}
        for name, duration in pairs(self.stats.times.installs) do
            table.insert(installs, { name = name, duration = tonumber(duration) or 0 })
        end
        table.sort(installs, function(a, b) return a.duration > b.duration end)
        summary.slowest_installs = vim.list_slice(installs, 1, 5)
    end

    -- Find failed packs
    if self.manager and self.manager.packs then
        for name, pack in pairs(self.manager.packs) do
            if pack:get_status() == "failed" then
                table.insert(summary.failed_packs, {
                    name = name,
                    error = pack.error or "unknown error"
                })
            end
        end
    end

    return summary
end

-- ============================================================================
-- Task Metrics
-- ============================================================================

function Metrics:get_task_summary()
    local summary = {
        total_tasks = 0,
        successful = 0,
        failed = 0,
        skipped = 0,
        by_pack = {}
    }

    if not self.stats.times.tasks then
        return summary
    end

    for pack_name, tasks in pairs(self.stats.times.tasks) do
        local pack_summary = {
            total = 0,
            successful = 0,
            failed = 0,
            skipped = 0,
            tasks = {}
        }

        for task_id, task_data in pairs(tasks) do
            pack_summary.total = pack_summary.total + 1
            summary.total_tasks = summary.total_tasks + 1

            if task_data.status == "success" then
                pack_summary.successful = pack_summary.successful + 1
                summary.successful = summary.successful + 1
            elseif task_data.status == "failed" then
                pack_summary.failed = pack_summary.failed + 1
                summary.failed = summary.failed + 1
            elseif task_data.status == "skipped" then
                pack_summary.skipped = pack_summary.skipped + 1
                summary.skipped = summary.skipped + 1
            end

            table.insert(pack_summary.tasks, {
                id = task_id,
                status = task_data.status,
                duration = task_data.duration,
                error = task_data.error
            })
        end

        summary.by_pack[pack_name] = pack_summary
    end

    return summary
end

-- ============================================================================
-- Utility Functions
-- ============================================================================

function Metrics:reset_stats()
    self.stats = {
        times = {
            events = {},
            loads = {},
            installs = {},
            tasks = {},
            stages = {}
        },
        counts = {
            total = 0,
            loaded = 0,
            failed = 0,
            installing = 0,
            pending = 0,
            disabled = 0
        },
        session = {
            start_time = vim.loop.hrtime(),
            total_duration = 0
        }
    }
end

function Metrics:print_summary()
    local stats = self:get_stats()
    local performance = self:get_performance_summary()

    print("=== Sage Pack Manager Metrics ===")
    print(string.format("Total Packs: %d", stats.counts.total))
    print(string.format("Loaded: %d", stats.counts.loaded))
    print(string.format("Failed: %d", stats.counts.failed))
    print(string.format("Session Duration: %sms", stats.session.elapsed_ms))

    if #performance.failed_packs > 0 then
        print("\n=== Failed Packs ===")
        for _, failed in ipairs(performance.failed_packs) do
            print(string.format("  - %s: %s", failed.name, failed.error))
        end
    end

    if #performance.slowest_installs > 0 then
        print("\n=== Slowest Installs ===")
        for _, install in ipairs(performance.slowest_installs) do
            print(string.format("  - %s: %.2fms", install.name, install.duration))
        end
    end
end

return Metrics
local API = {}

function API.new(container)
    local self = setmetatable({}, API)

    self.container = container

    self.manager = self.container:resolve("manager")
    self.utils = self.container:resolve("utils")

    self.stats = {}
    self.stats.times = {}
    self.stats.times.events = {}
    self.stats.times.loads = {}
    self.stats.times.installs = {}

    return self
end

function API:get_stage_lists()
    local Manager = self.manager
    local utils = self.utils
    local Packs = Manager.packs
    local all_packs = vim.tbl_values(Packs)
    local sorted = utils.sort_packs(all_packs)

    return sorted
end

function API:get_event(event)
    if self["stats"] and self["stats"].times.events[event] ~= nil then
        return self.stats.times.events[event]
    end
end

function API:get_stats()
    local Packs = self.manager:get_packs()

    self.stats["counted"] = 0
    self.stats["loaded"] = 0
    self.stats["failed"] = 0

    for name, pack in pairs(Packs) do
        self.stats["counted"] = self.stats["counted"] + 1
        if not pack.loaded then
            self.stats["failed"] = self.stats["failed"] + 1
        else
            self.stats["loaded"] = self.stats["loaded"] + 1
        end
        self.stats["times"][name] = pack.times
    end
    return self.stats
end

return API
--- ============================================================================
-- metrics.lua (FIXED & ENHANCED)
-- ============================================================================

local Metrics = {}
Metrics.__index = Metrics
Metrics._singleton = nil

function Metrics.get_singleton(container)
    if Metrics._singleton == nil then
        Metrics._singleton = Metrics.new(container)
    end
    return Metrics._singleton
end

function Metrics.new(container)
    local self = setmetatable({}, Metrics)

    self.container = container
    self.manager = self.container:resolve("manager")
    self.utils = self.container:resolve("utils")
    self.bus = self.container:resolve("bus")

    -- Initialize stats structure
    self.stats = {
        times = {
            events = {},
            loads = {},
            installs = {},
            tasks = {},
            stages = {}
        },
        counts = {
            total = 0,
            loaded = 0,
            failed = 0,
            installing = 0,
            pending = 0,
            disabled = 0
        },
        session = {
            start_time = vim.loop.hrtime(),
            total_duration = 0
        }
    }

    -- Setup event listeners for automatic tracking
    self:setup_event_listeners()

    return self
end

-- ============================================================================
-- Event Listeners for Automatic Tracking
-- ============================================================================

function Metrics:setup_event_listeners()
    if not self.bus then
        return
    end

    -- Track installation events
    self.bus.on("pack:install:start", function(data)
        self:track_event("install:start:" .. data.name, vim.loop.hrtime())
    end)

    self.bus.on("pack:install:finish", function(data)
        self:track_event("install:finish:" .. data.name, vim.loop.hrtime())
        if data.install_duration then
            self:track_install_time(data.name, data.install_duration)
        end
    end)

    -- Track task events
    self.bus.on("pack:task:complete", function(data)
        self:track_task(data.name, data.task_id, {
            status = data.status,
            duration = data.duration,
            error = data.error
        })
    end)

    -- Track load events
    self.bus.on("pack:load:complete", function(data)
        self:track_event("load:complete:" .. data.name, vim.loop.hrtime())
    end)

    -- Track completion
    self.bus.on("pack:run_complete", function(data)
        self.stats.session.total_duration = data.total_duration or 0
        self:track_event("run:complete", vim.loop.hrtime())
    end)
end

-- ============================================================================
-- Event Tracking
-- ============================================================================

function Metrics:track_event(event, value)
    if not self.stats.times or not self.stats.times.events then
        return false, "Stats not initialized"
    end

    self.stats.times.events[event] = value
    return true, string.format("Event '%s' tracked", event)
end

function Metrics:track_install_time(pack_name, duration)
    if not self.stats.times.installs then
        self.stats.times.installs = {}
    end
    self.stats.times.installs[pack_name] = duration
end

function Metrics:track_task(pack_name, task_id, task_data)
    if not self.stats.times.tasks then
        self.stats.times.tasks = {}
    end
    if not self.stats.times.tasks[pack_name] then
        self.stats.times.tasks[pack_name] = {}
    end
    self.stats.times.tasks[pack_name][task_id] = task_data
end

function Metrics:get_event(event)
    if self.stats and self.stats.times and self.stats.times.events then
        return self.stats.times.events[event]
    end
    return nil
end

-- ============================================================================
-- Stats Collection
-- ============================================================================

function Metrics:get_stats()
    if not self.manager or not self.manager.packs then
        return self.stats
    end

    local packs = self.manager.packs

    -- Reset counts
    self.stats.counts = {
        total = 0,
        loaded = 0,
        failed = 0,
        installing = 0,
        pending = 0,
        disabled = 0,
        by_stage = {
            now = 0,
            lazy = 0,
            later = 0,
            disabled = 0
        }
    }

    -- Collect per-pack times
    if not self.stats.times then
        self.stats.times = {}
    end

    -- Count packs by status and stage
    for name, pack in pairs(packs) do
        self.stats.counts.total = self.stats.counts.total + 1

        -- Count by status
        local status = pack:get_status()
        if status == "loaded" or status == "complete" then
            self.stats.counts.loaded = self.stats.counts.loaded + 1
        elseif status == "failed" then
            self.stats.counts.failed = self.stats.counts.failed + 1
        elseif status == "installing" then
            self.stats.counts.installing = self.stats.counts.installing + 1
        elseif status == "pending" then
            self.stats.counts.pending = self.stats.counts.pending + 1
        elseif status == "disabled" then
            self.stats.counts.disabled = self.stats.counts.disabled + 1
        end

        -- Count by stage
        local stage = pack:get_stage()
        if self.stats.counts.by_stage[stage] then
            self.stats.counts.by_stage[stage] = self.stats.counts.by_stage[stage] + 1
        end

        -- Store pack times
        if pack.times then
            self.stats.times[name] = pack.times
        end
    end

    -- Calculate session duration
    local current_time = vim.loop.hrtime()
    local elapsed = (current_time - self.stats.session.start_time) / 1e6
    self.stats.session.elapsed_ms = string.format("%.2f", elapsed)

    return self.stats
end

-- ============================================================================
-- Pack Status Information
-- ============================================================================

function Metrics:get_status()
    if not self.manager or not self.manager.packs then
        return {}
    end

    local packs = self.manager.packs
    local status = {}

    for name, pack in pairs(packs) do
        status[name] = {
            name = name,
            status = pack:get_status(),
            stage = pack:get_stage(),
            installed = pack.installed or false,
            loaded = pack.loaded or false,
            failed = pack.failed or false,
            times = pack.times or {},
            path = pack:get_path(),
        }
    end

    return status
end

function Metrics:get_pack_status(pack_name)
    if not self.manager or not self.manager.packs then
        return nil
    end

    local pack = self.manager.packs[pack_name]
    if not pack then
        return nil
    end

    return {
        name = pack_name,
        status = pack:get_status(),
        stage = pack:get_stage(),
        installed = pack.installed or false,
        loaded = pack.loaded or false,
        failed = pack.failed or false,
        times = pack.times or {},
        path = pack:get_path(),
        lifecycle = pack.lifecycle and {
            completed = pack.lifecycle.completed,
            progress = pack.lifecycle:get_progress()
        } or nil
    }
end

-- ============================================================================
-- Configuration Information
-- ============================================================================

function Metrics:get_config()
    if not self.manager or not self.manager.packs then
        return {}
    end

    local packs = self.manager.packs
    local config = {}

    for name, pack in pairs(packs) do
        local spec = pack.specs and pack.specs.normalize
        config[name] = {
            name = name,
            status = pack:get_status(),
            stage = pack:get_stage(),
            installed = pack.installed or false,
            loaded = pack.loaded or false,
            failed = pack.failed or false,
            times = pack.times or {},
            path = pack:get_path(),
            spec = spec and {
                src = spec.src,
                name = spec.name,
                stage = spec.stage,
                data = spec.data
            } or nil
        }
    end

    return config
end

function Metrics:get_pack_config(pack_name)
    if not self.manager or not self.manager.packs then
        return nil
    end

    local pack = self.manager.packs[pack_name]
    if not pack then
        return nil
    end

    local spec = pack.specs and pack.specs.normalize
    return {
        name = pack_name,
        status = pack:get_status(),
        stage = pack:get_stage(),
        spec = spec and {
            src = spec.src,
            name = spec.name,
            stage = spec.stage,
            data = spec.data
        } or nil
    }
end

-- ============================================================================
-- Vim Pack Information
-- ============================================================================

function Metrics:get_vim_info(pack_name)
    local ok, result = pcall(vim.pack.get, { name = pack_name })
    if ok then
        return result
    end
    return nil
end

-- ============================================================================
-- Stage Lists
-- ============================================================================

function Metrics:get_stage_lists()
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

function Metrics:get_packs_by_stage(stage)
    local sorted = self:get_stage_lists()
    return sorted[stage] or {}
end

-- ============================================================================
-- Performance Metrics
-- ============================================================================

function Metrics:get_performance_summary()
    local summary = {
        session = {
            elapsed = self.stats.session.elapsed_ms or "0",
            total_duration = self.stats.session.total_duration or "0"
        },
        counts = self.stats.counts,
        slowest_installs = {},
        slowest_tasks = {},
        failed_packs = {}
    }

    -- Find slowest installs
    if self.stats.times.installs then
        local installs = {}
        for name, duration in pairs(self.stats.times.installs) do
            table.insert(installs, { name = name, duration = tonumber(duration) or 0 })
        end
        table.sort(installs, function(a, b) return a.duration > b.duration end)
        summary.slowest_installs = vim.list_slice(installs, 1, 5)
    end

    -- Find failed packs
    if self.manager and self.manager.packs then
        for name, pack in pairs(self.manager.packs) do
            if pack:get_status() == "failed" then
                table.insert(summary.failed_packs, {
                    name = name,
                    error = pack.error or "unknown error"
                })
            end
        end
    end

    return summary
end

-- ============================================================================
-- Task Metrics
-- ============================================================================

function Metrics:get_task_summary()
    local summary = {
        total_tasks = 0,
        successful = 0,
        failed = 0,
        skipped = 0,
        by_pack = {}
    }

    if not self.stats.times.tasks then
        return summary
    end

    for pack_name, tasks in pairs(self.stats.times.tasks) do
        local pack_summary = {
            total = 0,
            successful = 0,
            failed = 0,
            skipped = 0,
            tasks = {}
        }

        for task_id, task_data in pairs(tasks) do
            pack_summary.total = pack_summary.total + 1
            summary.total_tasks = summary.total_tasks + 1

            if task_data.status == "success" then
                pack_summary.successful = pack_summary.successful + 1
                summary.successful = summary.successful + 1
            elseif task_data.status == "failed" then
                pack_summary.failed = pack_summary.failed + 1
                summary.failed = summary.failed + 1
            elseif task_data.status == "skipped" then
                pack_summary.skipped = pack_summary.skipped + 1
                summary.skipped = summary.skipped + 1
            end

            table.insert(pack_summary.tasks, {
                id = task_id,
                status = task_data.status,
                duration = task_data.duration,
                error = task_data.error
            })
        end

        summary.by_pack[pack_name] = pack_summary
    end

    return summary
end

-- ============================================================================
-- Utility Functions
-- ============================================================================

function Metrics:reset_stats()
    self.stats = {
        times = {
            events = {},
            loads = {},
            installs = {},
            tasks = {},
            stages = {}
        },
        counts = {
            total = 0,
            loaded = 0,
            failed = 0,
            installing = 0,
            pending = 0,
            disabled = 0
        },
        session = {
            start_time = vim.loop.hrtime(),
            total_duration = 0
        }
    }
end

function Metrics:print_summary()
    local stats = self:get_stats()
    local performance = self:get_performance_summary()

    print("=== Sage Pack Manager Metrics ===")
    print(string.format("Total Packs: %d", stats.counts.total))
    print(string.format("Loaded: %d", stats.counts.loaded))
    print(string.format("Failed: %d", stats.counts.failed))
    print(string.format("Session Duration: %sms", stats.session.elapsed_ms))

    if #performance.failed_packs > 0 then
        print("\n=== Failed Packs ===")
        for _, failed in ipairs(performance.failed_packs) do
            print(string.format("  - %s: %s", failed.name, failed.error))
        end
    end

    if #performance.slowest_installs > 0 then
        print("\n=== Slowest Installs ===")
        for _, install in ipairs(performance.slowest_installs) do
            print(string.format("  - %s: %.2fms", install.name, install.duration))
        end
    end
end

return Metrics
