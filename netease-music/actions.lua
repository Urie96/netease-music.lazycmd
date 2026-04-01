local M = {}

local api = require 'netease-music.api'
local config = require 'netease-music.config'
local shared = require 'netease-music.shared'

local function hovered_entry() return lc.api.page_get_hovered() end

local function get_mpv()
  local ok, mod = pcall(require, 'mpv')
  if ok and mod then return mod end
  shared.show_error '需要先启用 mpv 插件：请在 lc.config.plugins 中加入 { dir = "plugins/mpv.lazycmd" }'
  return nil
end

local function player_preview(entry)
  local meta = entry.mpv_meta or {}
  local item = entry.player_item or {}
  local player = entry.player or {}
  local url = meta.url or item.filename or item.url or '-'

  return shared.preview_lines {
    lc.style.line { shared.okc 'mpv 队列' },
    '',
    shared.kv_line('状态', player.pause and '暂停' or '播放中', player.pause and 'warm' or 'accent'),
    shared.kv_line('当前播放', tostring(item.current == true or item.playing == true), 'accent'),
    shared.kv_line('标题', meta.title or item.title or '-'),
    shared.kv_line('歌手', meta.artist or '-'),
    shared.kv_line('专辑', meta.album or '-'),
    shared.kv_line('时长', shared.format_duration(meta.duration or 0), 'accent'),
    shared.kv_line('URL', url),
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
    liked = song.liked == true,
    url = url_info.url,
    source = 'netease-music',
    display = function(item, player, meta)
      local current = item.current or item.playing
      local marker = shared.dim '  '
      if current then marker = player.pause and shared.warm '⏸ ' or shared.okc '▶ ' end
      return lc.style.line {
        marker,
        meta.liked == true and shared.liked_icon() or shared.dim '  ',
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
      [keymap.search] = { callback = M.open_search_input, desc = '搜索音乐' },
      [keymap.toggle_like] = { callback = M.toggle_song_like_entry, desc = '切换喜欢状态' },
    },
  }
end

local function set_song_like_local(song_id, liked)
  local entries = lc.api.page_get_entries() or {}
  local path = lc.api.get_current_path() or {}
  local is_liked_page = path[1] == 'netease-music' and path[2] == 'liked'
  local next_entries = {}
  local updated = false
  for _, entry in ipairs(entries) do
    if entry.kind == 'song' and entry.song and tostring(entry.song.id) == tostring(song_id) then
      if is_liked_page and liked ~= true then
        updated = true
      else
        entry.song.liked = liked == true
        entry.display = shared.format_song_display(entry.song)
        table.insert(next_entries, entry)
        updated = true
      end
    elseif entry.mpv_meta and tostring(entry.mpv_meta.id) == tostring(song_id) then
      entry.mpv_meta.liked = liked == true
      table.insert(next_entries, entry)
      updated = true
    else
      table.insert(next_entries, entry)
    end
  end

  if not updated then return end

  if is_liked_page and #next_entries == 0 then
    next_entries = {
      {
        key = 'empty',
        kind = 'info',
        display = lc.style.line { shared.dim '还没有喜欢的歌曲' },
        preview = function(_, cb) cb(shared.preview_lines { '还没有喜欢的歌曲' }) end,
      },
    }
  end

  lc.api.page_set_entries(next_entries)
  local hovered = lc.api.page_get_hovered()
  if hovered and type(hovered.preview) == 'function' then
    hovered:preview(function(preview) lc.api.page_set_preview(preview) end)
  end
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
    prompt = '搜索网易云音乐',
    placeholder = '请输入关键词',
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

local function reload_account_page()
  lc.cmd 'reload'
end

local function qr_image_path(token)
  return '/tmp/lazycmd-netease-music-qr-' .. tostring(token or 'latest') .. '.png'
end

local function open_qr_in_browser(session)
  local qr_img = session and session.img or nil
  if not qr_img or qr_img == '' then error '二维码图片缺失' end

  local encoded = tostring(qr_img)
  encoded = encoded:gsub('^data:image/[^;]+;base64,', '')

  local image_path = qr_image_path(session and session.token)
  local decoded = lc.base64.decode(encoded)
  local ok, err = lc.fs.write_file_sync(image_path, decoded)
  if not ok then error('写入二维码图片失败: ' .. tostring(err)) end
  lc.system.open(image_path)
  return image_path
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
      reload_account_page()
      return
    end

    if not state or state.token ~= token then return end

    if state.status == 'success' then
      local profile = data and data.profile or {}
      local nickname = profile.nickname and ('：' .. tostring(profile.nickname)) or ''
      shared.show_info('二维码登录成功' .. nickname)
      reload_account_page()
      return
    end

    if state.status == 'expired' then
      shared.show_error(state.message or '二维码已过期')
      reload_account_page()
      return
    end

    if state.code ~= prev_code or state.status ~= prev_status or state.message ~= prev_message then
      reload_account_page()
    end
    lc.defer_fn(function() poll_qr_login(token) end, 1500)
  end)
