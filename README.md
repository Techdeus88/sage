# Sage

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
