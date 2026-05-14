local M = {}

local api = require 'netease-music.api'
local config = require 'netease-music.config'
local shared = require 'netease-music.shared'

M.name = 'netease-music'
M.title = '网易云音乐'

local function song_id(song) return tostring(song and (song.id or song.songId) or '') end

local function song_title(song)
  song = song or {}
  return song.name or song.title or ('#' .. song_id(song))
end

local function song_album(song)
  local album = song and (song.al or song.album) or {}
  if type(album) == 'table' then return album.name or album.title or '-' end
  return tostring(album or '-')
end

local function song_artists(song)
  song = song or {}
  local artists = song.ar or song.artists or song.artist or {}
  if type(artists) == 'string' then return artists end
  local names = {}
  for _, artist in ipairs(artists or {}) do
    table.insert(names, artist.name or artist.nickname or tostring(artist.id or '?'))
  end
  if #names == 0 and song.pc and song.pc.artist then return tostring(song.pc.artist) end
  return #names > 0 and table.concat(names, ', ') or '未知歌手'
end

local function normalize_track(song, extra)
  song = song or {}
  local duration_ms = tonumber(song.dt or song.duration or 0) or 0
  local out = {
    type = 'track',
    id = song_id(song),
    title = song_title(song),
    artist = song_artists(song),
    album = song_album(song),
    duration = duration_ms > 1000 and math.floor(duration_ms / 1000) or duration_ms,
    liked = song.liked == true,
    source = M.name,
    raw = song,
  }
  return deck.tbl_extend('force', out, extra or {})
end

local function normalize_playlist(playlist, extra)
  playlist = playlist or {}
  local creator = playlist.creator or {}
  local owner = type(creator) == 'table' and (creator.nickname or creator.userName or creator.userId) or creator
  local out = {
    type = 'playlist',
    id = tostring(playlist.id or ''),
    name = playlist.name or tostring(playlist.id or '歌单'),
    owner = owner,
    track_count = tonumber(playlist.trackCount or playlist.songCount or 0),
    description = playlist.description,
    play_count = tonumber(playlist.playCount or 0),
    source = M.name,
    raw = playlist,
  }
  return deck.tbl_extend('force', out, extra or {})
end

local function normalize_album(album, extra)
  album = album or {}
  local out = {
    type = 'album',
    id = tostring(album.id or ''),
    name = album.name or tostring(album.id or '专辑'),
    artist = song_artists { artists = album.artists or album.ar or {} },
    track_count = tonumber(album.size or album.songCount or 0),
    source = M.name,
    raw = album,
  }
  return deck.tbl_extend('force', out, extra or {})
end

local function normalize_artist(artist, extra)
  artist = artist or {}
  local out = {
    type = 'artist',
    id = tostring(artist.id or ''),
    name = artist.name or tostring(artist.id or '歌手'),
    album_count = tonumber(artist.albumSize or artist.albumCount or 0),
    source = M.name,
    raw = artist,
  }
  return deck.tbl_extend('force', out, extra or {})
end

local function map_items(items, mapper, extra)
  local out = {}
  for _, item in ipairs(items or {}) do
    table.insert(out, mapper(item, extra))
  end
  return out
end

local function append_all(target, items)
  for _, item in ipairs(items or {}) do
    table.insert(target, item)
  end
end

local function unique_playlists(playlists)
  local out, seen = {}, {}
  for _, playlist in ipairs(playlists or {}) do
    local id = tostring(playlist.id or '')
    if id ~= '' and not seen[id] then
      seen[id] = true
      table.insert(out, playlist)
    end
  end
  return out
end

local function qr_image_path(token)
  return '/tmp/lazydeck-netease-music-qr-' .. tostring(token or 'latest') .. '.png'
end

local function preview_lines(lines) return shared.preview_lines(lines) end

