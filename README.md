#---- ============================================================================
-- STATUSLINE - FIXED & COMPLETE
-- Drop-in replacement for your statusline.lua
-- ============================================================================

local M = {}

local state = {
  cache = {
    diagnostics = "",
    branch = "",
    col_scrollbar = {},
  },
  info = {
    mode = "short",
  },
  -- Track last update time per cache key
  last_update = {},
  -- Debounce intervals per key (ms)
  debounce_ms = {
    diagnostics = 100,
    branch = 300,
    col_scrollbar = 50,
  },
}

-- ============================================================================
-- DEBOUNCE & CACHE SYSTEM
-- ============================================================================

local function should_update_cache(key)
  local now = vim.uv.now()
  local last_update = state.last_update[key] or 0
  local debounce = state.debounce_ms[key] or 100
  return (now - last_update) >= debounce
end

local function update_cache(key, value)
  state.cache[key] = value
  state.last_update[key] = vim.uv.now()
end

local function get_cached_value(key)
  return state.cache[key]
end

-- ============================================================================
-- STATE HELPERS
-- ============================================================================

state.get = function(key)
  local keys = vim.split(key, ".", { plain = true })
  local value = state
  for _, k in ipairs(keys) do
    if value[k] then
      value = value[k]
    else
      return nil
    end
  end
  return value
end

