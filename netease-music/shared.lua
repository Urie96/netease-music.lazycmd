local M = {}

local api = require 'netease-music.api'

function M.dim(text) return lc.style.span(tostring(text or '')):fg 'blue' end
function M.accent(text) return lc.style.span(tostring(text or '')):fg 'cyan' end
function M.warm(text) return lc.style.span(tostring(text or '')):fg 'yellow' end
function M.okc(text) return lc.style.span(tostring(text or '')):fg 'green' end
function M.mag(text) return lc.style.span(tostring(text or '')):fg 'magenta' end
function M.titlec(text) return lc.style.span(tostring(text or '')):fg 'white' end
function M.liked_icon() return lc.style.span(' '):fg 'red' end

local function aligned_line(line) return { line = line, align = true } end

function M.preview_lines(lines)
  local out, aligned = {}, {}
  for _, line in ipairs(lines or {}) do
    local item = line
    local should_align = false

    if type(line) == 'table' and line.line ~= nil then
      item = line.line
      should_align = line.align == true
    elseif type(line) == 'string' or type(line) == 'number' or type(line) == 'boolean' or line == nil then
      item = lc.style.line { lc.style.span(tostring(line or '')) }
    end

    table.insert(out, item)
    if should_align then table.insert(aligned, item) end
  end

  if #aligned > 0 then lc.style.align_columns(aligned) end
  return lc.style.text(out)
end

function M.kv_line(label, value, label_color)
  local label_span = lc.style.span(tostring(label or ''))
  if label_color == 'accent' then
    label_span = label_span:fg 'cyan'
  elseif label_color == 'warm' then
    label_span = label_span:fg 'yellow'
  elseif label_color == 'mag' then
    label_span = label_span:fg 'magenta'
  else
    label_span = label_span:fg 'blue'
  end

  return aligned_line(lc.style.line {
    label_span,
    M.dim ': ',
    M.titlec(value or '-'),
  })
end

function M.show_error(err)
  lc.notify(lc.style.line {
    lc.style.span('网易云音乐：'):fg 'red',
    lc.style.span(tostring(err)):fg 'red',
  })
end

function M.show_info(msg)
  lc.notify(lc.style.line {
    lc.style.span('网易云音乐：'):fg 'cyan',
    lc.style.span(tostring(msg)):fg 'white',
  })
end

function M.format_duration(ms)
  local n = tonumber(ms or 0)
  if not n or n <= 0 then return '--:--' end
  local seconds = math.floor(n / 1000)
  local h = math.floor(seconds / 3600)
  local m = math.floor((seconds % 3600) / 60)
  local s = seconds % 60
  if h > 0 then return string.format('%d:%02d:%02d', h, m, s) end
  return string.format('%d:%02d', m, s)
end

function M.song_id(song) return tostring(song.id or song.songId or '') end

function M.song_title(song) return song.name or song.title or ('#' .. M.song_id(song)) end

function M.song_album(song)
  local album = song.al or song.album or {}
  if type(album) == 'table' then return album.name or album.title or '-' end
  return tostring(album or '-')
end

function M.song_artists(song)
  local artists = song.ar or song.artists or song.artist or {}
  if type(artists) == 'string' then return artists end
  local names = {}
  for _, artist in ipairs(artists or {}) do
    table.insert(names, artist.name or artist.nickname or tostring(artist.id or '?'))
  end
  if #names == 0 and song.pc and song.pc.artist then return tostring(song.pc.artist) end
  return #names > 0 and table.concat(names, ', ') or '未知歌手'
end

function M.playlist_creator_name(playlist)
  local creator = playlist.creator or {}
  if type(creator) == 'table' then return creator.nickname or creator.userName or creator.userId or '-' end
  return tostring(creator or '-')
end

function M.format_song_display(song)
  return lc.style.line {
    song.liked == true and M.liked_icon() or M.dim '  ',
    M.titlec(M.song_title(song)),
    M.dim '  [',
    M.accent(M.song_artists(song)),
    M.dim ']',
  }