local function qr_preview_widget(qr)
  local image_path = qr and qr.img and qr_image_path(qr.token) or nil
  local text = preview_lines {
    deck.style.line { shared.accent '二维码登录' },
    '',
    shared.kv_line('当前状态', qr and (qr.message or qr.status) or '-', 'accent'),
    shared.kv_line('状态码', qr and qr.code and tostring(qr.code) or '-', 'warm'),
    shared.kv_line('二维码图片', qr and qr.img and '已生成' or '未生成', qr and qr.img and 'warm' or 'mag'),
    shared.kv_line('图片位置', image_path or '-', 'accent'),
    shared.kv_line('二维码内容', qr and qr.url and '已生成' or '未生成', qr and qr.url and 'warm' or 'mag'),
    qr and qr.url and qr.url ~= '' and '' or nil,
    qr and qr.url and qr.url ~= '' and deck.style.line { shared.warm '二维码地址' } or nil,
    qr and qr.url and qr.url ~= '' and deck.style.line { shared.titlec(qr.url) } or nil,
    '',
    deck.style.line { shared.dim '按回车生成新的二维码；扫码确认后自动保存 cookie。' },
  }

  if image_path then
    return {
      text,
      '',
      deck.style.line { shared.warm '二维码图片预览' },
      deck.style.image(image_path),
    }
  end
  return text
end

local function write_qr_image(session)
  local qr_img = session and session.img or nil
  if not qr_img or qr_img == '' then error '二维码图片缺失' end
  local encoded = tostring(qr_img):gsub('^data:image/[^;]+;base64,', '')
  local decoded = deck.base64.decode(encoded)
  local image_path = qr_image_path(session and session.token)
  local ok, err = deck.fs.write_file_sync(image_path, decoded)
  if not ok then error('写入二维码图片失败: ' .. tostring(err)) end
  return image_path
end

local function account_status_preview(data, err)
  local cfg = config.get()
  if err then
    return preview_lines {
      deck.style.line { shared.titlec '账号' },
      '',
      shared.kv_line('服务地址', cfg.base_url or '-', 'accent'),
      shared.kv_line('Cookie', api.get_cookie() and '已配置' or '未配置', api.get_cookie() and 'warm' or 'mag'),
      shared.kv_line('UID', api.get_uid() or '-', 'accent'),
      '',
      deck.style.line { shared.dim('登录状态不可用：' .. tostring(err)) },
    }
  end
  return shared.account_preview(data, cfg)
end

local function account_entries(cb)
  api.get_login_status(function(data, err)
    local login_keymap = {
      ['<enter>'] = { callback = M.open_qr_login, desc = '二维码登录' },
    }

    cb {
      {
        key = 'status',
        kind = 'info',
        display = deck.style.line {
          shared.titlec(data and data.profile and data.profile.nickname or '账号状态'),
          shared.dim '  ·  ',
          shared.dim(err and '离线' or '就绪'),
        },
        preview = function(_, done) done(account_status_preview(data, err)) end,
      },
      {
        key = 'login-qr',
        kind = 'action',
        display = deck.style.line {
          shared.accent '二维码登录',
          shared.dim '  ·  生成二维码并轮询登录状态',
        },
        preview = function(_, done) done(qr_preview_widget(api.get_qr_login_state())) end,
        keymap = login_keymap,
      },
    }
  end)
end

local function poll_qr_login(token)
  local current = api.get_qr_login_state()
  if current.token ~= token then return end

  local prev_status = current.status
  local prev_code = current.code
  local prev_message = current.message
  api.poll_qr_login(token, function(state, err, data)
    if err then
      shared.show_error(err)
      deck.cmd 'reload'
      return
    end
    if not state or state.token ~= token then return end

    if state.status == 'success' then
      local profile = data and data.profile or {}
      local nickname = profile.nickname and ('：' .. tostring(profile.nickname)) or ''
      shared.show_info('二维码登录成功' .. nickname)
      deck.cmd 'reload'
      return
    end

    if state.status == 'expired' then
      shared.show_error(state.message or '二维码已过期')
      deck.cmd 'reload'
      return
    end

    if state.code ~= prev_code or state.status ~= prev_status or state.message ~= prev_message then deck.cmd 'reload' end
    deck.defer_fn(function() poll_qr_login(token) end, 1500)
  end)
