local wezterm = require 'wezterm'
local config = wezterm.config_builder()

config.font = wezterm.font 'Hack Nerd Font'
config.font_size = 18.0

return config