-- tests/minimal_init.lua
vim.env.LAZY_STDPATH = "/tmp/runner-test"
local root = vim.env.LAZY_STDPATH

-- Bootstrap lazy.nvim
local lazypath = root .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
    vim.fn.system({ "git", "clone", "--filter=blob:none",
        "https://github.com/folke/lazy.nvim.git", lazypath })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
    { "nvim-lua/plenary.nvim" },
    { dir = vim.fn.getcwd() }, -- loads your plugin from the repo root
}, {
    root = root .. "/plugins",
    lockfile = root .. "/lazy-lock.json",
})

-- Point runtimepath at your plugin's lua/ dir
vim.opt.rtp:prepend(vim.fn.getcwd())
