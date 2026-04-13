-- lua/split-pane.lua

---@class PaneManagerBehaviorConfig
---@field autosave boolean If true, auto-saves modified buffers on close/toggle instead of prompting (default: false).

---@class PaneManagerWindowConfig
---@field split_direction "v"|"h" Default split direction used by smart pickers (default: "v").

---@class PaneManagerKeymapsConfig
---@field find_vsplit string Find file → vertical split   (default: "<leader>fv").
---@field find_hsplit string Find file → horizontal split (default: "<leader>fh").
---@field grep_vsplit string Live grep → vertical split   (default: "<leader>gv").
---@field grep_hsplit string Live grep → horizontal split (default: "<leader>gh").
---@field new_vsplit  string New file  → vertical split   (default: "<leader>nv").
---@field new_hsplit  string New file  → horizontal split (default: "<leader>nh").
---@field smart_find  string Smart find file (ui.select)  (default: "<leader>fw").
---@field smart_grep  string Smart grep WS  (ui.select)   (default: "<leader>gw").
---@field smart_new   string Smart new file (ui.select)   (default: "<leader>nw").
---@field toggle_pane string Toggle hide/restore current pane (default: "<leader>pt").
---@field kill_pane   string Kill current pane and buffer (default: "<leader>pk").

---@class PaneManagerConfig
---@field window   PaneManagerWindowConfig
---@field keymaps  PaneManagerKeymapsConfig
---@field behavior PaneManagerBehaviorConfig

---@class PaneManager
---@field config PaneManagerConfig
local M = {}

local default_config = {
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
		new_vsplit = "<leader>nv",
		new_hsplit = "<leader>nh",
		smart_find = "<leader>fw",
		smart_grep = "<leader>gw",
		smart_new = "<leader>nw",
		toggle_pane = "<leader>pt",
		kill_pane = "<leader>pk",
	},
}

M.config = vim.deepcopy(default_config)

-- ── State ────────────────────────────────────────────────────────────────────

local state = {
	hidden_buf = nil,
	last_dir = nil,
}

-- ── UI Helpers ───────────────────────────────────────────────────────────────

