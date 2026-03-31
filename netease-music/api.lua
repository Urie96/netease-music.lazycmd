local M = {}

local config = require 'netease-music.config'

local state = {
  cache_prefix = 'netease-music:',
  cache_version = 0,
  cache = {},
  config_key = nil,
  cookie = nil,
  uid = nil,
}

local CACHE_NAMESPACE = 'netease-music.api'

local cache_ttl = {
  login_status = 60,
  personalized = 43200,
  top_playlists = 43200,
  my_playlists = 10800,
  liked_songs = 10800,
  song_details = 10800,
  like_check = 1800,
  recommend_playlists = 43200,
  daily_songs = 43200,
  playlist_meta = 10800,
  playlist_tracks = 10800,
  search = 86400,
  song_urls = 1800,
  lyric = 2592000,
}

local function urlencode(value)
  return tostring(value)
    :gsub('\n', '\r\n')
    :gsub('([^%w%-_%.~])', function(char) return string.format('%%%02X', string.byte(char)) end)
end

local function encode_query(params)
  local chunks = {}
  for key, value in pairs(params or {}) do
    if value ~= nil and value ~= '' then table.insert(chunks, urlencode(key) .. '=' .. urlencode(value)) end
  end
  table.sort(chunks)
  return table.concat(chunks, '&')
end

local function current_cfg() return config.get() end

local function config_key(cfg)
  return encode_query {
    base_url = cfg.base_url or '',
    uid = cfg.uid or '',
  }
end

local function ensure_cache_state()
  local cfg = current_cfg()
  local next_key = config_key(cfg)
  if state.config_key == next_key then return cfg end

  state.config_key = next_key
  state.cache_prefix = 'netease-music:' .. next_key .. ':'
  state.cache_version = 0
  state.cache = {}
  state.cookie = cfg.cookie or lc.cache.get('netease-music', 'cookie')
  state.uid = cfg.uid or lc.cache.get('netease-music', 'uid')
  return cfg
end

local function current_cookie()
  local cfg = ensure_cache_state()
  return cfg.cookie or state.cookie
end

local function current_uid()
  local cfg = ensure_cache_state()
  return cfg.uid or state.uid
end

local function set_cookie(cookie)
  local text = cookie and tostring(cookie):match '^%s*(.-)%s*$' or nil
  if not text or text == '' then return end
  state.cookie = text
  lc.cache.set('netease-music', 'cookie', text)
end

local function set_uid(uid)
  local text = uid and tostring(uid):match '^%s*(.-)%s*$' or nil
  if not text or text == '' then return end
  state.uid = text
  lc.cache.set('netease-music', 'uid', text)
end

local function make_cache_key(name, params)
  return state.cache_prefix .. tostring(state.cache_version) .. ':' .. name .. ':' .. encode_query(params)
end

local function cache_get(name, params)
  local key = make_cache_key(name, params)
  local cached = state.cache[key]
  if cached ~= nil then return cached end

  local persisted = lc.cache.get(CACHE_NAMESPACE, key)
  if persisted ~= nil then
    state.cache[key] = persisted
    return persisted
  end

  return nil, key
end

local function cache_set(key, value, ttl)
  state.cache[key] = value
  if ttl and ttl > 0 then
    lc.cache.set(CACHE_NAMESPACE, key, value, { ttl = ttl })
    return
  end
  lc.cache.set(CACHE_NAMESPACE, key, value)
end

local function cache_delete_by_name(name, params)
  local key = make_cache_key(name, params)
  state.cache[key] = nil
  lc.cache.delete(CACHE_NAMESPACE, key)
end

local function get_cached_json(name, params, ttl, loader, cb)
  local cached, key = cache_get(name, params)
  if cached ~= nil then
    cb(cached)
    return
  end

  loader(function(payload, err)
    if err then
      cb(nil, err)
      return
    end
    cache_set(key, payload, ttl)
    cb(payload)
  end)
end

