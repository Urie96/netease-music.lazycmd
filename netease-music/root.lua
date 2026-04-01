local M = {}

local actions = require 'netease-music.actions'
local api = require 'netease-music.api'
local config = require 'netease-music.config'
local shared = require 'netease-music.shared'

local function section_entry(key, title, color, subtitle)
  return {
    key = key,
    kind = 'section',
    display = lc.style.line { color(title) },
    preview = function(_, cb)
      cb(shared.preview_lines {
        lc.style.line { color(title) },
        '',
        lc.style.line { shared.dim(subtitle) },
      })
    end,
  }
end

local function qr_image_path(token)
  return '/tmp/lazycmd-netease-music-qr-' .. tostring(token or 'latest') .. '.png'
end

local function account_entries(cb)
  api.get_login_status(function(data, err)
    local cfg = config.get()
    local action_keymap = function(callback, desc)
      local keymap = {}
      if cfg.keymap.enter then keymap[cfg.keymap.enter] = { callback = callback, desc = desc } end
      if cfg.keymap.open and cfg.keymap.open ~= cfg.keymap.enter then
        keymap[cfg.keymap.open] = { callback = callback, desc = desc }
      end
      return keymap
    end

    local function build_status_preview()
      if err then
        return shared.preview_lines {
          lc.style.line { shared.titlec '账号' },
          '',
          shared.kv_line('服务地址', cfg.base_url or '-', 'accent'),
          shared.kv_line('Cookie', api.get_cookie() and '已配置' or '未配置', api.get_cookie() and 'warm' or 'mag'),
          shared.kv_line('UID', api.get_uid() or '-', 'accent'),
          '',
          lc.style.line { shared.dim('登录状态不可用：' .. tostring(err)) },
        }
      end
      return shared.account_preview(data, cfg)
    end

    cb {
      {
        key = 'status',
        kind = 'info',
        display = lc.style.line {
          shared.titlec(data and data.profile and data.profile.nickname or '账号状态'),
          shared.dim '  ·  ',
          shared.dim(err and '离线' or '就绪'),
        },
        keymap = {
          [config.get().keymap.search] = { callback = actions.open_search_input, desc = '搜索音乐' },
        },
        preview = function(_, done) done(build_status_preview()) end,
      },
      {
        key = 'login-sms',
        kind = 'action',
        display = lc.style.line {
          shared.okc '短信验证码登录',
          shared.dim '  ·  发送验证码并完成登录',
        },
        preview = function(_, done)
          done(shared.preview_lines {
            lc.style.line { shared.okc '短信验证码登录' },
            '',
            shared.kv_line('当前手机号', api.get_phone() or '-', 'accent'),
            shared.kv_line('当前 Cookie', api.get_cookie() and '已保存' or '未保存', api.get_cookie() and 'warm' or 'mag'),
            '',
            lc.style.line { shared.dim '输入手机号后，插件会调用 /captcha/sent 和 /login/cellphone 完成登录。' },
          })
        end,
        keymap = action_keymap(actions.open_sms_login, '短信验证码登录'),
      },
      {
        key = 'login-qr',
        kind = 'action',
        display = lc.style.line {
          shared.accent '二维码登录',
          shared.dim '  ·  打开二维码图片并轮询登录状态',
        },
        preview = function(_, done)
          local qr = api.get_qr_login_state()
          done(shared.preview_lines {
            lc.style.line { shared.accent '二维码登录' },
            '',
            shared.kv_line('当前状态', qr.message or qr.status or '-', 'accent'),
            shared.kv_line('状态码', qr.code and tostring(qr.code) or '-', 'warm'),
            shared.kv_line('二维码图片', qr.img and '已生成' or '未生成', qr.img and 'warm' or 'mag'),
            shared.kv_line('图片位置', qr.img and qr_image_path(qr.token) or '-', 'accent'),
            shared.kv_line('二维码内容', qr.url and '已生成' or '未生成', qr.url and 'warm' or 'mag'),
            '',
            lc.style.line { shared.dim '会生成新的二维码图片并尝试用系统默认应用打开；成功扫码后自动保存 cookie。' },
          })
        end,
        keymap = action_keymap(actions.open_qr_login, '二维码登录'),
      },
      {
        key = 'login-cookie',
        kind = 'action',
        display = lc.style.line {
          shared.warm '手动输入 Cookie',
          shared.dim '  ·  适合从浏览器复制 MUSIC_U',
        },
        preview = function(_, done)
          done(shared.preview_lines {
            lc.style.line { shared.warm '手动输入 Cookie' },
            '',
            shared.kv_line('当前 Cookie', api.get_cookie() and '已保存' or '未保存', api.get_cookie() and 'warm' or 'mag'),
            '',
            lc.style.line { shared.dim '支持粘贴完整 Cookie；如果只包含 MUSIC_U=... 也可以。保存后会立即校验登录态。' },
          })
        end,
        keymap = action_keymap(actions.open_cookie_input, '手动输入 Cookie'),
      },
      {
        key = 'clear-auth',
        kind = 'action',
        display = lc.style.line {
          shared.mag '清除本地凭证',
          shared.dim '  ·  删除 secrets 中保存的 cookie 和手机号',
        },
        preview = function(_, done)
          done(shared.preview_lines {
            lc.style.line { shared.mag '清除本地凭证' },
            '',
            lc.style.line { shared.dim '会删除插件通过 lc.secrets 保存的 cookie 和手机号。setup() 或环境变量中的配置不会被改动。' },
          })
        end,
        keymap = action_keymap(actions.clear_saved_auth, '清除本地凭证'),
      },
    }
  end)
end

local sections = {
  {
    key = 'account',
    title = '账号',
    subtitle = '登录状态、Cookie 和 UID',
    color = shared.accent,
  },
  {
    key = 'recommend',
    title = '每日推荐歌单',
    subtitle = 'recommend/resource，需要登录',
    color = shared.okc,
  },
  {
    key = 'daily',
    title = '每日推荐歌曲',
    subtitle = 'recommend/songs，需要登录',
    color = shared.warm,
  },
  {
    key = 'my',
    title = '我的歌单',
    subtitle = 'user/playlist，需要 UID 或登录态',
    color = shared.mag,
  },
  {
    key = 'liked',
    title = '我喜欢的音乐',
    subtitle = 'likelist + song/detail，需要登录',
    color = shared.accent,
  },
  {
    key = 'personalized',
    title = '推荐歌单',
    subtitle = '公开推荐歌单',
    color = shared.okc,
  },
  {
    key = 'top',
    title = '热门歌单',
    subtitle = 'top/playlist 热门歌单',
    color = shared.warm,
  },
  {
    key = 'search',
    title = '搜索',
    subtitle = '歌曲、专辑、歌手、歌单',
    color = shared.titlec,
  },
}

local function list_daily_songs(cb)
  local playlist = require 'netease-music.playlist'
  api.list_daily_songs(function(songs, err)
    if err then
      cb(nil, err)
      return
    end

    local entries = {}
    for _, song in ipairs(songs or {}) do
        table.insert(entries, playlist.build_song_entry(song, {
          id = 'daily-songs',
        name = '每日推荐歌曲',
      }))
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

  if section == 'liked' then
    require('netease-music.playlist').list_liked_songs_entries(cb)
    return
  end

  if section == 'search' then
    require('netease-music.search').list(path, cb)
    return
  end

  require('netease-music.playlist').list(path, cb)
end

return M
