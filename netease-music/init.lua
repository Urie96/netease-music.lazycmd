local M = {}

local actions = require 'netease-music.actions'
local api = require 'netease-music.api'
local config = require 'netease-music.config'
local root = require 'netease-music.root'
local shared = require 'netease-music.shared'

local function config_entries(err)
  return {
    {
      key = 'configure',
      kind = 'info',
      display = lc.style.line { lc.style.span('请通过 setup() 配置网易云音乐插件'):fg 'yellow' },
      preview = function(_, cb)
        cb(shared.preview_lines {
          lc.style.line { shared.titlec '网易云音乐插件配置' },
          '',
          shared.kv_line('base_url', 'NeteaseCloudMusicApi 服务地址', 'accent'),
          '',
          lc.style.line { shared.dim(tostring(err)) },
        })
      end,
    },
  }
end

function M.setup(opt)
  config.setup(opt)
  local _, setup_err = lc.plugin.load 'mpv'
  if setup_err then lc.log('warn', 'failed to setup mpv plugin from netease-music: {}', tostring(setup_err)) end
end

function M.list(path, cb)
  local ok, err = api.ensure_configured()
  if not ok then
    cb(config_entries(err))
    return
  end

  root.list(path, function(entries, list_err)
    if list_err then
      shared.show_error(list_err)
      cb {}
      return
    end
    cb(entries)
  end)
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

  cb(shared.preview_lines {
    lc.style.line { shared.titlec(entry.key or '网易云音乐') },
  })
end

return M