end

function M.format_playlist_display(playlist)
  return lc.style.line { M.warm(playlist.name or playlist.id or '歌单') }
end

function M.format_artist_display(artist)
  return lc.style.line {
    M.mag(artist.name or artist.id or '歌手'),
    artist.alias and #artist.alias > 0 and M.dim('  ·  ' .. table.concat(artist.alias, ' / ')) or '',
  }
end

function M.format_album_display(album)
  local artist = M.song_artists { artists = album.artists or album.ar or {} }
  return lc.style.line {
    M.warm(album.name or album.id or '专辑'),
    M.dim '  ·  ',
    M.accent(artist),
  }
end

function M.song_preview(song, cb)
  api.get_lyric(song.id, function(lyric, err)
    local lyric_lines = {}
    if lyric and lyric ~= '' then
      local count = 0
      for line in tostring(lyric):gmatch '[^\r\n]+' do
        local text = line:gsub('%b[]', ''):match '^%s*(.-)%s*$'
        if text ~= '' then
          table.insert(lyric_lines, text)
          count = count + 1
          if count >= 8 then break end
        end
      end
    end

    local lines = {
      lc.style.line { M.titlec(M.song_title(song)) },
      '',
      M.kv_line('歌手', M.song_artists(song), 'accent'),
      M.kv_line('专辑', M.song_album(song), 'warm'),
      M.kv_line('时长', M.format_duration(song.dt or song.duration), 'accent'),
      M.kv_line('喜欢', tostring(song.liked == true), song.liked == true and 'warm' or 'mag'),
      M.kv_line('歌曲 ID', tostring(song.id or '-')),
    }

    if err then
      table.insert(lines, '')
      table.insert(lines, lc.style.line { M.dim('歌词不可用：' .. tostring(err)) })
    elseif #lyric_lines > 0 then
      table.insert(lines, '')
      table.insert(lines, lc.style.line { M.accent '歌词' })
      for _, line in ipairs(lyric_lines) do
        table.insert(lines, line)
      end
    end

    cb(M.preview_lines(lines))
  end)
end

function M.playlist_preview(playlist)
  return M.preview_lines {
    lc.style.line { M.warm(playlist.name or '歌单') },
    '',
    M.kv_line('歌曲数', tostring(playlist.trackCount or playlist.songCount or 0) .. ' 首', 'accent'),
    M.kv_line('播放次数', tostring(playlist.playCount or '-'), 'warm'),
    M.kv_line('收藏数', tostring(playlist.subscribedCount or '-'), 'mag'),
    '',
    lc.style.line { M.dim(playlist.description or '暂无简介') },
  }
end

function M.account_preview(data, cfg)
  local profile = data and data.profile or {}
  local account = data and data.account or {}
  return M.preview_lines {
    lc.style.line { M.titlec '账号' },
    '',
    M.kv_line('服务地址', cfg.base_url or '-', 'accent'),
    M.kv_line('Cookie', api.get_cookie() and '已配置' or '未配置', api.get_cookie() and 'warm' or 'mag'),
    M.kv_line('手机号', api.get_phone() or '-', 'accent'),
    M.kv_line('UID', api.get_uid() or '-', 'accent'),
    M.kv_line('昵称', profile.nickname or '-', 'warm'),
    M.kv_line('用户 ID', tostring(profile.userId or account.id or '-'), 'accent'),
    '',
    lc.style.line { M.dim '可在此页直接进行短信验证码登录，或手动录入 Cookie。敏感凭证会保存在 lc.secrets。' },
  }
end

function M.current_song_entries()
  local entries = lc.api.page_get_entries() or {}
  local songs = {}
  for _, entry in ipairs(entries) do
    if entry.kind == 'song' and entry.song then table.insert(songs, entry.song) end
  end
  return songs, entries
end

return M