local function request_json(endpoint, params, opt, cb)
  local cfg = ensure_cache_state()
  if not cfg.base_url or cfg.base_url == '' then
    cb(nil, '缺少 NeteaseCloudMusicApi 的 base_url 配置')
    return
  end

  if type(opt) == 'function' then
    cb = opt
    opt = {}
  end
  opt = opt or {}

  local query = lc.tbl_extend('force', {}, params or {})
  if not opt.no_cookie then
    local cookie = current_cookie()
    if cookie and cookie ~= '' then query.cookie = cookie end
  end

  local url = cfg.base_url .. endpoint
  local query_string = encode_query(query)
  if query_string ~= '' then url = url .. '?' .. query_string end

  lc.http.get(url, function(response)
    if not response.success then
      cb(nil, response.error or ('HTTP ' .. tostring(response.status)))
      return
    end

    local decode_ok, decoded = pcall(lc.json.decode, response.body or '')
    if not decode_ok then
      cb(nil, '解析网易云接口响应失败')
      return
    end

    local code = tonumber(decoded.code or 200)
    local allow_codes = opt.allow_codes or {}
    if code ~= 200 and not allow_codes[code] then
      cb(nil, decoded.message or decoded.msg or ('请求失败（' .. tostring(code) .. '）'))
      return
    end

    if opt.capture_cookie ~= false and decoded.cookie then set_cookie(decoded.cookie) end
    cb(decoded)
  end)
end

local function to_number(value)
  local n = tonumber(value)
  if n == nil then return 0 end
  return n
end

function M.ensure_configured()
  local cfg = ensure_cache_state()
  if not cfg.base_url or cfg.base_url == '' then return nil, '缺少 NeteaseCloudMusicApi 的 base_url 配置' end
  return true
end

function M.get_cookie() return current_cookie() end

function M.get_uid() return current_uid() end

function M.get_login_status(cb)
  get_cached_json('login-status', {}, cache_ttl.login_status, function(done) request_json('/login/status', {}, done) end, function(payload, err)
    if err then
      cb(nil, err)
      return
    end

    local data = payload.data or {}
    local profile = data.profile or {}
    if profile.userId then set_uid(profile.userId) end
    cb(data)
  end)
end

local function ensure_uid(cb)
  local uid = current_uid()
  if uid and uid ~= '' then
    cb(uid)
    return
  end

  M.get_login_status(function(data, err)
    if err then
      cb(nil, err)
      return
    end
    local profile = data and data.profile or {}
    if not profile or not profile.userId then
      cb(nil, '缺少 UID，请配置 uid 或使用 cookie 登录')
      return
    end
    cb(tostring(profile.userId))
  end)
end

function M.list_personalized_playlists(cb)
  local cfg = ensure_cache_state()
  local params = { limit = cfg.personalized_limit or 30 }
  get_cached_json('personalized', params, cache_ttl.personalized, function(done) request_json('/personalized', params, done) end, function(payload, err)
    if err then
      cb(nil, err)
      return
    end
    cb(payload.result or {})
  end)
end

function M.list_top_playlists(cb)
  local cfg = ensure_cache_state()
  local params = {
    limit = cfg.top_playlist_limit or 50,
    order = 'hot',
  }
  get_cached_json('top-playlists', params, cache_ttl.top_playlists, function(done) request_json('/top/playlist', params, done) end, function(payload, err)
    if err then
      cb(nil, err)
      return
    end
    cb(payload.playlists or {})
  end)
end

function M.list_my_playlists(cb)
  ensure_uid(function(uid, uid_err)
    if uid_err then
      cb(nil, uid_err)
      return
    end

    local cfg = ensure_cache_state()
    local params = {
      uid = uid,
      limit = cfg.my_playlist_limit or 100,
    }
    get_cached_json('my-playlists', params, cache_ttl.my_playlists, function(done) request_json('/user/playlist', params, done) end, function(payload, err)
      if err then
        cb(nil, err)
        return
      end
      cb(payload.playlist or {})
    end)
  end)
end

function M.list_recommend_playlists(cb)
  get_cached_json('recommend-playlists', {}, cache_ttl.recommend_playlists, function(done) request_json('/recommend/resource', {}, done) end, function(payload, err)
    if err then
      cb(nil, err)
      return
    end
    cb(payload.recommend or {})
  end)
end

