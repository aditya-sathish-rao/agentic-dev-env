local wezterm = require('wezterm')
local config = wezterm.config_builder()

config.font = wezterm.font('Hack Nerd Font')
config.font_size = 22.0
config.color_scheme = 'Rasi (terminal.sexy)'
config.window_background_opacity = 0.3
config.macos_window_background_blur = 90
config.window_decorations = 'RESIZE'
config.hide_tab_bar_if_only_one_tab = true

return config