state.set = function(key, value)
  local keys = vim.split(key, ".", { plain = true })
  local target = state
  for i = 1, #keys - 1 do
    local k = keys[i]
    if not target[k] then target[k] = {} end
    target = target[k]
  end
  target[keys[#keys]] = value
end

state.clear_cache = function()
  state.cache = {
    diagnostics = "",
    branch = "",
    col_scrollbar = {},
  }
  state.last_update = {}
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

local function buffer_not_code_buffer()
  local curr_ft = vim.bo.filetype
  local disabled_filetypes = {
    "snacks_terminal",
    "help",
    "man",
    "sage",
    "oil",
    "minifiles",
  }
  return vim.tbl_contains(disabled_filetypes, curr_ft) or vim.fn.mode() == "t"
end

local function buffer_is_empty()
  local lines = vim.api.nvim_buf_line_count(0)
  return lines == 0
end

local function _spacer(n)
  return string.rep(" ", n)
end

local function _align()
  return "%="
end

local function is_truncated(trunc_width)
  local cur_width = vim.o.laststatus == 3 and vim.o.columns
    or vim.api.nvim_win_get_width(0)
  return cur_width < (trunc_width or -1)
end

-- ============================================================================
-- MODE DISPLAY
-- ============================================================================

local CTRL_S = vim.api.nvim_replace_termcodes("<C-S>", true, true, true)
local CTRL_V = vim.api.nvim_replace_termcodes("<C-V>", true, true, true)

local modes = setmetatable({
  ["n"] = { long = "NORMAL", short = "N", hl = "StatuslineModeNormal" },
  ["v"] = { long = "VISUAL", short = "V", hl = "StatuslineModeVisual" },
  ["V"] = { long = "V-LINE", short = "V-L", hl = "StatuslineModeVisual" },
  [CTRL_V] = { long = "V-BLOCK", short = "V-B", hl = "StatuslineModeVisual" },
  ["s"] = { long = "SELECT", short = "S", hl = "StatuslineModeVisual" },
  ["S"] = { long = "S-LINE", short = "S-L", hl = "StatuslineModeVisual" },
  [CTRL_S] = { long = "S-BLOCK", short = "S-B", hl = "StatuslineModeVisual" },
  ["i"] = { long = "INSERT", short = "I", hl = "StatuslineModeInsert" },
  ["R"] = { long = "REPLACE", short = "R", hl = "StatuslineModeReplace" },
  ["c"] = { long = "COMMAND", short = "C", hl = "StatuslineModeCommand" },
  ["r"] = { long = "PROMPT", short = "P", hl = "StatuslineModeOther" },
  ["!"] = { long = "SHELL", short = "Sh", hl = "StatuslineModeOther" },
  ["t"] = { long = "TERMINAL", short = "T", hl = "StatuslineModeOther" },
}, {
  __index = function()
    return { long = "Unknown", short = "U", hl = "StatuslineModeOther" }
  end,
})

local function get_mode()
  local mode_info = modes[vim.fn.mode()]
  local mode = state.get("info.mode") == "short" and mode_info.short
    or mode_info.long
  return _G.tools.hl_str(mode_info.hl, _spacer(1) .. mode .. _spacer(1))
end

-- ============================================================================
-- DISPLAY COMPONENTS
-- ============================================================================

local function get_path()
  if buffer_not_code_buffer() then return "" end
  if is_truncated(100) then return _spacer(1) end
  local path = vim.fn.expand("%:~:.:h")
  local max_width = 30
  if path == "." or path == "" then
    return ""
  elseif #path > max_width then
    path = "…" .. string.sub(path, -max_width + 2)
  end
  return _G.tools.hl_str("StatuslineFilepath", path .. _spacer(1))
end

local function get_filename()
  if buffer_not_code_buffer() then return "" end
  local filename = vim.fn.expand("%:~:t")
  local buf = vim.api.nvim_get_current_buf()
  local icon, icon_hl, _ =
    require("mini.icons").get("filetype", vim.bo.filetype)
  local diagnostic_map = {
    [vim.diagnostic.severity.ERROR] = "DiagnosticError",
    [vim.diagnostic.severity.WARN] = "DiagnosticWarn",
    [vim.diagnostic.severity.INFO] = "DiagnosticInfo",
    [vim.diagnostic.severity.HINT] = "DiagnosticHint",
  }
  local diagnostics = vim.diagnostic.get(buf)
  local hl = #diagnostics > 0 and diagnostic_map[diagnostics[1].severity]
    or "StatuslineTextMain"

  if filename == "" then return _G.tools.hl_str(hl, "[No Name]") end
  return _G.tools.hl_str(icon_hl, icon .. _spacer(1))
    .. _G.tools.hl_str(hl, filename .. _spacer(1))
end

local function get_modification_status()
  local buf_modified = vim.bo.modified
  local buf_modifiable = vim.bo.modifiable
  local buf_readonly = vim.bo.readonly
  if buf_modified then
    return _G.tools.hl_str("DiagnosticWarn", "●" .. _spacer(2))
  elseif buf_modifiable == false or buf_readonly == true then
    return _G.tools.hl_str("DiagnosticError", "󰑇" .. _spacer(2))
  else
    return _spacer(2)
  end
end

local function get_lsp_status()
  if buffer_not_code_buffer() then return "" end
  local clients = vim.lsp.get_clients({ bufnr = 0 })
  if #clients > 0 and clients[1].initialized then
    return _G.tools.hl_str("DiagnosticWarn", " " .. _spacer(1))
  else
    return ""
  end
end

local function get_formatter_status()
  if buffer_not_code_buffer() then return "" end
  local conform = require("conform")
  local formatters = conform.list_formatters(0)
  if #formatters > 0 then
    return _G.tools.hl_str("Special", " " .. _spacer(1))
  else
    return ""
  end
end

local function get_copilot_status()
  if buffer_not_code_buffer() then return "" end
  local ok, status = pcall(function()
    return require("sidekick.status").get()
  end)
  if not ok or not status then return "" end
  local hl = status.kind == "Error" and "DiagnosticError"
    or status.busy and "DiagnosticWarn"
    or "Define"
  return _G.tools.hl_str(hl, " " .. _spacer(1))
end

-- ============================================================================
-- DIAGNOSTICS - WITH DEBOUNCE
-- ============================================================================

local function get_diagnostics()
  if buffer_not_code_buffer() then return "" end

  if not should_update_cache("diagnostics") then
    return get_cached_value("diagnostics")
  end

  local severities = {
    { name = "E", hl = "DiagnosticError" },
    { name = "W", hl = "DiagnosticWarn" },
    { name = "I", hl = "DiagnosticInfo" },
    { name = "H", hl = "DiagnosticHint" },
  }

  local result = ""
  local diag_count = 0

  for _, severity in ipairs(severities) do
    local count = #vim.diagnostic.get(
      0,
      { severity = vim.diagnostic.severity[severity.name] }
    )
    if count > 0 then
      result = result
        .. _G.tools.hl_str(severity.hl, " " .. count .. _spacer(1))
      diag_count = 1
    end
  end

  local ret = result .. _spacer(diag_count)
  update_cache("diagnostics", ret)
  return ret
end

-- ============================================================================
-- GIT BRANCH - WITH DEBOUNCE
-- ============================================================================

local function get_branch()
  if buffer_not_code_buffer() then return "" end

  if not should_update_cache("branch") then
    return get_cached_value("branch")
  end

  local result = vim
    .system({ "git", "rev-parse", "--abbrev-ref", "HEAD" }, { text = true })
    :wait()

  local branch_name
  if result.code == 0 then
    branch_name = result.stdout:gsub("\n$", "")
  else
    branch_name = "!git_repo"
  end

  local formatted = _G.tools.hl_str("StatuslineFilepath", branch_name .. _spacer(1))
  update_cache("branch", formatted)
  return formatted
end

-- ============================================================================
-- RECORDING
-- ============================================================================

local function get_recording()
  local recording = vim.fn.reg_recording()
  if recording == "" then return "" end
  return _G.tools.hl_str("StatuslineTextAccent", "󰑋 ")
    .. _G.tools.hl_str(
      "DiagnosticError",
      recording .. " recording" .. _spacer(2)
    )
end

-- ============================================================================
-- SCROLLBARS
-- ============================================================================

local function get_row_scrollbar()
  if is_truncated(75) or buffer_not_code_buffer() or buffer_is_empty() then
    return ""
  end

  local sbar_chars = {
    "▔",
    "🮂",
    "🬂",
    "🮃",
    "▀",
    "▄",
    "▃",
    "🬭",
    "▂",
    "▁",
  }

  local cur_line = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_line_count(0)
  local i = math.floor((cur_line - 1) / lines * #sbar_chars) + 1
  local sbar = string.rep(sbar_chars[i], 2)

  return _G.tools.hl_str("DiagnosticError", sbar .. _spacer(1))
end

local function get_col_scrollbar()
  if is_truncated(75) or buffer_not_code_buffer() or buffer_is_empty() then
    return ""
  end

  local sbar_chars = {
    "▔",
    "🮂",
    "🬂",
    "🮃",
    "▀",
    "▄",
    "▃",
    "🬭",
    "▂",
    "▁",
  }

  local total_cols_in_line = vim.fn.col("$") - 1
  local cur_col = vim.api.nvim_win_get_cursor(0)[2]

  if total_cols_in_line == 0 then total_cols_in_line = 1 end
  local percentage = (cur_col / total_cols_in_line) * 100

  local char_index = math.floor((percentage / 100) * (#sbar_chars - 1)) + 1
  char_index = math.max(1, math.min(char_index, #sbar_chars))

  local max_length = 10
  local final_index = math.min(max_length, char_index)
  local col_cache = get_cached_value("col_scrollbar")
  local spacing

  if col_cache[final_index] then
    spacing = col_cache[final_index]
  else
    spacing = max_length - final_index
    col_cache[final_index] = spacing
    update_cache("col_scrollbar", col_cache)
  end

  local sbar = string.format(
    "%s%s",
    string.rep("▂", final_index),
    string.rep(" ", spacing)
  )

  return _G.tools.hl_col_str("DiagnosticWarn", sbar .. _spacer(1))
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

M.setup = function()
  vim.opt.laststatus = 3
  vim.opt.showmode = false
end

M.load = function()
  local curr_ft = vim.bo.filetype
  local disabled_filetypes = {
    "dashboard",
    "sage",
    "sage-dashboard",
    "minifiles",
    "oil",
  }

  if vim.tbl_contains(disabled_filetypes, curr_ft) then return "" end

  return table.concat({
    get_col_scrollbar(),
    get_mode(),
    get_path(),
    get_filename(),
    get_modification_status(),
    get_lsp_status(),
    get_formatter_status(),
    get_copilot_status(),
    get_diagnostics(),
    _align(),
    get_recording(),
    _align(),
    get_branch(),
    get_row_scrollbar(),
  })
end

-- ============================================================================
-- SETUP
-- ============================================================================

vim.api.nvim_create_augroup("Statusline", { clear = true })
vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter" }, {
  group = "Statusline",
  pattern = "*",
  callback = function()
    vim.o.statusline = "%!v:lua.require'statusline'.load()"
  end,
})

return M- ============================================================================
-- STATUSLINE - FIXED & COMPLETE
-- Drop-in replacement for your statusline.lua
-- ============================================================================

local M = {}

local state = {
  cache = {
    diagnostics = "",
    branch = "",
    col_scrollbar = {},
  },
  info = {
    mode = "short",
  },
  -- Track last update time per cache key
  last_update = {},
  -- Debounce intervals per key (ms)
  debounce_ms = {
    diagnostics = 100,
    branch = 300,
    col_scrollbar = 50,
  },
}

-- ============================================================================
-- DEBOUNCE & CACHE SYSTEM
-- ============================================================================

local function should_update_cache(key)
  local now = vim.uv.now()
  local last_update = state.last_update[key] or 0
  local debounce = state.debounce_ms[key] or 100
  return (now - last_update) >= debounce
end

local function update_cache(key, value)
  state.cache[key] = value
  state.last_update[key] = vim.uv.now()
end

local function get_cached_value(key)
  return state.cache[key]
end

-- ============================================================================
-- STATE HELPERS
-- ============================================================================

state.get = function(key)
  local keys = vim.split(key, ".", { plain = true })
  local value = state
  for _, k in ipairs(keys) do
    if value[k] then
      value = value[k]
    else
      return nil
    end
  end
  return value
end

state.set = function(key, value)
  local keys = vim.split(key, ".", { plain = true })
  local target = state
  for i = 1, #keys - 1 do
    local k = keys[i]
    if not target[k] then target[k] = {} end
    target = target[k]
  end
  target[keys[#keys]] = value
end

state.clear_cache = function()
  state.cache = {
    diagnostics = "",
    branch = "",
    col_scrollbar = {},
  }
  state.last_update = {}
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

local function buffer_not_code_buffer()
  local curr_ft = vim.bo.filetype
  local disabled_filetypes = {
    "snacks_terminal",
    "help",
    "man",
    "sage",
    "oil",
    "minifiles",
  }
  return vim.tbl_contains(disabled_filetypes, curr_ft) or vim.fn.mode() == "t"
end

local function buffer_is_empty()
  local lines = vim.api.nvim_buf_line_count(0)
  return lines == 0
end

local function _spacer(n)
  return string.rep(" ", n)
end

local function _align()
  return "%="
end

local function is_truncated(trunc_width)
  local cur_width = vim.o.laststatus == 3 and vim.o.columns
    or vim.api.nvim_win_get_width(0)
  return cur_width < (trunc_width or -1)
end

-- ============================================================================
-- MODE DISPLAY
-- ============================================================================

local CTRL_S = vim.api.nvim_replace_termcodes("<C-S>", true, true, true)
local CTRL_V = vim.api.nvim_replace_termcodes("<C-V>", true, true, true)

local modes = setmetatable({
  ["n"] = { long = "NORMAL", short = "N", hl = "StatuslineModeNormal" },
  ["v"] = { long = "VISUAL", short = "V", hl = "StatuslineModeVisual" },
  ["V"] = { long = "V-LINE", short = "V-L", hl = "StatuslineModeVisual" },
  [CTRL_V] = { long = "V-BLOCK", short = "V-B", hl = "StatuslineModeVisual" },
  ["s"] = { long = "SELECT", short = "S", hl = "StatuslineModeVisual" },
  ["S"] = { long = "S-LINE", short = "S-L", hl = "StatuslineModeVisual" },
  [CTRL_S] = { long = "S-BLOCK", short = "S-B", hl = "StatuslineModeVisual" },
  ["i"] = { long = "INSERT", short = "I", hl = "StatuslineModeInsert" },
  ["R"] = { long = "REPLACE", short = "R", hl = "StatuslineModeReplace" },
  ["c"] = { long = "COMMAND", short = "C", hl = "StatuslineModeCommand" },
  ["r"] = { long = "PROMPT", short = "P", hl = "StatuslineModeOther" },
  ["!"] = { long = "SHELL", short = "Sh", hl = "StatuslineModeOther" },
  ["t"] = { long = "TERMINAL", short = "T", hl = "StatuslineModeOther" },
}, {
  __index = function()
    return { long = "Unknown", short = "U", hl = "StatuslineModeOther" }
  end,
})

local function get_mode()
  local mode_info = modes[vim.fn.mode()]
  local mode = state.get("info.mode") == "short" and mode_info.short
    or mode_info.long
  return _G.tools.hl_str(mode_info.hl, _spacer(1) .. mode .. _spacer(1))
end

-- ============================================================================
-- DISPLAY COMPONENTS
-- ============================================================================

local function get_path()
  if buffer_not_code_buffer() then return "" end
  if is_truncated(100) then return _spacer(1) end
  local path = vim.fn.expand("%:~:.:h")
  local max_width = 30
  if path == "." or path == "" then
    return ""
  elseif #path > max_width then
    path = "…" .. string.sub(path, -max_width + 2)
  end
  return _G.tools.hl_str("StatuslineFilepath", path .. _spacer(1))
end

local function get_filename()
  if buffer_not_code_buffer() then return "" end
  local filename = vim.fn.expand("%:~:t")
  local buf = vim.api.nvim_get_current_buf()
  local icon, icon_hl, _ =
    require("mini.icons").get("filetype", vim.bo.filetype)
  local diagnostic_map = {
    [vim.diagnostic.severity.ERROR] = "DiagnosticError",
    [vim.diagnostic.severity.WARN] = "DiagnosticWarn",
    [vim.diagnostic.severity.INFO] = "DiagnosticInfo",
    [vim.diagnostic.severity.HINT] = "DiagnosticHint",
  }
  local diagnostics = vim.diagnostic.get(buf)
  local hl = #diagnostics > 0 and diagnostic_map[diagnostics[1].severity]
    or "StatuslineTextMain"

  if filename == "" then return _G.tools.hl_str(hl, "[No Name]") end
  return _G.tools.hl_str(icon_hl, icon .. _spacer(1))
    .. _G.tools.hl_str(hl, filename .. _spacer(1))
end

local function get_modification_status()
  local buf_modified = vim.bo.modified
  local buf_modifiable = vim.bo.modifiable
  local buf_readonly = vim.bo.readonly
  if buf_modified then
    return _G.tools.hl_str("DiagnosticWarn", "●" .. _spacer(2))
  elseif buf_modifiable == false or buf_readonly == true then
    return _G.tools.hl_str("DiagnosticError", "󰑇" .. _spacer(2))
  else
    return _spacer(2)
  end
end

local function get_lsp_status()
  if buffer_not_code_buffer() then return "" end
  local clients = vim.lsp.get_clients({ bufnr = 0 })
  if #clients > 0 and clients[1].initialized then
    return _G.tools.hl_str("DiagnosticWarn", " " .. _spacer(1))
  else
    return ""
  end
end

local function get_formatter_status()
  if buffer_not_code_buffer() then return "" end
  local conform = require("conform")
  local formatters = conform.list_formatters(0)
  if #formatters > 0 then
    return _G.tools.hl_str("Special", " " .. _spacer(1))
  else
    return ""
  end
end

local function get_copilot_status()
  if buffer_not_code_buffer() then return "" end
  local ok, status = pcall(function()
    return require("sidekick.status").get()
  end)
  if not ok or not status then return "" end
  local hl = status.kind == "Error" and "DiagnosticError"
    or status.busy and "DiagnosticWarn"
    or "Define"
  return _G.tools.hl_str(hl, " " .. _spacer(1))
end

-- ============================================================================
-- DIAGNOSTICS - WITH DEBOUNCE
-- ============================================================================

local function get_diagnostics()
  if buffer_not_code_buffer() then return "" end

  if not should_update_cache("diagnostics") then
    return get_cached_value("diagnostics")
  end

  local severities = {
    { name = "E", hl = "DiagnosticError" },
    { name = "W", hl = "DiagnosticWarn" },
    { name = "I", hl = "DiagnosticInfo" },
    { name = "H", hl = "DiagnosticHint" },
  }

  local result = ""
  local diag_count = 0

  for _, severity in ipairs(severities) do
    local count = #vim.diagnostic.get(
      0,
      { severity = vim.diagnostic.severity[severity.name] }
    )
    if count > 0 then
      result = result
        .. _G.tools.hl_str(severity.hl, " " .. count .. _spacer(1))
      diag_count = 1
    end
  end

  local ret = result .. _spacer(diag_count)
  update_cache("diagnostics", ret)
  return ret
end

-- ============================================================================
-- GIT BRANCH - WITH DEBOUNCE
-- ============================================================================

local function get_branch()
  if buffer_not_code_buffer() then return "" end

  if not should_update_cache("branch") then
    return get_cached_value("branch")
  end

  local result = vim
    .system({ "git", "rev-parse", "--abbrev-ref", "HEAD" }, { text = true })
    :wait()

  local branch_name
  if result.code == 0 then
    branch_name = result.stdout:gsub("\n$", "")
  else
    branch_name = "!git_repo"
  end

  local formatted = _G.tools.hl_str("StatuslineFilepath", branch_name .. _spacer(1))
  update_cache("branch", formatted)
  return formatted
end

-- ============================================================================
-- RECORDING
-- ============================================================================

local function get_recording()
  local recording = vim.fn.reg_recording()
  if recording == "" then return "" end
  return _G.tools.hl_str("StatuslineTextAccent", "󰑋 ")
    .. _G.tools.hl_str(
      "DiagnosticError",
      recording .. " recording" .. _spacer(2)
    )
end

-- ============================================================================
-- SCROLLBARS
-- ============================================================================

local function get_row_scrollbar()
  if is_truncated(75) or buffer_not_code_buffer() or buffer_is_empty() then
    return ""
  end

  local sbar_chars = {
    "▔",
    "🮂",
    "🬂",
    "🮃",
    "▀",
    "▄",
    "▃",
    "🬭",
    "▂",
    "▁",
  }

  local cur_line = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_line_count(0)
  local i = math.floor((cur_line - 1) / lines * #sbar_chars) + 1
  local sbar = string.rep(sbar_chars[i], 2)

  return _G.tools.hl_str("DiagnosticError", sbar .. _spacer(1))
end

local function get_col_scrollbar()
  if is_truncated(75) or buffer_not_code_buffer() or buffer_is_empty() then
    return ""
  end

  local sbar_chars = {
    "▔",
    "🮂",
    "🬂",
    "🮃",
    "▀",
    "▄",
    "▃",
    "🬭",
    "▂",
    "▁",
  }

  local total_cols_in_line = vim.fn.col("$") - 1
  local cur_col = vim.api.nvim_win_get_cursor(0)[2]

  if total_cols_in_line == 0 then total_cols_in_line = 1 end
  local percentage = (cur_col / total_cols_in_line) * 100

  local char_index = math.floor((percentage / 100) * (#sbar_chars - 1)) + 1
  char_index = math.max(1, math.min(char_index, #sbar_chars))

  local max_length = 10
  local final_index = math.min(max_length, char_index)
  local col_cache = get_cached_value("col_scrollbar")
  local spacing

  if col_cache[final_index] then
    spacing = col_cache[final_index]
  else
    spacing = max_length - final_index
    col_cache[final_index] = spacing
    update_cache("col_scrollbar", col_cache)
  end

  local sbar = string.format(
    "%s%s",
    string.rep("▂", final_index),
    string.rep(" ", spacing)
  )

  return _G.tools.hl_col_str("DiagnosticWarn", sbar .. _spacer(1))
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

M.setup = function()
  vim.opt.laststatus = 3
  vim.opt.showmode = false
end

M.load = function()
  local curr_ft = vim.bo.filetype
  local disabled_filetypes = {
    "dashboard",
    "sage",
    "sage-dashboard",
    "minifiles",
    "oil",
  }

  if vim.tbl_contains(disabled_filetypes, curr_ft) then return "" end

  return table.concat({
    get_col_scrollbar(),
    get_mode(),
    get_path(),
    get_filename(),
    get_modification_status(),
    get_lsp_status(),
    get_formatter_status(),
    get_copilot_status(),
    get_diagnostics(),
    _align(),
    get_recording(),
    _align(),
    get_branch(),
    get_row_scrollbar(),
  })
end

-- ============================================================================
-- SETUP
-- ============================================================================

vim.api.nvim_create_augroup("Statusline", { clear = true })
vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter" }, {
  group = "Statusline",
  pattern = "*",
  callback = function()
    vim.o.statusline = "%!v:lua.require'statusline'.load()"
  end,
})

return M- ============================================================================
-- STATUSLINE - FIXED & COMPLETE
-- Drop-in replacement for your statusline.lua
-- ============================================================================

local M = {}

local state = {
  cache = {
    diagnostics = "",
    branch = "",
    col_scrollbar = {},
  },
  info = {
    mode = "short",
  },
  -- Track last update time per cache key
  last_update = {},
  -- Debounce intervals per key (ms)
  debounce_ms = {
    diagnostics = 100,
    branch = 300,
    col_scrollbar = 50,
  },
}

-- ============================================================================
-- DEBOUNCE & CACHE SYSTEM
-- ============================================================================

local function should_update_cache(key)
  local now = vim.uv.now()
  local last_update = state.last_update[key] or 0
  local debounce = state.debounce_ms[key] or 100
  return (now - last_update) >= debounce
end

local function update_cache(key, value)
  state.cache[key] = value
  state.last_update[key] = vim.uv.now()
end

local function get_cached_value(key)
  return state.cache[key]
end

-- ============================================================================
-- STATE HELPERS
-- ============================================================================

state.get = function(key)
  local keys = vim.split(key, ".", { plain = true })
  local value = state
  for _, k in ipairs(keys) do
    if value[k] then
      value = value[k]
    else
      return nil
    end
  end
  return value
end

state.set = function(key, value)
  local keys = vim.split(key, ".", { plain = true })
  local target = state
  for i = 1, #keys - 1 do
    local k = keys[i]
    if not target[k] then target[k] = {} end
    target = target[k]
  end
  target[keys[#keys]] = value
end

state.clear_cache = function()
  state.cache = {
    diagnostics = "",
    branch = "",
    col_scrollbar = {},
  }
  state.last_update = {}
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

local function buffer_not_code_buffer()
  local curr_ft = vim.bo.filetype
  local disabled_filetypes = {
    "snacks_terminal",
    "help",
    "man",
    "sage",
    "oil",
    "minifiles",
  }
  return vim.tbl_contains(disabled_filetypes, curr_ft) or vim.fn.mode() == "t"
end

local function buffer_is_empty()
  local lines = vim.api.nvim_buf_line_count(0)
  return lines == 0
end

local function _spacer(n)
  return string.rep(" ", n)
end

local function _align()
  return "%="
end

local function is_truncated(trunc_width)
  local cur_width = vim.o.laststatus == 3 and vim.o.columns
    or vim.api.nvim_win_get_width(0)
  return cur_width < (trunc_width or -1)
end

-- ============================================================================
-- MODE DISPLAY
-- ============================================================================

local CTRL_S = vim.api.nvim_replace_termcodes("<C-S>", true, true, true)
local CTRL_V = vim.api.nvim_replace_termcodes("<C-V>", true, true, true)

local modes = setmetatable({
  ["n"] = { long = "NORMAL", short = "N", hl = "StatuslineModeNormal" },
  ["v"] = { long = "VISUAL", short = "V", hl = "StatuslineModeVisual" },
  ["V"] = { long = "V-LINE", short = "V-L", hl = "StatuslineModeVisual" },
  [CTRL_V] = { long = "V-BLOCK", short = "V-B", hl = "StatuslineModeVisual" },
  ["s"] = { long = "SELECT", short = "S", hl = "StatuslineModeVisual" },
  ["S"] = { long = "S-LINE", short = "S-L", hl = "StatuslineModeVisual" },
  [CTRL_S] = { long = "S-BLOCK", short = "S-B", hl = "StatuslineModeVisual" },
  ["i"] = { long = "INSERT", short = "I", hl = "StatuslineModeInsert" },
  ["R"] = { long = "REPLACE", short = "R", hl = "StatuslineModeReplace" },
  ["c"] = { long = "COMMAND", short = "C", hl = "StatuslineModeCommand" },
  ["r"] = { long = "PROMPT", short = "P", hl = "StatuslineModeOther" },
  ["!"] = { long = "SHELL", short = "Sh", hl = "StatuslineModeOther" },
  ["t"] = { long = "TERMINAL", short = "T", hl = "StatuslineModeOther" },
}, {
  __index = function()
    return { long = "Unknown", short = "U", hl = "StatuslineModeOther" }
  end,
})

local function get_mode()
  local mode_info = modes[vim.fn.mode()]
  local mode = state.get("info.mode") == "short" and mode_info.short
    or mode_info.long
  return _G.tools.hl_str(mode_info.hl, _spacer(1) .. mode .. _spacer(1))
end

-- ============================================================================
-- DISPLAY COMPONENTS
-- ============================================================================

local function get_path()
  if buffer_not_code_buffer() then return "" end
  if is_truncated(100) then return _spacer(1) end
  local path = vim.fn.expand("%:~:.:h")
  local max_width = 30
  if path == "." or path == "" then
    return ""
  elseif #path > max_width then
    path = "…" .. string.sub(path, -max_width + 2)
  end
  return _G.tools.hl_str("StatuslineFilepath", path .. _spacer(1))
end

local function get_filename()
  if buffer_not_code_buffer() then return "" end
  local filename = vim.fn.expand("%:~:t")
  local buf = vim.api.nvim_get_current_buf()
  local icon, icon_hl, _ =
    require("mini.icons").get("filetype", vim.bo.filetype)
  local diagnostic_map = {
    [vim.diagnostic.severity.ERROR] = "DiagnosticError",
    [vim.diagnostic.severity.WARN] = "DiagnosticWarn",
    [vim.diagnostic.severity.INFO] = "DiagnosticInfo",
    [vim.diagnostic.severity.HINT] = "DiagnosticHint",
  }
  local diagnostics = vim.diagnostic.get(buf)
  local hl = #diagnostics > 0 and diagnostic_map[diagnostics[1].severity]
    or "StatuslineTextMain"

  if filename == "" then return _G.tools.hl_str(hl, "[No Name]") end
  return _G.tools.hl_str(icon_hl, icon .. _spacer(1))
    .. _G.tools.hl_str(hl, filename .. _spacer(1))
end

local function get_modification_status()
  local buf_modified = vim.bo.modified
  local buf_modifiable = vim.bo.modifiable
  local buf_readonly = vim.bo.readonly
  if buf_modified then
    return _G.tools.hl_str("DiagnosticWarn", "●" .. _spacer(2))
  elseif buf_modifiable == false or buf_readonly == true then
    return _G.tools.hl_str("DiagnosticError", "󰑇" .. _spacer(2))
  else
    return _spacer(2)
  end
end

local function get_lsp_status()
  if buffer_not_code_buffer() then return "" end
  local clients = vim.lsp.get_clients({ bufnr = 0 })
  if #clients > 0 and clients[1].initialized then
    return _G.tools.hl_str("DiagnosticWarn", " " .. _spacer(1))
  else
    return ""
  end
end

local function get_formatter_status()
  if buffer_not_code_buffer() then return "" end
  local conform = require("conform")
  local formatters = conform.list_formatters(0)
  if #formatters > 0 then
    return _G.tools.hl_str("Special", " " .. _spacer(1))
  else
    return ""
  end
end

local function get_copilot_status()
  if buffer_not_code_buffer() then return "" end
  local ok, status = pcall(function()
    return require("sidekick.status").get()
  end)
  if not ok or not status then return "" end
  local hl = status.kind == "Error" and "DiagnosticError"
    or status.busy and "DiagnosticWarn"
    or "Define"
  return _G.tools.hl_str(hl, " " .. _spacer(1))
end

-- ============================================================================
-- DIAGNOSTICS - WITH DEBOUNCE
-- ============================================================================

local function get_diagnostics()
  if buffer_not_code_buffer() then return "" end

  if not should_update_cache("diagnostics") then
    return get_cached_value("diagnostics")
  end

  local severities = {
    { name = "E", hl = "DiagnosticError" },
    { name = "W", hl = "DiagnosticWarn" },
    { name = "I", hl = "DiagnosticInfo" },
    { name = "H", hl = "DiagnosticHint" },
  }

  local result = ""
  local diag_count = 0

  for _, severity in ipairs(severities) do
    local count = #vim.diagnostic.get(
      0,
      { severity = vim.diagnostic.severity[severity.name] }
    )
    if count > 0 then
      result = result
        .. _G.tools.hl_str(severity.hl, " " .. count .. _spacer(1))
      diag_count = 1
    end
  end

  local ret = result .. _spacer(diag_count)
  update_cache("diagnostics", ret)
  return ret
end

-- ============================================================================
-- GIT BRANCH - WITH DEBOUNCE
-- ============================================================================

local function get_branch()
  if buffer_not_code_buffer() then return "" end

  if not should_update_cache("branch") then
    return get_cached_value("branch")
  end

  local result = vim
    .system({ "git", "rev-parse", "--abbrev-ref", "HEAD" }, { text = true })
    :wait()

  local branch_name
  if result.code == 0 then
    branch_name = result.stdout:gsub("\n$", "")
  else
    branch_name = "!git_repo"
  end

  local formatted = _G.tools.hl_str("StatuslineFilepath", branch_name .. _spacer(1))
  update_cache("branch", formatted)
  return formatted
end

-- ============================================================================
-- RECORDING
-- ============================================================================

local function get_recording()
  local recording = vim.fn.reg_recording()
  if recording == "" then return "" end
  return _G.tools.hl_str("StatuslineTextAccent", "󰑋 ")
    .. _G.tools.hl_str(
      "DiagnosticError",
      recording .. " recording" .. _spacer(2)
    )
end

-- ============================================================================
-- SCROLLBARS
-- ============================================================================

local function get_row_scrollbar()
  if is_truncated(75) or buffer_not_code_buffer() or buffer_is_empty() then
    return ""
  end

  local sbar_chars = {
    "▔",
    "🮂",
    "🬂",
    "🮃",
    "▀",
    "▄",
    "▃",
    "🬭",
    "▂",
    "▁",
  }

  local cur_line = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_line_count(0)
  local i = math.floor((cur_line - 1) / lines * #sbar_chars) + 1
  local sbar = string.rep(sbar_chars[i], 2)

  return _G.tools.hl_str("DiagnosticError", sbar .. _spacer(1))
end

local function get_col_scrollbar()
  if is_truncated(75) or buffer_not_code_buffer() or buffer_is_empty() then
    return ""
  end

  local sbar_chars = {
    "▔",
    "🮂",
    "🬂",
    "🮃",
    "▀",
    "▄",
    "▃",
    "🬭",
    "▂",
    "▁",
  }

  local total_cols_in_line = vim.fn.col("$") - 1
  local cur_col = vim.api.nvim_win_get_cursor(0)[2]

  if total_cols_in_line == 0 then total_cols_in_line = 1 end
  local percentage = (cur_col / total_cols_in_line) * 100

  local char_index = math.floor((percentage / 100) * (#sbar_chars - 1)) + 1
  char_index = math.max(1, math.min(char_index, #sbar_chars))

  local max_length = 10
  local final_index = math.min(max_length, char_index)
  local col_cache = get_cached_value("col_scrollbar")
  local spacing

  if col_cache[final_index] then
    spacing = col_cache[final_index]
  else
    spacing = max_length - final_index
    col_cache[final_index] = spacing
    update_cache("col_scrollbar", col_cache)
  end

  local sbar = string.format(
    "%s%s",
    string.rep("▂", final_index),
    string.rep(" ", spacing)
  )

  return _G.tools.hl_col_str("DiagnosticWarn", sbar .. _spacer(1))
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

M.setup = function()
  vim.opt.laststatus = 3
  vim.opt.showmode = false
end

M.load = function()
  local curr_ft = vim.bo.filetype
  local disabled_filetypes = {
    "dashboard",
    "sage",
    "sage-dashboard",
    "minifiles",
    "oil",
  }

  if vim.tbl_contains(disabled_filetypes, curr_ft) then return "" end

  return table.concat({
    get_col_scrollbar(),
    get_mode(),
    get_path(),
    get_filename(),
    get_modification_status(),
    get_lsp_status(),
    get_formatter_status(),
    get_copilot_status(),
    get_diagnostics(),
    _align(),
    get_recording(),
    _align(),
    get_branch(),
    get_row_scrollbar(),
  })
end

-- ============================================================================
-- SETUP
-- ============================================================================

vim.api.nvim_create_augroup("Statusline", { clear = true })
vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter" }, {
  group = "Statusline",
  pattern = "*",
  callback = function()
    vim.o.statusline = "%!v:lua.require'statusline'.load()"
  end,
})

return M Sage

A modern package manager for Neovim written in Lua.

## ⚡️ Requirements

- Neovim >= **0.8.0** (needs to be built with **LuaJIT**)
- Git >= **2.19.0**

## 🛠️ Installation

### Bootstrap

Add the following to your `init.lua`:

```lua
-- Bootstrap sage
local sagepath = vim.fn.stdpath("data") .. "/sage"
if not (vim.uv or vim.loop).fs_stat(sagepath) then
  local sagerepo = "https://github.com/techdeus88/sage.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=main", sagerepo, sagepath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone sage:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(sagepath)

-- Setup sagilllle
require("sage").setup(opts)
```

## ✨ Features

- 📦 Manage all your Neovim packages with a powerful UI
- 🚀 Fast startup times with caching and bytecode compilation
- 💾 Efficient package installation via git
- 🔌 Flexible lazy-loading support
- ⚙️ Simple Lua-based configuration
- 🔒 Lockfile support for reproducible installs
- 🎨 Modern TUI interface

## 🔌 Basic Usage

Create a `sage.lua` file in your `~/.config/nvim/lua` directory:

```lua
return {
  -- Package specs go here
  "nvim-lua/plenary.nvim",
  { "folke/which-key.nvim", lazy = true },
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    event = "VeryLazy",
  },
}
```

Then load it in your `init.lua`:

```lua
require("sage").setup(opts)
```

## 🎯 Package Spec

### Basic Properties

- `[1]` (string): Short package url (e.g., `"username/package"`)
- `url` (string): Full git url for the package
- `name` (string): Custom name for the package
- `dir` (string): Local directory path for development
- `dev` (boolean): Use local dev version instead of git

### Loading

- `lazy` (boolean): Lazy-load this package (default: `false`)
- `event` (string|string[]): Load on event(s)
- `cmd` (string|string[]): Load on command(s)
- `ft` (string|string[]): Load on filetype(s)
- `keys` (string[]|table[]): Load on key binding(s)
- `dependencies` (string[]): Packages to load before this one

### Setup

- `init` (function): Run during startup
- `config` (function): Run when package loads
- `opts` (table|function): Configuration table passed to `config()`
- `build` (string|function|string[]): Build commands to run after install

### Versioning

- `branch` (string): Git branch to use
- `tag` (string): Git tag to use
- `commit` (string): Git commit hash to use
- `version` (string): Semver version range (e.g., `"^1.0.0"`, `"*"`)
- `pin` (boolean): Don't update this package

## 📝 Examples

### Simple package

```lua
"nvim-lua/plenary.nvim"
```

### Lazy-loaded plugin with options

```lua
{
  "folke/tokyonight.nvim",
  lazy = false,
  priority = 1000,
  opts = {
    style = "moon",
  },
}
```

### Load on command

```lua
{
  "nvim-tree/nvim-tree.lua",
  cmd = "NvimTreeToggle",
  opts = {},
}
```

### Load on filetype

```lua
{
  "nvim-neorg/neorg",
  ft = "norg",
  opts = {
    load = {
      ["core.defaults"] = {},
    },
  },
}
```

### With dependencies

```lua
{
  "hrsh7th/nvim-cmp",
  event = "InsertEnter",
  dependencies = {
    "hrsh7th/cmp-nvim-lsp",
    "hrsh7th/cmp-buffer",
  },
  opts = {},
}
```

### Local development package

```lua
{
  "my-plugin",
  dir = "~/projects/my-plugin",
  dev = true,
}
```

## 🚀 Commands

All operations can be performed from the UI or via command:

```vim
:Sage                " Show the UI
:Sage install        " Install missing packages
:Sage update         " Update all packages
:Sage sync           " Install, clean, and update
:Sage clean          " Remove unused packages
:Sage check          " Check for updates
:Sage log            " Show recent updates
:Sage build {pkg}    " Rebuild a package
```

## ⚙️ Configuration

Create a `sage.lua` configuration file:

```lua
require("sage").setup({
  -- root directory for packages
  root = vim.fn.stdpath("data") .. "/sage",

  -- configuration for git operations
  git = {
    -- timeout for git operations (seconds)
    timeout = 120,
    -- git url format
    url_format = "https://github.com/%s.git",
  },

  -- UI configuration
  ui = {
    size = { width = 0.8, height = 0.8 },
    border = "rounded",
  },

  -- performance settings
  performance = {
    cache = {
      enabled = true,
    },
  },
})
```

## 🔒 Lockfile

After updating packages, a `sage-lock.json` lockfile is generated. It's recommended to commit this file to version control to ensure reproducible installs across machines.

To restore packages to lockfile versions:

```vim
:Sage restore
```

## 🔄 Updating Sage

To update Sage itself:

```bash
cd ~/.local/share/nvim/sage
git pull origin main
```

## 📂 Project Structure

```
~/.local/share/nvim/sage/
├── lua/
│   └── sage/
│       ├── init.lua
│       ├── ui.lua
│       ├── manager.lua
│       └── ...
├── plugin/
│   └── sage.lua
└── README.md
```

## 🤝 Contributing

Contributions are welcome! Please fork this repository and submit a pull request.

## 📄 License

MIT License - see LICENSE file for details

## 🆘 Support

For issues, questions, or feature requests, please open an issue on GitHub.
