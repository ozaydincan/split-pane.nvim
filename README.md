# split-pane.nvim

A stateful, API-driven window pane manager for Neovim 0.10+.

split-pane.nvim uses native Lua APIs for window management, replacing Ex-command string parsing. It integrates with telescope.nvim and custom UI prompts.

## Features

* Native API implementation: Uses `vim.api.nvim_open_win` to avoid string escaping issues associated with legacy `:split` commands.
* Picker integration: Uses `telescope.nvim` and `vim.ui.select` to route search and grep results into designated split panes.
* Custom UI prompts: Provides floating windows for new file creation and unsaved changes warnings.
* Stateful management: Hide and restore panes without losing buffer state or cursor position.

## Installation

Using lazy.nvim:

```lua
{
  "ozaydincan/split-pane.nvim",
  dependencies = {
    "nvim-telescope/telescope.nvim",
    "nvim-lua/plenary.nvim",
  },
  keys = {
    { "<leader>fv", desc = "Pane: Find file (Vertical)" },
    { "<leader>fh", desc = "Pane: Find file (Horizontal)" },
    { "<leader>gv", desc = "Pane: Grep (Vertical)" },
    { "<leader>gh", desc = "Pane: Grep (Horizontal)" },
    { "<leader>nv", desc = "Pane: New file (Vertical)" },
    { "<leader>nh", desc = "Pane: New file (Horizontal)" },
    { "<leader>fw", desc = "Pane: Smart find file" },
    { "<leader>gw", desc = "Pane: Smart grep" },
    { "<leader>nw", desc = "Pane: Smart new file" },
    { "<leader>pt", desc = "Pane: Toggle current" },
    { "<leader>pk", desc = "Pane: Kill current" },
  },
  config = function()
    require("split-pane").setup()
  end,
}
```
## Configuration
The default configuration is provided below. Pass a table to the setup function to override these values.

```lua
require("split-pane").setup({
  behavior = {
    autosave = false,
  },
  window = {
    split_direction = "v",
  },
  keymaps = {
    find_vsplit = "<leader>fv",
    find_hsplit = "<leader>fh",
    grep_vsplit = "<leader>gv",
    grep_hsplit = "<leader>gh",
    new_vsplit  = "<leader>nv",
    new_hsplit  = "<leader>nh",
    smart_find  = "<leader>fw",
    smart_grep  = "<leader>gw",
    smart_new   = "<leader>nw",
    toggle_pane = "<leader>pt",
    kill_pane   = "<leader>pk",
  },
})

```

## Usage
### Commands

The following commands are registered automatically:

* :SpFind - Open Telescope file finder in a managed split.

* :SpGrep - Open Telescope live grep in a managed split.

* :SpNew - Create a new file via floating UI prompt.

* :SpToggle - Hide or restore the current managed pane.

* :SpKill - Close the pane and clean up its state.

## Split Behavior

* Explicit: Commands such as find_vsplit force a vertical or horizontal layout.

* Smart: Commands such as smart_find use the window.split_direction parameter defined in the configuration.

## Requirements
* Neovim 0.10+ 
* telescope.nvim
