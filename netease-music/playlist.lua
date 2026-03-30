local M = {}

local actions = require 'netease-music.actions'
local api = require 'netease-music.api'
local config = require 'netease-music.config'
local shared = require 'netease-music.shared'

local function playlist_keymap()
  local keymap = config.get().keymap
  return {
    [keymap.append_playlist_to_player] = { callback = actions.append_playlist_entry, desc = 'append playlist to player' },
  }
end

local function song_keymap()
  local keymap = config.get().keymap
  return {
    [keymap.play_now] = { callback = actions.play_song_entry, desc = 'play now' },
    [keymap.append_to_player] = { callback = actions.append_song_entry, desc = 'append to player' },
  }
end

local function build_playlist_entry(playlist)
  return {
    key = tostring(playlist.id),
    kind = 'playlist',
    playlist = playlist,
    display = shared.format_playlist_display(playlist),
    keymap = playlist_keymap(),
    preview = function(_, cb) cb(shared.playlist_preview(playlist)) end,
  }
end

local function build_song_entry(song, playlist)
  return {
    key = tostring(song.id),
    kind = 'song',
    song = song,
    playlist = playlist,
    display = shared.format_song_display(song),
    keymap = song_keymap(),
    preview = function(_, cb) shared.song_preview(song, cb) end,
  }
end

local function empty_entry(message)
  return {
    key = 'empty',
    kind = 'info',
    display = lc.style.line { shared.dim(message) },
    preview = function(_, cb) cb(shared.preview_lines { message }) end,
  }
end

local sources = {
  personalized = function(cb) api.list_personalized_playlists(cb) end,
  top = function(cb) api.list_top_playlists(cb) end,
  my = function(cb) api.list_my_playlists(cb) end,
  recommend = function(cb) api.list_recommend_playlists(cb) end,
}

function M.list(path, cb)
  local source = path[2]
  local loader = sources[source]
  if not loader then
    cb({}, 'unknown playlist source: ' .. tostring(source))
    return
  end

  if #path == 2 then
    loader(function(playlists, err)
      if err then
        cb(nil, err)
        return
      end

      local entries = {}
      for _, playlist in ipairs(playlists or {}) do
        table.insert(entries, build_playlist_entry(playlist))
      end
      if #entries == 0 then entries = { empty_entry 'No playlists available' } end
      cb(entries)
    end)
    return
  end

  api.get_playlist_detail(path[3], function(playlist, songs, err)
    if err then
      cb(nil, err)
      return
    end

    local entries = {}
    for _, song in ipairs(songs or {}) do
      table.insert(entries, build_song_entry(song, playlist))
    end
    if #entries == 0 then entries = { empty_entry 'This playlist has no songs' } end
    cb(entries)
  end)
end

return M
