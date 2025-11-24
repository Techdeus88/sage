-- ============================================================================
-- DEPS - Dependency resolution and sorting
-- ============================================================================
local Deps = {}

local function get_dep_name(dep, utils)
    if type(dep) == "string" then
        return utils.extract_name(dep)
    else
        if type(dep) == "table" and dep.name then
            return dep.name
        end
        return utils.extract_name(dep[1] or dep.src)
    end
end

function Deps.topological_sort(packs, container)
    local sorted = {}
    local visited = {}
    local visiting = {}
    local manager = container:resolve("manager")
    local utils = container:resolve("utils")
    local pack_by_name = manager._packs

    local function visit(pack)
        local name = pack.specs.normalize.name
        if visited[name] then
            return
        end
        if visiting[name] then
            error(string.format("Circular dependency detected: %s", name))
        end
        visiting[name] = true

        local depends = pack.specs.normalize.data.depends or {}
        for _, dep in ipairs(depends) do
            local dep_name = get_dep_name(dep, utils)
            if dep_name then
                local dep_pack = pack_by_name[dep_name]
                if dep_pack then
                    visit(dep_pack)
                else
                    pack._services.logger:warn(
                        "Deps",
                        string.format("Dependency '%s' not found for '%s'", dep_name, name)
                    )
                end
            end
        end

        visiting[name] = false
        visited[name] = true
        table.insert(sorted, pack)
    end

    for _, pack in ipairs(packs) do
        visit(pack)
    end
    return sorted
end

function Deps.sort_by_priority(packs)
    local copy = vim.list_extend({}, packs)
    table.sort(copy, function(a, b)
        local priority_a = a.specs.normalize.data.priority or 50
        local priority_b = b.specs.normalize.data.priority or 50
        return priority_a > priority_b
    end)
    return copy
end

function Deps.sort_by_load_order(packs, container)
    local sorted = Deps.topological_sort(packs, container)
    return Deps.sort_by_priority(sorted)
end

function Deps.group_by_dependency_level(packs, utils)
    local levels = {}
    local level_map = {}
    local pack_by_name = {}

    for _, pack in ipairs(packs) do
        pack_by_name[pack.specs.normalize.name] = pack
    end

    local function get_level(pack)
        local name = pack.specs.normalize.name
        if level_map[name] then
            return level_map[name]
        end

        local depends = pack.specs.normalize.data.depends or {}
        local max_dep_level = 0

        for _, dep in ipairs(depends) do
            local dep_name = get_dep_name(dep, utils)
            if dep_name then
                local dep_pack = pack_by_name[dep_name]
                if dep_pack then
                    local dep_level = get_level(dep_pack)
                    max_dep_level = math.max(max_dep_level, dep_level)
                end
            end
        end

        local my_level = max_dep_level + 1
        level_map[name] = my_level
        levels[my_level] = levels[my_level] or {}
        table.insert(levels[my_level], pack)
        return my_level
    end

    for _, pack in ipairs(packs) do
        get_level(pack)
    end

    local result = {}
    for i = 1, #levels do
        if levels[i] then
            table.insert(result, levels[i])
        end
    end
    return result
end

return Deps
