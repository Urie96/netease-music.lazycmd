local M = {}

local api = require 'netease-music.api'
local config = require 'netease-music.config'
local provider = require 'netease-music.provider'
local shared = require 'netease-music.shared'

local browser = nil

local function config_entries(err)
  return {
    {
      key = 'configure',
      kind = 'info',
      display = deck.style.line { deck.style.span('请通过 setup() 配置网易云音乐插件'):fg 'yellow' },
      preview = function(_, cb)
        cb(shared.preview_lines {
          deck.style.line { shared.titlec '网易云音乐插件配置' },
          '',
          shared.kv_line('base_url', 'NeteaseCloudMusicApi 服务地址', 'accent'),
          '',
          deck.style.line { shared.dim(tostring(err)) },
        })
      end,
    },
  }
end

local function ensure_browser()
  if browser then return browser end

  local music, load_err = deck.plugin.load 'music'
  if not music then error('failed to load music plugin: ' .. tostring(load_err)) end

  browser = music.new(provider, {
    root = 'netease-music',
  })
  return browser
end

function M.setup(opt)
  config.setup(opt)
  browser = nil
  local _, setup_err = deck.plugin.load 'music'
  if setup_err then deck.log('warn', 'failed to setup music plugin from netease-music: {}', tostring(setup_err)) end
end

function M.list(path, cb)
  local ok, err = api.ensure_configured()
  if not ok then
    cb(config_entries(err))
    return
  end

  local get_ok, b_or_err = pcall(ensure_browser)
  if not get_ok then
    cb(config_entries(b_or_err))
    return
  end

  b_or_err:list(path, cb)
end

function M.preview(entry, cb)
  if not entry then
    cb ''
    return
  end

  if type(entry.preview) == 'function' then
    entry:preview(cb)
    return
  end

  local get_ok, b_or_err = pcall(ensure_browser)
  if get_ok then
    b_or_err:preview(entry, cb)
  else
    cb(shared.preview_lines { tostring(b_or_err) })
  end
end

return M
