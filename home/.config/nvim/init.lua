require('vim_config')
require('keys')

-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'
-- Probe the plugin itself, not just the directory: a failed clone leaves the dir behind.
if not (vim.uv or vim.loop).fs_stat(lazypath .. '/lua/lazy') then
  local clone_cmd = {
    'git',
    'clone',
    '--filter=blob:none',
    'https://github.com/folke/lazy.nvim.git',
    lazypath,
  }
  -- pcall: vim.fn.system raises when git itself is missing
  local ok, output = pcall(vim.fn.system, clone_cmd)
  if not ok or vim.v.shell_error ~= 0 then
    vim.fn.delete(lazypath, 'rf') -- so the next launch retries instead of finding an empty dir
    vim.api.nvim_echo({
      { 'Failed to clone lazy.nvim:\n', 'ErrorMsg' },
      { table.concat(clone_cmd, ' ') .. '\n', 'WarningMsg' },
      { tostring(output), 'WarningMsg' },
    }, true, {})
    -- keep the error on screen for an interactive launch
    if #vim.api.nvim_list_uis() > 0 then
      vim.fn.getchar()
    end
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

-- Load all plugins from lua/plugins/
require('lazy').setup({
  spec = {
    { import = 'plugins' },
  },
  -- no plugin here needs luarocks, and the hererocks check only adds noise to :checkhealth lazy
  rocks = { enabled = false },
})