function M.list_daily_songs(cb)
  get_cached_json('daily-songs', {}, cache_ttl.daily_songs, function(done) request_json('/recommend/songs', {}, done) end, function(payload, err)
    if err then
      cb(nil, err)
      return
    end
    local data = payload.data or {}
    M.apply_song_like_state(data.dailySongs or {}, function(songs) cb(songs or {}) end)
  end)
end

function M.get_song_details(ids, cb)
  local list = {}
  for _, id in ipairs(ids or {}) do
    if id ~= nil then table.insert(list, tostring(id)) end
  end
  if #list == 0 then
    cb({})
    return
  end

  local params = { ids = table.concat(list, ',') }
  get_cached_json('song-details', params, cache_ttl.song_details, function(done) request_json('/song/detail', params, done) end, function(payload, err)
    if err then
      cb(nil, err)
      return
    end
    cb(payload.songs or {})
  end)
end

function M.get_liked_song_ids(cb)
  ensure_uid(function(uid, uid_err)
    if uid_err then
      cb(nil, uid_err)
      return
    end

    local params = { uid = uid }
    get_cached_json('liked-songs', params, cache_ttl.liked_songs, function(done) request_json('/likelist', params, done) end, function(payload, err)
      if err then
        cb(nil, err)
        return
      end
      cb(payload.ids or {})
    end)
  end)
end

local function get_song_like_cache(song_id)
  local params = { id = tostring(song_id) }
  local key = make_cache_key('like-song', params)
  local cached = state.cache[key]
  if cached == nil then cached = lc.cache.get(CACHE_NAMESPACE, key) end
  if cached ~= nil then state.cache[key] = cached end
  return cached, key
end

local function set_song_like_cache(song_id, liked)
  local _, key = get_song_like_cache(song_id)
  cache_set(key, liked == true, cache_ttl.like_check)
end

function M.check_song_likes(ids, cb)
  local list = {}
  for _, id in ipairs(ids or {}) do
    if id ~= nil then table.insert(list, tostring(id)) end
  end
  if #list == 0 then
    cb({})
    return
  end

  local out = {}
  local missing = {}
  for _, id in ipairs(list) do
    local cached = get_song_like_cache(id)
    if cached ~= nil then
      out[id] = cached == true
    else
      out[id] = false
      table.insert(missing, id)
    end
  end

  if #missing == 0 then
    cb(out)
    return
  end

  local params = { ids = '[' .. table.concat(missing, ',') .. ']' }
  request_json('/song/like/check', params, function(payload, err)
    if err then
      cb(nil, err)
      return
    end

    local liked_ids = payload.ids
    if type(liked_ids) == 'table' and #liked_ids > 0 then
      local liked_set = {}
      for _, id in ipairs(liked_ids) do
        liked_set[tostring(id)] = true
      end
      for _, id in ipairs(missing) do
        local liked = liked_set[id] == true
        out[id] = liked
        set_song_like_cache(id, liked)
      end
      cb(out)
      return
    end

    local raw = payload.data or {}
    if #raw > 0 then
      for index, value in ipairs(raw) do
        local id = tostring(missing[index])
        local liked = value == true or value == 1
        out[id] = liked
        set_song_like_cache(id, liked)
      end
    else
      local seen = {}
      for key, value in pairs(raw or {}) do
        local id = tostring(key)
        local liked = value == true or value == 1
        out[id] = liked
        seen[id] = true
        set_song_like_cache(id, liked)
      end
      for _, id in ipairs(missing) do
        if not seen[id] then set_song_like_cache(id, false) end
      end
    end
    cb(out)
  end)
end

function M.apply_song_like_state(songs, cb)
  local ids = {}
  for _, song in ipairs(songs or {}) do
    if song and song.id ~= nil then table.insert(ids, song.id) end
  end
  if #ids == 0 then
    cb(songs or {})
    return
  end

  M.check_song_likes(ids, function(statuses, err)
    if err then
      cb(songs or {})
      return
    end

    for _, song in ipairs(songs or {}) do
      song.liked = statuses[tostring(song.id)] == true
    end
    cb(songs or {})
  end)
end

