
-- ============================================================================
-- metrics.lua (FIXED & ENHANCED)
-- ============================================================================

local Metrics = {}
Metrics.__index = Metrics
Metrics._singleton = nil

function Metrics:get_singleton(container)
    if self._singleton == nil then
        self._singleton = self.new(container)
    end
    return self._singleton
end
-- ============================================================================
-- metrics.lua (FIXED & ENHANCED)
-- ============================================================================

local Metrics = {}
Metrics.__index = Metrics
Metrics._singleton = nil

function Metrics.get_singleton(container)
    if Metrics._singleton == nil then
        Metrics._singleton = Metrics.new(container)
    end
    return Metrics

function Metrics.new(container)
    local self = setmetatable({}, Metrics)

    self.container = container

    self.bus = self.container:resolve("bus")
    self.manager = self.container:resolve("manager")
    self.utils = self.container:resolve("utils")

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

