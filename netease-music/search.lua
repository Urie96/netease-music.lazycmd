local M = {}

local actions = require 'netease-music.actions'
local api = require 'netease-music.api'
local config = require 'netease-music.config'
local shared = require 'netease-music.shared'

local function search_keymap()
  local keymap = config.get().keymap
  return {
    [keymap.search] = { callback = actions.open_search_input, desc = 'search again' },
  }
end

local function song_keymap()
  local keymap = config.get().keymap
  return {
    [keymap.play_now] = { callback = actions.play_song_entry, desc = 'play now' },
    [keymap.append_to_player] = { callback = actions.append_song_entry, desc = 'append to player' },
    [keymap.search] = { callback = actions.open_search_input, desc = 'search again' },
  }
end

local function list_search_root(cb)
  local keymap = config.get().keymap
  cb {
    {
      key = 'prompt',
      kind = 'info',
      display = lc.style.line { shared.titlec(('Press %s to search songs, albums, artists and playlists'):format(keymap.search)) },
      keymap = search_keymap(),
      preview = function(_, done)
        done(shared.preview_lines {
          lc.style.line { shared.titlec 'Search Netease Music' },
          '',
          lc.style.line { shared.dim 'Search uses /cloudsearch and groups results by song, album, artist and playlist.' },
        })
      end,
    },
  }
end

local function group_display(kind, count)
  local color = kind == 'artist' and shared.mag or (kind == 'album' and shared.warm or (kind == 'playlist' and shared.okc or shared.accent))
  local title = kind:gsub('^%l', string.upper)
  return lc.style.line {
    color(title),
    shared.dim '  ·  ',
    shared.okc(count),
    shared.dim(' ' .. title .. (count == 1 and '' or 's')),
  }
end

local function list_search_groups(query, cb)
  api.search(query, function(result, err)
    if err then
      cb(nil, err)
      return
    end

    local entries = {}
    for _, kind in ipairs { 'song', 'album', 'artist', 'playlist' } do
      local items = result[kind] or {}
      table.insert(entries, {
        key = kind,
        kind = 'search_group',
        query = query,
        search_kind = kind,
        count = #items,
        display = group_display(kind, #items),
        keymap = search_keymap(),
        preview = function(entry, done)
          done(shared.preview_lines {
            lc.style.line { shared.titlec 'Search results' },
            '',
            shared.kv_line('Query', entry.query or '-', 'accent'),
            shared.kv_line('Type', entry.search_kind or '-', 'warm'),
            shared.kv_line('Count', tostring(entry.count or 0), 'accent'),
          })
        end,
      })
    end
    cb(entries)
  end)
end

local function build_song_entry(song)
  return {
    key = tostring(song.id),
    kind = 'song',
    song = song,
    display = shared.format_song_display(song),
    keymap = song_keymap(),
    preview = function(_, cb) shared.song_preview(song, cb) end,
  }
end

local function build_album_entry(album)
  return {
    key = tostring(album.id),
    kind = 'info',
    display = shared.format_album_display(album),
    keymap = search_keymap(),
    preview = function(_, cb)
      cb(shared.preview_lines {
        lc.style.line { shared.warm(album.name or 'Album') },
        '',
        shared.kv_line('Artist', shared.song_artists { artists = album.artists or {} }, 'accent'),
        shared.kv_line('Album ID', tostring(album.id or '-')),
      })
    end,
  }
end

local function build_artist_entry(artist)
  return {
    key = tostring(artist.id),
    kind = 'info',
    display = shared.format_artist_display(artist),
    keymap = search_keymap(),
    preview = function(_, cb)
      cb(shared.preview_lines {
        lc.style.line { shared.mag(artist.name or 'Artist') },
        '',
        shared.kv_line('Artist ID', tostring(artist.id or '-')),
        shared.kv_line('Alias', artist.alias and table.concat(artist.alias, ', ') or '-'),
      })
    end,
  }
end

local function build_playlist_entry(playlist)
  local keymap = config.get().keymap
  return {
    key = tostring(playlist.id),
    kind = 'playlist',
    playlist = playlist,
    display = shared.format_playlist_display(playlist),
    keymap = {
      [keymap.append_playlist_to_player] = { callback = actions.append_playlist_entry, desc = 'append playlist to player' },
      [keymap.search] = { callback = actions.open_search_input, desc = 'search again' },
    },
    preview = function(_, cb) cb(shared.playlist_preview(playlist)) end,
  }
end

local function list_search_items(query, kind, cb)
  api.search(query, function(result, err)
    if err then
      cb(nil, err)
      return
    end

    local items = result[kind] or {}
    local entries = {}
    if kind == 'song' then
      for _, item in ipairs(items) do
        table.insert(entries, build_song_entry(item))
      end
    elseif kind == 'album' then
      for _, item in ipairs(items) do
        table.insert(entries, build_album_entry(item))
      end
    elseif kind == 'artist' then
      for _, item in ipairs(items) do
        table.insert(entries, build_artist_entry(item))
      end
    elseif kind == 'playlist' then
      for _, item in ipairs(items) do
        table.insert(entries, build_playlist_entry(item))
      end
    end

    if #entries == 0 then
      entries = {
        {
          key = 'empty',
          kind = 'info',
          display = lc.style.line { shared.dim('No ' .. kind .. ' matched this query') },
          keymap = search_keymap(),
          preview = function(_, done)
            done(shared.preview_lines {
              lc.style.line { shared.dim 'No results' },
              '',
              shared.kv_line('Query', query, 'accent'),
              shared.kv_line('Type', kind, 'warm'),
            })
          end,
        },
      }
    end

    cb(entries)
  end)
end

local function list_search_playlist_detail(playlist_id, cb)
  api.get_playlist_detail(playlist_id, function(playlist, songs, err)
    if err then
      cb(nil, err)
      return
    end

    local entries = {}
    for _, song in ipairs(songs or {}) do
      table.insert(entries, {
        key = tostring(song.id),
        kind = 'song',
        song = song,
        playlist = playlist,
        display = shared.format_song_display(song),
        keymap = song_keymap(),
        preview = function(_, done) shared.song_preview(song, done) end,
      })
    end

    if #entries == 0 then
      entries = {
        {
          key = 'empty',
          kind = 'info',
          display = lc.style.line { shared.dim 'This playlist has no songs' },
          keymap = search_keymap(),
          preview = function(_, done) done(shared.playlist_preview(playlist)) end,
        },
      }
    end

    cb(entries)
  end)
end

function M.list(path, cb)
  if #path == 2 then
    list_search_root(cb)
    return
  end

  local query = path[3]
  if not query or query == '' then
    list_search_root(cb)
    return
  end

  if #path == 3 then
    list_search_groups(query, cb)
    return
  end

  if path[4] == 'playlist' and path[5] then
    list_search_playlist_detail(path[5], cb)
    return
  end

  list_search_items(query, path[4], cb)
end

return M