--- Checks if a buffer is modified. If so, respects the autosave flag or pops a custom float.
---@param buf integer Buffer ID to check
---@param action_cb fun() Callback to execute after saving (or if user chooses to proceed without saving)
local function prompt_save(buf, action_cb)
	local is_modified = vim.api.nvim_get_option_value("modified", { buf = buf })

	-- If it's not modified, just proceed instantly.
	if not is_modified then
		action_cb()
		return
	end

	-- If autosave is on, silently write and proceed.
	if M.config.behavior.autosave then
		vim.api.nvim_buf_call(buf, function()
			vim.cmd("silent! write")
		end)
		action_cb()
		return
	end

	-- Otherwise, build the interactive prompt float
	local filename = vim.api.nvim_buf_get_name(buf)
	local display_name = vim.fn.fnamemodify(filename, ":~:.") -- Makes path relative to home/cwd
	if display_name == "" then
		display_name = "[No Name]"
	end

	local prompt_buf = vim.api.nvim_create_buf(false, true)
	local lines = {
		"",
		"  File: " .. display_name,
		"",
		"  Save changes before closing?",
		"  [y]es  /  [n]o  /  [c]ancel",
	}
	vim.api.nvim_buf_set_lines(prompt_buf, 0, -1, false, lines)

	-- Center the float
	local width = math.max(40, #display_name + 12)
	local height = #lines
	local col = math.floor((vim.o.columns - width) / 2)
	local row = math.floor((vim.o.lines - height) / 2)

	local win = vim.api.nvim_open_win(prompt_buf, true, {
		relative = "editor",
		width = width,
		height = height,
		col = col,
		row = row,
		style = "minimal",
		border = "rounded",
		title = { { " Unsaved Changes ", "WarningMsg" } },
		title_pos = "center",
		zindex = 100, -- Ensure it sits on top of everything
	})

	local function close_prompt()
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
		if vim.api.nvim_buf_is_valid(prompt_buf) then
			vim.api.nvim_buf_delete(prompt_buf, { force = true })
		end
	end

	-- Map Keys for the float
	local opts = { buffer = prompt_buf, noremap = true, silent = true }

	-- [Y]es: Save and execute action
	vim.keymap.set("n", "y", function()
		close_prompt()
		vim.api.nvim_buf_call(buf, function()
			vim.cmd("silent! write")
		end)
		action_cb()
	end, opts)

	-- [N]o: Don't save, but proceed with the action (killing/hiding)
	vim.keymap.set("n", "n", function()
		close_prompt()
		action_cb()
	end, opts)

	-- [C]ancel or [Esc]: Abort entirely
	vim.keymap.set("n", "c", close_prompt, opts)
	vim.keymap.set("n", "<Esc>", close_prompt, opts)
	vim.keymap.set("n", "q", close_prompt, opts)
end

-- ── Splits ───────────────────────────────────────────────────────────────────

local function split_open_buf(buf, split_dir, lnum, col)
	vim.api.nvim_set_option_value("buflisted", true, { buf = buf })
	local api_direction = (split_dir == "v") and "right" or "below"
	local win = vim.api.nvim_open_win(buf, true, {
		split = api_direction,
		win = vim.api.nvim_get_current_win(),
	})

	if lnum and lnum > 0 then
		vim.api.nvim_win_set_cursor(win, { lnum, math.max(0, (col or 1) - 1) })
		vim.api.nvim_win_call(win, function()
			vim.cmd.normal({ "zz", bang = true })
		end)
	end
end

local function split_open(filepath, split_dir, lnum, col)
	local buf = vim.fn.bufadd(filepath)
	split_open_buf(buf, split_dir, lnum, col)
end

-- ── Telescope ────────────────────────────────────────────────────────────────

local function make_attach(handler)
	return function(prompt_bufnr)
		local actions = require("telescope.actions")
		local action_state = require("telescope.actions.state")
		actions.select_default:replace(function()
			local entry = action_state.get_selected_entry()
			actions.close(prompt_bufnr)
			if entry then
				handler(entry)
			end
		end)
		return true
	end
end

local function telescope_find(split_dir)
	require("telescope.builtin").find_files({
		attach_mappings = make_attach(function(entry)
			split_open(entry.path or entry.filename, split_dir)
		end),
	})
end

local function telescope_grep(split_dir)
	require("telescope.builtin").live_grep({
		attach_mappings = make_attach(function(entry)
			split_open(entry.filename, split_dir, entry.lnum, entry.col)
		end),
	})
end

-- ── Files ─────────────────────────────────────────────────────────────────────

local function create_file(split_dir)
	local buf = vim.api.nvim_create_buf(false, true)
	local width = 50
	local height = 1
	local col = math.floor((vim.o.columns - width) / 2)
	local row = math.floor(vim.o.lines * 0.25)

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		col = col,
		row = row,
		style = "minimal",
		border = "rounded",
		-- Using highlight groups makes the float pop visually
		title = { { " Create New File (CWD) ", "DiagnosticInfo" } },
		title_pos = "center",
		zindex = 50,
	})

	vim.cmd("startinsert")

	local function close_float()
		vim.cmd("stopinsert")
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
		if vim.api.nvim_buf_is_valid(buf) then
			vim.api.nvim_buf_delete(buf, { force = true })
		end
	end

	vim.keymap.set({ "n", "i" }, "<CR>", function()
		local lines = vim.api.nvim_buf_get_lines(buf, 0, 1, false)
		local input = lines[1] or ""
		close_float()

		if input == "" then
			return
		end

		local cwd = vim.fn.getcwd()
		local path = vim.fn.expand(cwd .. "/" .. input)
		local dir = vim.fn.fnamemodify(path, ":h")

		if vim.fn.isdirectory(dir) == 0 then
			local ok, err = pcall(vim.fn.mkdir, dir, "p")
			if not ok then
				vim.notify("[split-pane] mkdir failed: " .. tostring(err), vim.log.levels.ERROR)
				return
			end
		end

		split_open(path, split_dir)
	end, { buffer = buf, noremap = true, silent = true })

	vim.keymap.set({ "n", "i" }, "<Esc>", close_float, { buffer = buf, noremap = true, silent = true })
	vim.keymap.set({ "n", "i" }, "<C-c>", close_float, { buffer = buf, noremap = true, silent = true })
end

