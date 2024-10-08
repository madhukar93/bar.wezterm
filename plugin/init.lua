local wez = require "wezterm"

local M = {}
local options = {}

local separator = package.config:sub(1, 1) == "\\" and "\\" or "/"
local plugin_dir = wez.plugin.list()[1].plugin_dir:gsub(separator .. "[^" .. separator .. "]*$", "")

--- Checks if the plugin directory exists
local function directory_exists(path)
  local success, result = pcall(wez.read_dir, plugin_dir .. path)
  return success and result
end

--- Returns the name of the package, used when requiring modules
local function get_require_path()
  local repo_owner = "madhukar93"
  local path = "httpssCssZssZsgithubsDscomsZs" .. repo_owner .. "sZsbarsDswezterm"
  local path_trailing_slash = path .. "sZs"
  return directory_exists(path_trailing_slash) and path_trailing_slash or path
end

package.path = package.path
  .. ";"
  .. plugin_dir
  .. separator
  .. get_require_path()
  .. separator
  .. "plugin"
  .. separator
  .. "?.lua"

local utilities = require "bar.utilities"
local config = require "bar.config"
local tabs = require "bar.tabs"
local user = require "bar.user"
local spotify = require "bar.spotify"
local paths = require "bar.paths"

-- conforming to https://github.com/wez/wezterm/commit/e4ae8a844d8feaa43e1de34c5cc8b4f07ce525dd
M.apply_to_config = function(c, opts)
  -- make the opts arg optional
  if not opts then
    opts = {}
  end

  -- combine user config with defaults
  options = config.extend_options(config.options, opts)

  local scheme = wez.color.get_builtin_schemes()[c.color_scheme]
  local default_colors = {
    tab_bar = {
      background = "transparent",
      active_tab = {
        bg_color = "transparent",
        fg_color = scheme.ansi[options.modules.tabs.active_tab_fg],
      },
      inactive_tab = {
        bg_color = "transparent",
        fg_color = scheme.ansi[options.modules.tabs.inactive_tab_fg],
      },
    },
  }

  if c.colors == nil then
    c.colors = default_colors
  else
    c.colors = utilities._merge(default_colors, c.colors)
  end

  -- make the plugin own these settings
  c.use_fancy_tab_bar = false
  c.tab_bar_at_bottom = options.position == "bottom"
  c.tab_max_width = options.max_width
end

wez.on("format-tab-title", function(tab, _, _, conf, _, _)
  local palette = conf.resolved_palette

  local index = tab.tab_index + 1
  local offset = #tostring(index) + #options.separator.left_icon + (2 * options.separator.space) + 2
  local title = index
    .. utilities._space(options.separator.left_icon, options.separator.space, nil)
    .. tabs.get_title(tab)

  local width = conf.tab_max_width - offset
  if #title > conf.tab_max_width then
    title = wez.truncate_right(title, width) .. "…"
  end

  local fg = palette.tab_bar.inactive_tab.fg_color
  local bg = palette.tab_bar.inactive_tab.bg_color
  if tab.is_active then
    fg = palette.tab_bar.active_tab.fg_color
    bg = palette.tab_bar.active_tab.bg_color
  end

  return {
    { Background = { Color = bg } },
    { Foreground = { Color = fg } },
    { Text = utilities._space(title, 0, 2) },
  }
end)

-- Name of workspace
wez.on("update-status", function(window, pane)
  local present, conf = pcall(window.effective_config, window)
  if not present then
    return
  end

  local palette = conf.resolved_palette

  -- left status
  local left_cells = {
    { Background = { Color = palette.tab_bar.background } },
  }

  if options.modules.workspace.enabled then
    local stat = " " .. options.modules.workspace.icon .. " " .. window:active_workspace() .. " "
    local stat_fg = palette.ansi[options.modules.workspace.color]

    if window:leader_is_active() then
      local leader_stat = " " .. options.modules.leader.icon .. " " .. window:active_workspace() .. " "
      stat_fg = palette.ansi[options.modules.leader.color]
      stat = utilities._constant_width(stat, leader_stat)
    end

    table.insert(left_cells, { Foreground = { Color = stat_fg } })
    table.insert(left_cells, { Text = stat })
  end

  if options.modules.pane.enabled then
    local success, result = pcall(function()
      return pane:get_foreground_process_name()
    end)
    if success and result then
      local process = utilities._basename(result)
      table.insert(left_cells, { Foreground = { Color = palette.ansi[options.modules.pane.color] } })
      table.insert(left_cells, { Text = options.modules.pane.icon .. " " .. process .. " " })
    end
  end

  window:set_left_status(wez.format(left_cells))

  -- right status
  local right_cells = {
    { Background = { Color = palette.tab_bar.background } },
  }

  local callbacks = {
    {
      name = "spotify",
      func = function()
        return spotify.get_currently_playing(options.modules.spotify.max_width, options.modules.spotify.throttle)
      end,
    },
    {
      name = "username",
      func = function()
        return user.username
      end,
    },
    {
      name = "hostname",
      func = function()
        return pane:get_user_vars().hostname or pane:get_domain_name()
      end,
      style = function(hostname)
        if not string.find(hostname, "local") then
          return palette.brights
        end
      end,
    },
    {
      name = "clock",
      func = function()
        return wez.time.now():format "%H:%M"
      end,
    },
    {
      name = "cwd",
      func = function()
        return paths.get_cwd(pane, true)
      end,
    },
  }

  for _, module in ipairs(callbacks) do
    local text = (function()
      local success, result = pcall(module.func)
      return success and result or ""
    end)()
    if #text > 0 and options.modules[module.name].enabled then
      table.insert(right_cells, { Foreground = { Color = palette.ansi[options.modules[module.name].color] } })
      table.insert(right_cells, { Text = text })
      table.insert(right_cells, { Foreground = { Color = palette.brights[1] } })
      table.insert(right_cells, {
        Text = utilities._space(options.separator.right_icon, options.separator.space, nil)
          .. options.modules[module.name].icon
          .. utilities._space(options.separator.field_icon, options.separator.space, nil),
      })
    end
  end

  window:set_right_status(wez.format(right_cells))
end)

return M