end

function M.open_qr_login()
  api.start_qr_login(function(session, err)
    if err then
      shared.show_error(err)
      deck.cmd 'reload'
      return
    end

    local ok, write_err = pcall(write_qr_image, session)
    if not ok then
      shared.show_error('生成二维码图片失败：' .. tostring(write_err))
      deck.cmd 'reload'
      return
    end

    shared.show_info '二维码已生成，请直接在预览区扫码'
    deck.cmd 'reload'
    deck.defer_fn(function() poll_qr_login(session.token) end, 1200)
  end)
end

M.extra_sections = {
  {
    key = 'account',
    title = '账号',
    icon = '',
    description = '二维码登录和账号状态',
    list = function(_, cb) account_entries(cb) end,
  },
}

function M.get_play_url(track, cb)
  api.get_song_urls({ track.id }, function(urls, err)
    if err then return cb(nil, err) end
    local item = urls and urls[tostring(track.id)] or nil
    cb(item and item.url or nil, nil)
  end)
end

function M.get_playlists(cb)
  api.list_my_playlists(function(playlists, err)
    if err then return cb(nil, err) end
    cb(map_items(playlists, normalize_playlist, { source_title = '我的歌单', list_source = 'my' }))
  end)
end

function M.get_playlist_tracks(playlist_id, cb)
  api.get_playlist_detail(playlist_id, function(playlist, songs, err)
    if err then return cb(nil, err) end
    cb(map_items(songs, normalize_track, {
      parent = normalize_playlist(playlist),
      list_source = 'playlist',
    }))
  end)
end

function M.get_recommend_playlists(cb)
  local collected = {}
  local pending = 3
  local failed = false

  local function done(items, err, extra)
    if failed then return end
    if err then
      failed = true
      cb(nil, err)
      return
    end
    append_all(collected, map_items(items, normalize_playlist, extra))
    pending = pending - 1
    if pending == 0 then cb(unique_playlists(collected)) end
  end

  api.list_recommend_playlists(function(items, err) done(items, err, { source_title = '每日推荐歌单', list_source = 'recommend' }) end)
  api.list_personalized_playlists(function(items, err) done(items, err, { source_title = '推荐歌单', list_source = 'personalized' }) end)
  api.list_top_playlists(function(items, err) done(items, err, { source_title = '热门歌单', list_source = 'top' }) end)
end

function M.get_recommend_tracks(cb)
  api.list_daily_songs(function(songs, err)
    if err then return cb(nil, err) end
    cb(map_items(songs, normalize_track, { source_title = '每日推荐歌曲', list_source = 'daily' }))
  end)
end

function M.get_liked_tracks(cb)
  api.list_liked_songs(function(songs, err)
    if err then return cb(nil, err) end
    cb(map_items(songs, normalize_track, { source_title = '我喜欢的音乐', list_source = 'liked' }))
  end)
end

function M.search(query, cb)
  api.search(query, function(result, err)
    if err then return cb(nil, err) end
    cb {
      tracks = map_items((result or {}).song, normalize_track, { list_source = 'search', query = query }),
      albums = map_items((result or {}).album, normalize_album, { list_source = 'search', query = query }),
      artists = map_items((result or {}).artist, normalize_artist, { list_source = 'search', query = query }),
      playlists = map_items((result or {}).playlist, normalize_playlist, { list_source = 'search', query = query }),
    }
  end)
end

function M.set_track_liked(track, liked, cb)
  api.set_song_like(track.id, liked == true, function(payload, err) cb(payload or true, err) end)
end

return M