-- ── Smart pickers ─────────────────────────────────────────────────────────────

local DIRECTIONS = {
	{ label = "  Vertical split", dir = "v" },
	{ label = "  Horizontal split", dir = "h" },
}

local function with_direction(action)
	local labels = vim.tbl_map(function(o)
		return o.label
	end, DIRECTIONS)
	vim.ui.select(labels, { prompt = "  Split Pane – open in:" }, function(choice)
		if not choice then
			return
		end
		for _, opt in ipairs(DIRECTIONS) do
			if opt.label == choice then
				action(opt.dir)
				return
			end
		end
	end)
end

-- ── Public API ───────────────────────────────────────────────────────────────

function M.find(split_dir)
	telescope_find(split_dir or M.config.window.split_direction)
end

function M.grep(split_dir)
	telescope_grep(split_dir or M.config.window.split_direction)
end

function M.new_file(split_dir)
	create_file(split_dir or M.config.window.split_direction)
end

function M.toggle()
	if state.hidden_buf and vim.api.nvim_buf_is_valid(state.hidden_buf) then
		split_open_buf(state.hidden_buf, state.last_dir or M.config.window.split_direction)
		state.hidden_buf = nil
	else
		local win = vim.api.nvim_get_current_win()
		local buf = vim.api.nvim_win_get_buf(win)

		-- Count ONLY normal windows (ignore floats like Telescope, UI plugins, or Plenary)
		local normal_win_count = 0
		for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
			if vim.api.nvim_win_get_config(w).relative == "" then
				normal_win_count = normal_win_count + 1
			end
		end

		if normal_win_count <= 1 then
			vim.notify("[split-pane] Cannot hide the last open window.", vim.log.levels.WARN)
			return
		end

		prompt_save(buf, function()
			state.hidden_buf = buf
			state.last_dir = M.config.window.split_direction
			vim.api.nvim_win_close(win, true)
		end)
	end
end

function M.kill()
	local buf = vim.api.nvim_get_current_buf()

	-- Wrap the kill action in our new prompt_save logic
	prompt_save(buf, function()
		if state.hidden_buf == buf then
			state.hidden_buf = nil
		end
		-- force=true ensures we bypass standard neovim unsaved warnings
		-- since we already handled the prompt ourselves.
		vim.api.nvim_buf_delete(buf, { force = true })
	end)
end

function M.setup(user_opts)
	M.config = vim.tbl_deep_extend("force", vim.deepcopy(default_config), user_opts or {})

	state.hidden_buf = nil
	state.last_dir = nil

	local km = M.config.keymaps
	local map = function(lhs, rhs, desc)
		vim.keymap.set("n", lhs, rhs, { desc = "[SP] " .. desc, noremap = true, silent = true })
	end

	map(km.find_vsplit, function()
		M.find("v")
	end, "Find file → vsplit")
	map(km.find_hsplit, function()
		M.find("h")
	end, "Find file → hsplit")
	map(km.grep_vsplit, function()
		M.grep("v")
	end, "Grep WS → vsplit")
	map(km.grep_hsplit, function()
		M.grep("h")
	end, "Grep WS → hsplit")
	map(km.new_vsplit, function()
		M.new_file("v")
	end, "New file → vsplit")
	map(km.new_hsplit, function()
		M.new_file("h")
	end, "New file → hsplit")
	map(km.smart_find, function()
		with_direction(telescope_find)
	end, "Smart find file")
	map(km.smart_grep, function()
		with_direction(telescope_grep)
	end, "Smart grep WS")
	map(km.smart_new, function()
		with_direction(create_file)
	end, "Smart new file")
	map(km.toggle_pane, function()
		M.toggle()
	end, "Toggle current pane")
	map(km.kill_pane, function()
		M.kill()
	end, "Kill current pane")

	vim.api.nvim_create_user_command("SpFind", function()
		M.find()
	end, {})
	vim.api.nvim_create_user_command("SpGrep", function()
		M.grep()
	end, {})
	vim.api.nvim_create_user_command("SpNew", function()
		M.new_file()
	end, {})
	vim.api.nvim_create_user_command("SpToggle", function()
		M.toggle()
	end, {})
	vim.api.nvim_create_user_command("SpKill", function()
		M.kill()
	end, {})
end

return M