function M.list_liked_songs(cb)
  M.get_liked_song_ids(function(ids, err)
    if err then
      cb(nil, err)
      return
    end

    if #(ids or {}) == 0 then
      cb({})
      return
    end

    M.get_song_details(ids, function(songs, detail_err)
      if detail_err then
        cb(nil, detail_err)
        return
      end

      for _, song in ipairs(songs or {}) do
        song.liked = true
      end
      cb(songs or {})
    end)
  end)
end

local function invalidate_like_caches()
  ensure_cache_state()
  local uid = current_uid()
  if uid and uid ~= '' then
    cache_delete_by_name('liked-songs', { uid = uid })
  end
end

function M.set_song_like(song_id, like, cb)
  request_json('/like', {
    id = song_id,
    like = like ~= false and 'true' or 'false',
  }, function(payload, err)
    if err then
      cb(nil, err)
      return
    end

    invalidate_like_caches()
    set_song_like_cache(song_id, like)
    cb(payload or true)
  end)
end

function M.get_playlist_detail(playlist_id, cb)
  local params = { id = playlist_id }
  get_cached_json('playlist-meta', params, cache_ttl.playlist_meta, function(done) request_json('/playlist/detail', params, done) end, function(meta, meta_err)
    if meta_err then
      cb(nil, nil, meta_err)
      return
    end

    get_cached_json(
      'playlist-tracks',
      params,
      cache_ttl.playlist_tracks,
      function(done) request_json('/playlist/track/all', params, done) end,
      function(track_payload, track_err)
        if track_err then
          cb(nil, nil, track_err)
          return
        end

        M.apply_song_like_state(track_payload.songs or {}, function(songs)
          cb(meta.playlist or {}, songs or {})
        end)
      end
    )
  end)
end

function M.search(query, cb)
  local cfg = ensure_cache_state()
  local params = {
    keywords = query,
    song_limit = cfg.search_song_limit or 20,
    album_limit = cfg.search_album_limit or 20,
    artist_limit = cfg.search_artist_limit or 20,
    playlist_limit = cfg.search_playlist_limit or 20,
  }

  get_cached_json('search', params, cache_ttl.search, function(done)
    local result = {}
    local specs = {
      { key = 'song', type = 1, limit = params.song_limit, field = 'songs' },
      { key = 'album', type = 10, limit = params.album_limit, field = 'albums' },
      { key = 'artist', type = 100, limit = params.artist_limit, field = 'artists' },
      { key = 'playlist', type = 1000, limit = params.playlist_limit, field = 'playlists' },
    }

    local pending = #specs
    local failed = false
    for _, spec in ipairs(specs) do
      request_json('/cloudsearch', { keywords = query, type = spec.type, limit = spec.limit }, function(payload, err)
        if failed then return end
        if err then
          failed = true
          done(nil, err)
          return
        end

        local result_block = payload.result or {}
        result[spec.key] = result_block[spec.field] or {}
        pending = pending - 1
        if pending == 0 then
          M.apply_song_like_state(result.song or {}, function(songs)
            result.song = songs or {}
            done(result)
          end)
        end
      end)
    end
  end, cb)
end

function M.get_song_urls(ids, cb)
  local cfg = ensure_cache_state()
  local list = {}
  for _, id in ipairs(ids or {}) do
    if id ~= nil then table.insert(list, tostring(id)) end
  end
  if #list == 0 then
    cb({})
    return
  end

  local params = {
    id = table.concat(list, ','),
    level = cfg.quality or 'exhigh',
  }
  get_cached_json('song-urls', params, cache_ttl.song_urls, function(done) request_json('/song/url/v1', params, done) end, function(payload, err)
    if err then
      cb(nil, err)
      return
    end

    local urls = {}
    for _, item in ipairs(payload.data or {}) do
      urls[tostring(item.id)] = item
    end
    cb(urls)
  end)
end

function M.get_lyric(song_id, cb)
  local params = { id = song_id }
  get_cached_json('lyric', params, cache_ttl.lyric, function(done) request_json('/lyric', params, done) end, function(payload, err)
    if err then
      cb(nil, err)
      return
    end

    local lrc = payload.lrc or {}
    cb(lrc.lyric or '')
  end)
end

function M.playlist_track_count(playlist)
  return to_number(playlist.trackCount or playlist.subscribedCount or playlist.playCount or 0)
end

return M
