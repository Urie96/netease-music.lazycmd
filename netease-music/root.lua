local M = {}

local actions = require 'netease-music.actions'
local api = require 'netease-music.api'
local config = require 'netease-music.config'
local shared = require 'netease-music.shared'

local function section_entry(key, title, color, subtitle)
  return {
    key = key,
    kind = 'section',
    display = lc.style.line {
      color(title),
      shared.dim '  ·  ',
      shared.dim(subtitle),
    },
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
        lc.style.line { shared.titlec 'Account' },
        '',
        shared.kv_line('Base URL', cfg.base_url or '-', 'accent'),
        shared.kv_line('Cookie', api.get_cookie() and 'configured' or 'missing', api.get_cookie() and 'warm' or 'mag'),
        shared.kv_line('UID', api.get_uid() or cfg.uid or '-', 'accent'),
        '',
        lc.style.line { shared.dim('Login status unavailable: ' .. tostring(err)) },
      }
    end

    cb {
      {
        key = 'status',
        kind = 'info',
        display = lc.style.line {
          shared.titlec(data and data.profile and data.profile.nickname or 'Account status'),
          shared.dim '  ·  ',
          shared.dim(err and 'offline' or 'ready'),
        },
        keymap = {
          [config.get().keymap.search] = { callback = actions.open_search_input, desc = 'search music' },
        },
        preview = function(_, done) done(lines) end,
      },
    }
  end)
end

local sections = {
  {
    key = 'account',
    title = 'Account',
    subtitle = 'login status, cookie and uid',
    color = shared.accent,
  },
  {
    key = 'recommend',
    title = 'Daily Playlists',
    subtitle = 'recommend/resource, requires login',
    color = shared.okc,
  },
  {
    key = 'daily',
    title = 'Daily Songs',
    subtitle = 'recommend/songs, requires login',
    color = shared.warm,
  },
  {
    key = 'my',
    title = 'My Playlists',
    subtitle = 'user/playlist, requires uid or login',
    color = shared.mag,
  },
  {
    key = 'personalized',
    title = 'Personalized',
    subtitle = 'public recommended playlists',
    color = shared.okc,
  },
  {
    key = 'top',
    title = 'Top Playlists',
    subtitle = 'hot playlists from top/playlist',
    color = shared.warm,
  },
  {
    key = 'search',
    title = 'Search',
    subtitle = 'songs, albums, artists and playlists',
    color = shared.titlec,
  },
}

local function list_daily_songs(cb)
  api.list_daily_songs(function(songs, err)
    if err then
      cb(nil, err)
      return
    end

    local keymap = config.get().keymap
    local entries = {}
    for _, song in ipairs(songs or {}) do
      table.insert(entries, {
        key = tostring(song.id),
        kind = 'song',
        song = song,
        display = shared.format_song_display(song),
        keymap = {
          [keymap.play_now] = { callback = actions.play_song_entry, desc = 'play now' },
          [keymap.append_to_player] = { callback = actions.append_song_entry, desc = 'append to player' },
        },
        preview = function(_, done) shared.song_preview(song, done) end,
      })
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

  if section == 'search' then
    require('netease-music.search').list(path, cb)
    return
  end

  require('netease-music.playlist').list(path, cb)
end

return M
