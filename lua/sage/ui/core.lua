local icons = require("sage.ui.icons")
-- ========================================================================jjjj-- ============================================================================
-- BASE ELEMENT CLASS
-- ============================================================================

local Element = {}
Element.__index = Element

function Element.new(name, initial_value)
    local self = setmetatable({}, Element)
    self.name = name
    self.value = initial_value
    self.dirty = false
    self.visible = true
    self.format_fn = nil -- Custom formatting function
    return self
end

-- Update element value, mark dirty if changed
function Element:update(new_value)
    if self.value ~= new_value then
        self.value = new_value
        self.dirty = true
        return true -- Changed
    end
    return false -- No change
end

-- Get current value
function Element:get()
    return self.value
end

-- Set visibility
function Element:set_visible(visible)
    if self.visible ~= visible then
        self.visible = visible
        self.dirty = true
    end
end

-- Check if element changed
function Element:is_dirty()
    return self.dirty
end

-- Mark clean after rendering
function Element:mark_clean()
    self.dirty = false
end

-- Render element to string
function Element:render()
    if not self.visible then
        return ""
    end

    if self.format_fn then
        return self.format_fn(self.value)
    end

    return tostring(self.value or "")
end

-- Set custom formatter
function Element:set_formatter(fn)
    self.format_fn = fn
    self.dirty = true
end

-- Clone element
function Element:clone()
    local new_elem = Element.new(self.name, self.value)
    new_elem.visible = self.visible
    new_elem.format_fn = self.format_fn
    return new_elem
end

local TextElement = setmetatable({}, { __index = Element })
TextElement.__index = TextElement

function TextElement.new(name, initial_value)
    local self = Element.new(name, initial_value)
    return setmetatable(self, TextElement)
end

-- ============================================================================

local NameElement = setmetatable({}, { __index = TextElement })
NameElement.__index = NameElement

function NameElement.new(name, initial_value)
    local self = TextElement.new(name, initial_value)
    return setmetatable(self, NameElement)
end

function NameElement:render()
    return self.value:upper()
end

-- ============================================================================

local BooleanElement = setmetatable({}, { __index = Element })
BooleanElement.__index = BooleanElement

function BooleanElement.new(name, initial_value, true_text, false_text)
    local self = Element.new(name, initial_value or false)
    self.true_text = true_text or "✓"
    self.false_text = false_text or "○"
    return setmetatable(self, BooleanElement)
end

function BooleanElement:render()
    if not self.visible then
        return ""
    end
    return self.value and self.true_text or self.false_text
end

-- ============================================================================

local LazyElement = setmetatable({}, { __index = Element })
LazyElement.__index = LazyElement

-- Icon mapping for different trigger types
local TRIGGER_ICONS = {
    events = icons.event or "", -- Event icon
    fts = icons.filetype or "󰈔", -- Filetype icon
    cmds = icons.command or "", -- Command icon
    keys = icons.keymap or "󰌓", -- Keymap icon
}

-- Create new LazyTriggerElement
-- @param name: element identifier
-- @param trigger_data: table with trigger information from pack.specs.normalize.data.on
function LazyElement.new(name, trigger_data)
    local self = setmetatable({}, LazyElement)
    self.name = name
    self.trigger_data = trigger_data or {}
    self.trigger_type = nil
    self.trigger_values = {}
    self:_parse_trigger_data()
    return self
end

function LazyElement:render()
    if not self.visible then
        return ""
    end
    return string.format("[%s %s]", self.lazy_map[self.type], self.value)
end

-- Update trigger data (for dynamic updates)
function LazyElement:update(new_trigger_data)
     -- If we have no existing data, always accept the new data (even if empty)
    if self.trigger_type == "none" or not self.trigger_data or not next(self.trigger_data) then
        self.trigger_data = new_trigger_data or {}
        self:_parse_trigger_data()
        return
    end

    -- If we have existing valid data, only update if new data is also valid
    if new_trigger_data and next(new_trigger_data) then
        self.trigger_data = new_trigger_data
        self:_parse_trigger_data()
    end

    self.trigger_data = new_trigger_data or {}
    self:_parse_trigger_data()
