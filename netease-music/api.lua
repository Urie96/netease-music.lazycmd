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
  return state.cache_prefix .. state.cache_version .. ':' .. name .. ':' .. encode_query(params)
end

local function get_cached_json(name, params, loader, cb)
  local key = make_cache_key(name, params)
  local cached = state.cache[key]
  if cached ~= nil then
    cb(cached)
    return
  end

  loader(function(payload, err)
    if err then
      cb(nil, err)
      return
    end
    state.cache[key] = payload
    cb(payload)
  end)
end

local function request_json(endpoint, params, opt, cb)
  local cfg = ensure_cache_state()
  if not cfg.base_url or cfg.base_url == '' then
    cb(nil, 'missing NeteaseCloudMusicApi base_url')
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
  if opt.timestamp ~= false then query.timestamp = tostring(os.time()) end

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
      cb(nil, 'failed to decode Netease response')
      return
    end

    local code = tonumber(decoded.code or 200)
    local allow_codes = opt.allow_codes or {}
    if code ~= 200 and not allow_codes[code] then
      cb(nil, decoded.message or decoded.msg or ('request failed (' .. tostring(code) .. ')'))
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
  if not cfg.base_url or cfg.base_url == '' then return nil, 'missing NeteaseCloudMusicApi base_url' end
  return true
end

function M.invalidate_cache()
  state.cache_version = state.cache_version + 1
  state.cache = {}
end

function M.get_cookie() return current_cookie() end

function M.get_uid() return current_uid() end

function M.get_login_status(cb)
  request_json('/login/status', {}, function(payload, err)
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
      cb(nil, 'missing uid, configure uid or login with cookie')
      return
    end
    cb(tostring(profile.userId))
  end)
end

function M.list_personalized_playlists(cb)
  local cfg = ensure_cache_state()
  local params = { limit = cfg.personalized_limit or 30 }
  get_cached_json('personalized', params, function(done) request_json('/personalized', params, done) end, function(payload, err)
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
  get_cached_json('top-playlists', params, function(done) request_json('/top/playlist', params, done) end, function(payload, err)
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
    get_cached_json('my-playlists', params, function(done) request_json('/user/playlist', params, done) end, function(payload, err)
      if err then
        cb(nil, err)
        return
      end
      cb(payload.playlist or {})
    end)
  end)
end

function M.list_recommend_playlists(cb)
  get_cached_json('recommend-playlists', {}, function(done) request_json('/recommend/resource', {}, done) end, function(payload, err)
    if err then
      cb(nil, err)
      return
    end
    cb(payload.recommend or {})
  end)
end

function M.list_daily_songs(cb)
  get_cached_json('daily-songs', {}, function(done) request_json('/recommend/songs', {}, done) end, function(payload, err)
    if err then
      cb(nil, err)
      return
    end
    local data = payload.data or {}
    cb(data.dailySongs or {})
  end)
end

function M.get_playlist_detail(playlist_id, cb)
  local params = { id = playlist_id }
  get_cached_json('playlist-meta', params, function(done) request_json('/playlist/detail', params, done) end, function(meta, meta_err)
    if meta_err then
      cb(nil, nil, meta_err)
      return
    end

    get_cached_json(
      'playlist-tracks',
      params,
      function(done) request_json('/playlist/track/all', params, done) end,
      function(track_payload, track_err)
        if track_err then
          cb(nil, nil, track_err)
          return
        end

        cb(meta.playlist or {}, track_payload.songs or {})
      end
    )
  end)
end

function M.search(query, cb)
  local cfg = ensure_cache_state()
  local result = {}

  local specs = {
    { key = 'song', type = 1, limit = cfg.search_song_limit or 20, field = 'songs' },
    { key = 'album', type = 10, limit = cfg.search_album_limit or 20, field = 'albums' },
    { key = 'artist', type = 100, limit = cfg.search_artist_limit or 20, field = 'artists' },
    { key = 'playlist', type = 1000, limit = cfg.search_playlist_limit or 20, field = 'playlists' },
  }

  local pending = #specs
  local failed = false
  for _, spec in ipairs(specs) do
    request_json('/cloudsearch', { keywords = query, type = spec.type, limit = spec.limit }, function(payload, err)
      if failed then return end
      if err then
        failed = true
        cb(nil, err)
        return
      end

      local result_block = payload.result or {}
      result[spec.key] = result_block[spec.field] or {}
      pending = pending - 1
      if pending == 0 then cb(result) end
    end)
  end
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
  request_json('/song/url/v1', params, function(payload, err)
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
  get_cached_json('lyric', params, function(done) request_json('/lyric', params, done) end, function(payload, err)
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
