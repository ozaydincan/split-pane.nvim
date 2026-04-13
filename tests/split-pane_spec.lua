-- tests/split-pane_spec.lua
local split_pane = require("split-pane")
local assert = require("luassert")

-- ── Helpers ──────────────────────────────────────────────────────────────────

--- Returns only standard windows, ignoring floats (like Plenary's test runner)
local function get_normal_wins()
	local normal_wins = {}
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if vim.api.nvim_win_get_config(win).relative == "" then
			table.insert(normal_wins, win)
		end
	end
	return normal_wins
end

--- Creates a scratch buffer and opens it in a split
---@return integer buf, integer win
local function create_test_pane()
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_set_option_value("buflisted", true, { buf = buf })

	local win = vim.api.nvim_open_win(buf, true, {
		split = "right",
		win = vim.api.nvim_get_current_win(),
	})

	return buf, win
end

--- Closes all standard windows except the very first one to reset state
local function close_all_splits()
	local wins = get_normal_wins()
	for i = 2, #wins do
		if vim.api.nvim_win_is_valid(wins[i]) then
			vim.api.nvim_win_close(wins[i], true)
		end
	end
end

-- ── Test Suite ───────────────────────────────────────────────────────────────

describe("split-pane.nvim:", function()
	before_each(function()
		split_pane.setup()
	end)

	after_each(function()
		close_all_splits()
	end)

	-- 1. Configuration & Setup Tests
	describe("setup", function()
		it("loads with sane default configurations", function()
			assert.are.same("v", split_pane.config.window.split_direction)
			assert.are.same(false, split_pane.config.behavior.autosave)
			assert.are.same("<leader>pt", split_pane.config.keymaps.toggle_pane)
		end)

		it("deep-merges user configurations correctly", function()
			split_pane.setup({
				behavior = { autosave = true },
				window = { split_direction = "h" },
			})

			assert.are.same(true, split_pane.config.behavior.autosave)
			assert.are.same("h", split_pane.config.window.split_direction)
			assert.are.same("<leader>pt", split_pane.config.keymaps.toggle_pane)
		end)

		it("registers all public user commands", function()
			local cmds = vim.api.nvim_get_commands({})
			assert.is_truthy(cmds["SpFind"])
			assert.is_truthy(cmds["SpGrep"])
			assert.is_truthy(cmds["SpNew"])
			assert.is_truthy(cmds["SpToggle"])
			assert.is_truthy(cmds["SpKill"])
		end)
	end)

	-- 2. State Management (Toggle & Kill)
	describe("state management", function()
		it("SpToggle hides the current window but keeps the buffer", function()
			local initial_win_count = #get_normal_wins()

			local buf, win = create_test_pane()
			assert.are.same(initial_win_count + 1, #get_normal_wins())

			split_pane.toggle()

			assert.is_false(vim.api.nvim_win_is_valid(win))
			assert.are.same(initial_win_count, #get_normal_wins())
			assert.is_true(vim.api.nvim_buf_is_valid(buf))
		end)

		it("SpToggle restores the hidden buffer into a new window", function()
			local buf, _ = create_test_pane()

			split_pane.toggle()
			local win_count_hidden = #get_normal_wins()

			split_pane.toggle()

			assert.are.same(win_count_hidden + 1, #get_normal_wins())
			local current_win = vim.api.nvim_get_current_win()
			assert.are.same(buf, vim.api.nvim_win_get_buf(current_win))
		end)

		it("SpKill destroys the buffer and closes the window", function()
			local buf, win = create_test_pane()

			assert.is_true(vim.api.nvim_buf_is_valid(buf))
			assert.is_true(vim.api.nvim_win_is_valid(win))

			split_pane.kill()

			assert.is_false(vim.api.nvim_win_is_valid(win))
			assert.is_false(vim.api.nvim_buf_is_valid(buf))
		end)

		it("SpToggle prevents closing the absolute last window", function()
			close_all_splits()
			local single_win = vim.api.nvim_get_current_win()

			split_pane.toggle()

			assert.is_true(vim.api.nvim_win_is_valid(single_win))
			assert.are.same(1, #get_normal_wins())
		end)
	end)
end)
