local M = {}

local api = require 'netease-music.api'
local config = require 'netease-music.config'
local shared = require 'netease-music.shared'

local function hovered_entry() return lc.api.page_get_hovered() end

local function get_mpv()
  local ok, mod = pcall(require, 'mpv')
  if ok and mod then return mod end
  shared.show_error('mpv plugin is required: add { dir = "plugins/mpv.lazycmd" } to lc.config.plugins')
  return nil
end

local function reload_if_player_visible()
  local path = lc.api.get_current_path() or {}
  if path[1] == 'mpv' then lc.cmd 'reload' end
end

local function player_preview(entry)
  local meta = entry.mpv_meta or {}
  local item = entry.player_item or {}
  local player = entry.player or {}

  return shared.preview_lines {
    lc.style.line { shared.okc 'mpv queue' },
    '',
    shared.kv_line('State', player.pause and 'paused' or 'playing', player.pause and 'warm' or 'accent'),
    shared.kv_line('Current', tostring(item.current == true or item.playing == true), 'accent'),
    shared.kv_line('Title', meta.title or item.title or '-'),
    shared.kv_line('Artist', meta.artist or '-'),
    shared.kv_line('Album', meta.album or '-'),
    shared.kv_line('Duration', shared.format_duration(meta.duration or 0), 'accent'),
  }
end

local function build_mpv_track(song, url_info)
  local keymap = config.get().keymap
  return {
    id = song.id,
    key = tostring(song.id),
    url = url_info.url,
    title = shared.song_title(song),
    artist = shared.song_artists(song),
    album = shared.song_album(song),
    duration = song.dt or song.duration,
    source = 'netease-music',
    display = function(item, player, meta)
      local current = item.current or item.playing
      local marker = shared.dim '  '
      if current then marker = player.pause and shared.warm '⏸ ' or shared.okc '▶ ' end
      return lc.style.line {
        marker,
        shared.titlec(meta.title or item.title or '-'),
        shared.dim '  [',
        shared.accent(meta.artist or '-'),
        shared.dim ']',
      }
    end,
    preview = function(entry, cb)
      local preview = player_preview(entry)
      if cb then
        cb(preview)
        return
      end
      return preview
    end,
    keymap = {
      [keymap.search] = { callback = M.open_search_input, desc = 'search music' },
    },
  }
end

local function collect_playable_tracks(songs, cb)
  local ids = {}
  for _, song in ipairs(songs or {}) do
    table.insert(ids, song.id)
  end

  api.get_song_urls(ids, function(urls, err)
    if err then
      cb(nil, err)
      return
    end

    local tracks = {}
    local skipped = 0
    for _, song in ipairs(songs or {}) do
      local url_info = urls[tostring(song.id)]
      if url_info and url_info.url and url_info.url ~= '' then
        table.insert(tracks, build_mpv_track(song, url_info))
      else
        skipped = skipped + 1
      end
    end

    cb(tracks, nil, skipped)
  end)
end

function M.open_search_input()
  lc.input {
    prompt = 'Search Netease Music',
    placeholder = 'keyword',
    on_submit = function(input)
      local query = tostring(input or ''):trim()
      if query == '' then
        lc.api.go_to { 'netease-music', 'search' }
        return
      end
      lc.api.go_to { 'netease-music', 'search', query }
    end,
  }
end

function M.play_song_entry()
  local target = hovered_entry()
  if not target or target.kind ~= 'song' or not target.song then
    lc.cmd 'enter'
    return
  end

  local mpv = get_mpv()
  if not mpv then return false end

  local _, entries = shared.current_song_entries()
  local start = 1
  for index, entry in ipairs(entries or {}) do
    if entry.kind == 'song' and entry.song and tostring(entry.song.id) == tostring(target.song.id) then
      start = index
      break
    end
  end

  local songs = {}
  for index = start, #entries do
    local entry = entries[index]
    if entry and entry.kind == 'song' and entry.song then table.insert(songs, entry.song) end
  end

  collect_playable_tracks(songs, function(tracks, err, skipped)
    if err then
      shared.show_error(err)
      return
    end
    if #tracks == 0 then
      shared.show_error 'No playable tracks in current selection'
      return
    end

    mpv.play_tracks(tracks)
      :next(function()
        local msg = 'Sent tracks to mpv queue'
        if skipped and skipped > 0 then msg = msg .. (' (' .. skipped .. ' skipped)') end
        shared.show_info(msg)
        reload_if_player_visible()
      end)
      :catch(function(play_err)
        shared.show_error(play_err)
      end)
  end)

  return true
end

function M.append_song_entry()
  local target = hovered_entry()
  if not target or target.kind ~= 'song' or not target.song then return false end

  local mpv = get_mpv()
  if not mpv then return false end

  collect_playable_tracks({ target.song }, function(tracks, err)
    if err then
      shared.show_error(err)
      return
    end
    if #tracks == 0 then
      shared.show_error 'Current song is not playable'
      return
    end

    mpv.append_tracks(tracks)
      :next(function()
        shared.show_info 'Song appended to mpv queue'
        reload_if_player_visible()
      end)
      :catch(function(append_err)
        shared.show_error(append_err)
      end)
  end)

  return true
end

function M.append_playlist_entry()
  local target = hovered_entry()
  if not target or target.kind ~= 'playlist' or not target.playlist or not target.playlist.id then return false end

  local mpv = get_mpv()
  if not mpv then return false end

  api.get_playlist_detail(target.playlist.id, function(_, songs, err)
    if err then
      shared.show_error(err)
      return
    end

    collect_playable_tracks(songs, function(tracks, track_err, skipped)
      if track_err then
        shared.show_error(track_err)
        return
      end
      if #tracks == 0 then
        shared.show_error 'No playable songs in this playlist'
        return
      end

      mpv.append_tracks(tracks)
        :next(function()
          local msg = 'Playlist appended to mpv queue'
          if skipped and skipped > 0 then msg = msg .. (' (' .. skipped .. ' skipped)') end
          shared.show_info(msg)
          reload_if_player_visible()
        end)
        :catch(function(append_err)
          shared.show_error(append_err)
        end)
    end)
  end)

  return true
end

return M