end

-- Render as button (similar to timing buttons)
-- Returns: "[icon type: value1, value2]"
function LazyElement:render()
    if not self.visible then
        return ""
    end

    -- Return cached render if data was cleared
    if self.trigger_type == "none" or #self.trigger_values == 0 then
        return self._last_render or "" -- ← Fallback to last valid render
    end

    local icon = TRIGGER_ICONS[self.trigger_type] or ""

    -- Format trigger type label
    local type_label = self.trigger_type
    if self.trigger_type == "fts" then
        type_label = "ft"
    elseif self.trigger_type == "cmds" then
        type_label = "cmd"
    end

    -- Truncate values if too many
    local max_display = 3
    local display_values = {}

    for i = 1, math.min(#self.trigger_values, max_display) do
        table.insert(display_values, self.trigger_values[i])
    end

    local value_str = table.concat(display_values, ", ")

    -- Add ellipsis if truncated
    if #self.trigger_values > max_display then
        value_str = value_str .. " +" .. (#self.trigger_values - max_display)
    end

    -- Limit total length
    local max_length = 30
    if #value_str > max_length then
        value_str = value_str:sub(1, max_length - 3) .. "..."
    end

    local result = string.format("[%s %s: %s]", icon, type_label, value_str)
    self._last_render = result -- ← Cache successful render
    return result
end

-- Render detailed version (for expanded view)
-- Returns: full list without truncation
function LazyElement:render_detailed()
    if self.trigger_type == "none" or #self.trigger_values == 0 then
        return "lazy (no triggers)"
    end

    local icon = TRIGGER_ICONS[self.trigger_type] or ""

    -- Format trigger type label
    local type_label = self.trigger_type
    if self.trigger_type == "fts" then
        type_label = "filetypes"
    elseif self.trigger_type == "cmds" then
        type_label = "commands"
    elseif self.trigger_type == "events" then
        type_label = "events"
    elseif self.trigger_type == "keys" then
        type_label = "keymaps"
    end

    local value_str = table.concat(self.trigger_values, ", ")

    return string.format("%s %s: %s", icon, type_label, value_str)
end

-- Check if has specific trigger type
function LazyElement:has_trigger(trigger_type)
    return self.trigger_type == trigger_type
end

-- Get raw trigger information
function LazyElement:get_info()
    return {
        type = self.trigger_type,
        values = self.trigger_values,
        count = #self.trigger_values,
    }
end
-- Parse trigger data to determine type and values
function LazyElement:_parse_trigger_data()
    local on = self.trigger_data

    -- Check for events
    local events = on.events or on.event
    if events then
        self.trigger_type = "events"
        self.trigger_values = type(events) == "table" and events or { events }
        return
    end

    -- Check for filetypes
    local fts = on.fts or on.ft
    if fts then
        self.trigger_type = "fts"
        self.trigger_values = type(fts) == "table" and fts or { fts }
        return
    end

    -- Check for commands
    local cmds = on.cmds or on.cmd
    if cmds then
        self.trigger_type = "cmds"
        self.trigger_values = type(cmds) == "table" and cmds or { cmds }
        return
    end

    -- Check for keys
    local keys = on.keys
    if keys then
        self.trigger_type = "keys"
        local key_list = type(keys) == "table" and keys or { keys }

        -- Extract key strings from key specs
        self.trigger_values = {}
        for _, key in ipairs(key_list) do
            if type(key) == "string" then
                table.insert(self.trigger_values, key)
            elseif type(key) == "table" then
                local lhs = key[1] or key.lhs or ""
                if lhs ~= "" then
                    table.insert(self.trigger_values, lhs)
                end
            end
        end
        return
    end

    -- Check for "after" dependencies
    local after = on.after
    if after then
        self.trigger_type = "after"
        self.trigger_values = type(after) == "table" and after or { after }
        return
    end

    -- Check for "before" dependencies
    local before = on.before
    if before then
        self.trigger_type = "before"
        self.trigger_values = type(before) == "table" and before or { before }
        return
    end

    -- No triggers found
    self.trigger_type = "none"
    self.trigger_values = {}
end

local StatusElement = setmetatable({}, { __index = Element })
StatusElement.__index = StatusElement

function StatusElement.new(name, initial_value, type)
    local self = Element.new(name, initial_value or "idle")

    self.type = type or "icon"
    self.status_map = {
        idle = "○",
        created = "◌",
        installing = "◌",
        installed = "◌",
        configuring = "◌",
        disabled = "◌",
        lazy = "◌",
        loading = "◌",
        pending = "◌",
        waiting = "◌",
        configured = "●",
        loaded = "●",
        ready = "●",
        failed = "✗",
    }
    return setmetatable(self, StatusElement)
end

function StatusElement:render()
    if not self.visible then
        return ""
    end
    return self.type == "icon" and self.status_map[self.value]
        or self.type == "icon_text" and self.status_map[self.value] .. " " .. self.value
        or self.value
end

function StatusElement:set_status_map(map)
    self.status_map = map
    self.dirty = true
end

-- ============================================================================

local StageElement = setmetatable({}, { __index = Element })
StageElement.__index = StageElement

function StageElement.new(name, initial_value, type, icons)
    local self = Element.new(name, initial_value)

    self.type = type or "icon_text"
    -- icons is now passed as parameter
    icons = icons or {}

    self.stage_map = {
        now = (icons.stage and icons.stage.now),
        later = (icons.stage and icons.stage.later),
        lazy = (icons.stage and icons.stage.lazy),
        disabled = (icons.stage and icons.stage.disabled),
    }
    return setmetatable(self, StageElement)
end

function StageElement:render()
    if not self.visible then
        return ""
    end
    if self.type == "icon" then
        return self.stage_map[self.value]
    elseif self.type == "text" then
        return self.value:upper()
    end
    return self.stage_map[self.value] .. " " .. self.value:upper()
end

function StageElement:set_stage_map(map)
    self.stage_map = map
    self.dirty = true
end

-- ============================================================================

local DurationElement = setmetatable({}, { __index = Element })
DurationElement.__index = DurationElement

function DurationElement.new(name, initial_value)
    local self = Element.new(name, initial_value)
    self.precision = 2
    self.unit = "ms"
    return setmetatable(self, DurationElement)
end

function DurationElement:render()
    if not self.visible then
        return ""
    end
    if not self.value or self.value == "" then
        return ""
    end
    return string.format("%." .. self.precision .. "f%s", self.value, self.unit)
end

function DurationElement:set_precision(precision)
    self.precision = precision
    self.dirty = true
end

-- ============================================================================
-- sage/ui/core/list_element.lua
-- A robust ListElement for dashboard/core UI usage.
-- This module provides a safe API for storing, updating and rendering lists of strings.
-- It intentionally does NOT perform any buffer/window rendering — that belongs to the UI layer.

local ListElement = {}
ListElement.__index = ListElement

-- Create a new ListElement
-- name : string identifier
-- values: table or nil (initial values)
-- opts: table, optional (allowed keys: separator, button_icon, transform)
function ListElement.new(name, values, opts)
    opts = opts or {}

    local self = setmetatable({}, ListElement)
    self.name = name or "list"
    -- normalize values to a flat array of strings
    self.values = {}
    if values then
        if type(values) == "table" then
            for _, v in ipairs(values) do
                table.insert(self.values, tostring(v))
            end
        else
            table.insert(self.values, tostring(values))
        end
    end

    self.separator = opts.separator or ", "
    self.button_icon = opts.button_icon or " " -- default icon for button render
    -- optional transform function applied to each value when rendering
    self.transform = opts.transform -- function(val) -> string

    return self
end

-- Return copy of values (to avoid external mutation)
function ListElement:get_values()
    local out = {}
    for i, v in ipairs(self.values) do
        out[i] = v
    end
    return out
end

-- Replace entire values array (defensive)
function ListElement:set_values(new_values)
    self.values = {}
    if not new_values then
        return
    end
    if type(new_values) == "table" then
        for _, v in ipairs(new_values) do
            table.insert(self.values, tostring(v))
        end
    else
        table.insert(self.values, tostring(new_values))
    end
end

-- Add a single value (idempotent optional)
-- opts: { unique = true } -> avoid duplicate entries
function ListElement:add(value, opts)
    if value == nil then
        return
    end
    opts = opts or {}
    local s = tostring(value)
    if opts.unique then
        for _, v in ipairs(self.values) do
            if v == s then
                return
            end
        end
    end
    table.insert(self.values, s)
end

-- Remove a value (first match)
function ListElement:remove(value)
    if value == nil then
        return
    end
    local s = tostring(value)
    for i, v in ipairs(self.values) do
        if v == s then
            table.remove(self.values, i)
            return true
        end
    end
    return false
end

-- Check membership
function ListElement:has(value)
    if value == nil then
        return false
    end
    local s = tostring(value)
    for _, v in ipairs(self.values) do
        if v == s then
            return true
        end
    end
    return false
end

function ListElement:render()
    if not self.values or #self.values == 0 then
        return ""
    end

    local rendered = {}
    for _, dep in ipairs(self.values) do
        local icon = " " -- or from your icons table
        table.insert(rendered, string.format("[%s %s]", icon, dep))
    end
    return rendered
end

-- Render as button-like segments (returns table of strings)
-- Each element => "[ ICON name ]" (no coloring / highlight)
-- Use UI layer to add highlights/extmarks for click behavior.
function ListElement:render_buttons()
    local out = {}
    for _, d in ipairs(self.values or {}) do
        local icon = " " -- or from your icons table
        table.insert(out, string.format("[%s%s]", icon, d))
    end
    return out
end
-- Convenience: render buttons concatenated into one string (space-separated)

function ListElement:render_buttons_joined(opts)
    local buttons = self:render_buttons(opts)
    if #buttons == 0 then
        return ""
    end
    return table.concat(buttons, " ")
end

-- Return count
function ListElement:count()
    return #self.values
end

-- Clear all entries
function ListElement:clear()
    self.values = {}
end

-- String metamethod (fallback)
function ListElement:__tostring()
    return self:render_join()
end

-- ============================================================================

local IconElement = setmetatable({}, { __index = Element })
IconElement.__index = IconElement

function IconElement.new(name, icon_set)
    local self = Element.new(name, nil)
    self.icon_set = icon_set or {}
    self.icon_key = nil
    return setmetatable(self, IconElement)
end

function IconElement:set_icon(key)
    if self.icon_key ~= key then
        self.icon_key = key
        self.value = self.icon_set[key]
        self.dirty = true
        return true
    end
    return false
end

function IconElement:render()
    if not self.visible then
        return ""
    end
    return self.value or ""
end

local TaskProgressElement = {}
TaskProgressElement.__index = TaskProgressElement

function TaskProgressElement.new(key, progress_data)
    local self = setmetatable({}, TaskProgressElement)
    self.key = key
    self.value = progress_data
        or {
            total = 0,
            completed = 0,
            required_completed = 0,
            required_total = 0,
            percentage = 0,
        }
    return self
end

function TaskProgressElement:update(progress_data)
    if progress_data then
        self.value = progress_data
    end
end

function TaskProgressElement:render()
    local p = self.value
    if p.total == 0 then
        return ""
    end
    if p.completed == p.total then
        return "[✓]"
    end
    if p.required_completed < p.required_total then
        return string.format("[%d/%d*]", p.required_completed, p.required_total)
    end
    return string.format("[%d/%d]", p.completed, p.total)
end

return {
    Element = Element,
    TextElement = TextElement,
    NameElement = NameElement,
    BooleanElement = BooleanElement,
    StatusElement = StatusElement,
    StageElement = StageElement,
    DurationElement = DurationElement,
    ListElement = ListElement,
    IconElement = IconElement,
    LazyElement = LazyElement,
    TaskProgressElement = TaskProgressElement,
}