end

function M.open_cookie_input()
  lc.input {
    prompt = '手动输入网易云 Cookie',
    placeholder = '粘贴完整 cookie，或至少包含 MUSIC_U=...',
    value = api.get_cookie() or '',
    on_submit = function(input)
      local cookie = tostring(input or ''):trim()
      if cookie == '' then
        shared.show_error 'Cookie 不能为空'
        return
      end

      api.save_cookie(cookie, function(data, err)
        if err then
          shared.show_error('Cookie 校验失败：' .. tostring(err))
          return
        end

        local profile = data and data.profile or {}
        local nickname = profile.nickname and ('：' .. tostring(profile.nickname)) or ''
        shared.show_info('Cookie 已保存' .. nickname)
        reload_account_page()
      end)
    end,
  }
end

function M.clear_saved_auth()
  lc.confirm {
    prompt = '清除当前保存的 Cookie / UID / 手机号？',
    on_confirm = function()
      api.clear_saved_auth()
      shared.show_info '已清除本地保存的登录凭证'
      reload_account_page()
    end,
  }
end

function M.open_sms_login()
  lc.input {
    prompt = '发送短信验证码',
    placeholder = '输入 11 位手机号，默认 +86',
    value = api.get_phone() or '',
    on_submit = function(phone_input)
      local phone = tostring(phone_input or ''):trim()
      if phone == '' then
        shared.show_error '手机号不能为空'
        return
      end

      api.send_login_captcha(phone, function(_, send_err)
        if send_err then
          shared.show_error(send_err)
          return
        end

        shared.show_info '验证码已发送'
        lc.input {
          prompt = '输入短信验证码',
          placeholder = '请输入收到的 4-6 位验证码',
          on_submit = function(code_input)
            local code = tostring(code_input or ''):trim()
            if code == '' then
              shared.show_error '验证码不能为空'
              return
            end

            api.login_with_captcha(phone, code, function(data, login_err)
              if login_err then
                shared.show_error(login_err)
                return
              end

              local profile = data and data.profile or {}
              local nickname = profile.nickname and ('：' .. tostring(profile.nickname)) or ''
              shared.show_info('短信登录成功' .. nickname)
              reload_account_page()
            end)
          end,
        }
      end)
    end,
  }
end

function M.open_qr_login()
  api.start_qr_login(function(session, err)
    if err then
      shared.show_error(err)
      reload_account_page()
      return
    end

    local ok, open_err = pcall(open_qr_in_browser, session)
    if not ok then
      shared.show_error('打开二维码失败：' .. tostring(open_err))
      reload_account_page()
      return
    end

    shared.show_info '已打开二维码图片，请在系统打开的应用中扫码'
    reload_account_page()
    lc.defer_fn(function() poll_qr_login(session.token) end, 1200)
  end)
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
      shared.show_error '当前选择中没有可播放的歌曲'
      return
    end

    mpv
      .play_tracks(tracks)
      :next(function()
        local msg = '已发送歌曲到 mpv 队列'
        if skipped and skipped > 0 then msg = msg .. ('（跳过 ' .. skipped .. ' 首）') end
        shared.show_info(msg)
        lc.cmd 'reload'
      end)
      :catch(function(play_err) shared.show_error(play_err) end)
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
      shared.show_error '当前歌曲不可播放'
      return
    end

    mpv
      .append_tracks(tracks)
      :next(function()
        shared.show_info '已追加歌曲到 mpv 队列'
        lc.cmd 'reload'
      end)
      :catch(function(append_err) shared.show_error(append_err) end)
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
        shared.show_error '这个歌单里没有可播放的歌曲'
        return
      end

      mpv
        .append_tracks(tracks)
        :next(function()
          local msg = '已追加歌单到 mpv 队列'
          if skipped and skipped > 0 then msg = msg .. ('（跳过 ' .. skipped .. ' 首）') end
          shared.show_info(msg)
          lc.cmd 'reload'
        end)
        :catch(function(append_err) shared.show_error(append_err) end)
    end)
  end)

  return true
end

function M.toggle_song_like_entry()
  local target = hovered_entry()
  if not target then return false end

  local song = nil
  if target.kind == 'song' and target.song then
    song = target.song
  elseif target.mpv_meta and target.mpv_meta.id then
    song = {
      id = target.mpv_meta.id,
      liked = target.mpv_meta.liked == true,
    }
  end

  if not song or not song.id then return false end

  local next_liked = song.liked ~= true
  set_song_like_local(song.id, next_liked)

  api.set_song_like(song.id, next_liked, function(_, err)
    if err then
      set_song_like_local(song.id, not next_liked)
      shared.show_error(err)
      return
    end

    shared.show_info(next_liked and '已加入我喜欢的音乐' or '已取消喜欢')
    lc.cmd 'reload'
  end)

  return true
end

return M
