# netease-music.lazydeck

网易云音乐 provider 插件，基于 `NeteaseCloudMusicApi` 提供标准化音乐数据；通用浏览、预览、搜索、推荐和播放队列由 `music.lazydeck` 提供。

## 功能

- 一级目录由 `music.lazydeck` 根据 provider 能力自动生成：
  - `Now Playing`：当前播放队列
  - `Playlists`：我的歌单，需要 UID 或可用登录态
  - `Recommendations`：推荐歌单 / 热门歌单 / 每日推荐歌曲
  - `Liked`：我喜欢的音乐，需要登录
  - `Search`：搜索歌曲、专辑、歌手、歌单；搜索结果中的歌单、专辑、歌手可继续进入查看歌曲
  - `账号`：网易云二维码登录和账号状态（provider `extra_sections`）
- 歌单页支持进入查看歌曲列表
- 歌手搜索结果支持进入专辑列表，再进入查看歌曲列表
- 歌曲预览统一使用 `music.lazydeck` 的通用 preview，不再加载歌词
- 歌曲条目会显示喜欢状态；按 `l` 可切换喜欢/取消喜欢
- 在歌曲上按 `Enter`：从当前歌曲开始替换 `/music` 队列并播放
- 在歌曲上按 `a`：把当前歌曲追加到 `/music` 队列
- 在歌单上按 `A`：把整个歌单追加到 `/music` 队列
- 投递到播放器时使用 `get_play_url(track, cb)` 延迟解析真实播放链接，避免长队列里的签名链接提前过期

## 配置

先准备一个运行中的 `NeteaseCloudMusicApi` 服务，例如默认的 `http://127.0.0.1:3000`。

```lua
{
  dir = 'plugins/music.lazydeck',
  config = function()
    require('music').setup {
      -- socket = (os.getenv 'TMPDIR' or '/tmp') .. '/lazydeck-mpv.sock', -- 默认值
    }
  end,
},
{
  dir = 'plugins/netease-music.lazydeck',
  config = function()
    require('netease-music').setup {
      base_url = os.getenv 'NETEASE_MUSIC_API_URL',
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
        toggle_like = 'l',
        play_now = '<enter>',
      },
    }
  end,
},
```

## 环境变量

- `NETEASE_MUSIC_API_URL`

插件只接受 `base_url` 这类非敏感配置。`cookie` 不通过 `setup()` 或环境变量传入；在 `账号` 页面完成二维码登录后，插件会把 `cookie` 和 `uid` 保存到 `deck.secrets`。

## 登录

重构后只保留二维码登录：

- 插件调用 `/login/qr/key` 和 `/login/qr/create`
- 将接口返回的二维码 base64 图片解码后写入临时 PNG 文件
- 在预览区展示二维码图片地址、二维码内容地址，以及通过 `deck.style.image(...)` 渲染的二维码图片预览
- 后台轮询 `/login/qr/check`，扫码确认成功后自动保存 `cookie`

## 依赖

- `NeteaseCloudMusicApi`
- `music.lazydeck`

## 接口

当前主要使用这些 API：

- `/login/status`
- `/login/qr/key`
- `/login/qr/create`
- `/login/qr/check`
- `/personalized`
- `/top/playlist`
- `/user/playlist`
- `/likelist`
- `/song/detail`
- `/song/like/check`
- `/like`
- `/recommend/resource`
- `/recommend/songs`
- `/playlist/detail`
- `/playlist/track/all`
- `/album`
- `/artist/album`
- `/cloudsearch`
- `/song/url/v1`

## 结构

- `netease-music/init.lua`: 配置检查，并把请求委托给 `music.new(provider)` 创建的 browser
- `netease-music/provider.lua`: 网易云数据标准化和 `music.lazydeck` provider 接口实现；包含二维码登录 extra section
- `netease-music/api.lua`: NeteaseCloudMusicApi 请求、缓存、登录态和 secrets 管理
- `netease-music/config.lua`: 配置归一化
- `netease-music/shared.lua`: 账号二维码登录页仍复用的基础样式和 preview helper

重构后旧 UI/action 模块已删除，浏览、预览、搜索、推荐和播放动作统一由 `music.lazydeck` 提供。
