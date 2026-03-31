local M = {}

local actions = require 'netease-music.actions'
local api = require 'netease-music.api'
local config = require 'netease-music.config'
local shared = require 'netease-music.shared'

local function section_entry(key, title, color, subtitle)
  return {
    key = key,
    kind = 'section',
    display = lc.style.line { color(title) },
    preview = function(_, cb)
      cb(shared.preview_lines {
        lc.style.line { color(title) },
        '',
        lc.style.line { shared.dim(subtitle) },
      })
    end,
  }
end

local function account_entries(cb)
  api.get_login_status(function(data, err)
    local cfg = config.get()
    local preview = shared.account_preview(data, cfg)
    local lines = preview
    if err then
      lines = shared.preview_lines {
        lc.style.line { shared.titlec '账号' },
        '',
        shared.kv_line('服务地址', cfg.base_url or '-', 'accent'),
        shared.kv_line('Cookie', api.get_cookie() and '已配置' or '未配置', api.get_cookie() and 'warm' or 'mag'),
        shared.kv_line('UID', api.get_uid() or cfg.uid or '-', 'accent'),
        '',
        lc.style.line { shared.dim('登录状态不可用：' .. tostring(err)) },
      }
    end

    cb {
      {
        key = 'status',
        kind = 'info',
        display = lc.style.line {
          shared.titlec(data and data.profile and data.profile.nickname or '账号状态'),
          shared.dim '  ·  ',
          shared.dim(err and '离线' or '就绪'),
        },
        keymap = {
          [config.get().keymap.search] = { callback = actions.open_search_input, desc = '搜索音乐' },
        },
        preview = function(_, done) done(lines) end,
      },
    }
  end)
end

local sections = {
  {
    key = 'account',
    title = '账号',
    subtitle = '登录状态、Cookie 和 UID',
    color = shared.accent,
  },
  {
    key = 'recommend',
    title = '每日推荐歌单',
    subtitle = 'recommend/resource，需要登录',
    color = shared.okc,
  },
  {
    key = 'daily',
    title = '每日推荐歌曲',
    subtitle = 'recommend/songs，需要登录',
    color = shared.warm,
  },
  {
    key = 'my',
    title = '我的歌单',
    subtitle = 'user/playlist，需要 UID 或登录态',
    color = shared.mag,
  },
  {
    key = 'liked',
    title = '我喜欢的音乐',
    subtitle = 'likelist + song/detail，需要登录',
    color = shared.accent,
  },
  {
    key = 'personalized',
    title = '推荐歌单',
    subtitle = '公开推荐歌单',
    color = shared.okc,
  },
  {
    key = 'top',
    title = '热门歌单',
    subtitle = 'top/playlist 热门歌单',
    color = shared.warm,
  },
  {
    key = 'search',
    title = '搜索',
    subtitle = '歌曲、专辑、歌手、歌单',
    color = shared.titlec,
  },
}

local function list_daily_songs(cb)
  local playlist = require 'netease-music.playlist'
  api.list_daily_songs(function(songs, err)
    if err then
      cb(nil, err)
      return
    end

    local entries = {}
    for _, song in ipairs(songs or {}) do
        table.insert(entries, playlist.build_song_entry(song, {
          id = 'daily-songs',
        name = '每日推荐歌曲',
      }))
    end
    cb(entries)
  end)
end

function M.list(path, cb)
  if #path == 1 then
    local entries = {}
    for _, section in ipairs(sections) do
      table.insert(entries, section_entry(section.key, section.title, section.color, section.subtitle))
    end
    cb(entries)
    return
  end

  local section = path[2]
  if section == 'account' then
    account_entries(cb)
    return
  end

  if section == 'daily' then
    list_daily_songs(cb)
    return
  end

  if section == 'liked' then
    require('netease-music.playlist').list_liked_songs_entries(cb)
    return
  end

  if section == 'search' then
    require('netease-music.search').list(path, cb)
    return
  end

  require('netease-music.playlist').list(path, cb)
end

return M
