local M = {}

local cfg = {
  base_url = os.getenv 'NETEASE_MUSIC_API_URL' or 'http://127.0.0.1:3000',
  cookie = os.getenv 'NETEASE_MUSIC_COOKIE',
  uid = os.getenv 'NETEASE_MUSIC_UID',
  quality = 'exhigh',
  personalized_limit = 30,
  top_playlist_limit = 50,
  my_playlist_limit = 100,
  daily_song_limit = 100,
  search_song_limit = 20,
  search_album_limit = 20,
  search_artist_limit = 20,
  search_playlist_limit = 20,
  keymap = {
    append_to_player = 'a',
    append_playlist_to_player = 'A',
    search = 's',
    play_now = '<enter>',
  },
}

local function trim(value)
  if value == nil then return nil end
  local text = tostring(value):match '^%s*(.-)%s*$'
  if text == '' then return nil end
  return text
end

local function normalize(next_cfg)
  local out = next_cfg
  out.base_url = trim(out.base_url)
  out.cookie = trim(out.cookie)
  out.uid = trim(out.uid)
  out.quality = trim(out.quality) or 'exhigh'

  if out.base_url then out.base_url = out.base_url:gsub('/+$', '') end

  return out
end

function M.setup(opt)
  local global_keymap = lc.config.get().keymap
  cfg = normalize(lc.tbl_deep_extend('force', cfg, { keymap = global_keymap }, opt or {}))
end

function M.get() return cfg end

return M
