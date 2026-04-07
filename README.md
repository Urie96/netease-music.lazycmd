# netease-music.lazycmd

网易云音乐插件，基于 `NeteaseCloudMusicApi` 提供浏览、搜索、歌词预览，以及把歌曲/歌单投递到 `mpv.lazycmd` 队列播放。

## 功能

- 一级目录显示：
  - `账号`：查看 `base_url` / `cookie` / `uid` 配置和登录状态，并支持短信验证码登录、二维码登录、手动输入 Cookie、清除本地凭证
  - `每日推荐歌单`：每日推荐歌单，需要登录
  - `每日推荐歌曲`：每日推荐歌曲，需要登录
  - `我的歌单`：用户歌单，需要 `uid` 或可用登录态
  - `我喜欢的音乐`：我喜欢的歌曲列表，需要登录
  - `推荐歌单`：推荐歌单
  - `热门歌单`：热门歌单
  - `搜索`：搜索歌曲、专辑、歌手、歌单
- 歌单页支持进入查看歌曲列表
- 歌曲预览会显示基础元数据，并尝试加载歌词前几行
- 歌曲条目会显示喜欢状态；按 `l` 可切换喜欢/取消喜欢
- 在歌曲上按 `Enter`：从当前歌曲开始替换 `mpv` 队列并播放
- 在歌曲上按 `a`：把当前歌曲追加到 `mpv` 队列
- 在歌单上按 `A`：把整个歌单追加到 `mpv` 队列
- 投递到 `mpv` 时使用 `get_play_url(track, cb)` 延迟解析真实播放链接，避免长队列里的签名链接提前过期

## 配置

先准备一个运行中的 `NeteaseCloudMusicApi` 服务，例如默认的 `http://127.0.0.1:3000`。

```lua
{
  dir = 'plugins/mpv.lazycmd',
  config = function()
    require('mpv').setup {
      socket = '/tmp/lazycmd-mpv.sock',
    }
  end,
},
{
  dir = 'plugins/netease-music.lazycmd',
  config = function()
    require('netease-music').setup {
      base_url = os.getenv 'NETEASE_MUSIC_API_URL',
      quality = 'exhigh',

      personalized_limit = 30,
      top_playlist_limit = 50,
      my_playlist_limit = 100,
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

插件只接受 `base_url` 这类非敏感配置。`cookie` 不再通过 `setup()` 或环境变量传入；如果你在 `账号` 页面完成短信验证码登录、二维码登录，或手动录入 Cookie，插件会把 `cookie`、`uid` 和最近一次使用的手机号都保存到 `lc.secrets`。

## 登录

在 `账号` 页面里，当前支持三种登录相关流程：

- `短信验证码登录`
  - 先输入手机号，插件调用 `/captcha/sent`
  - 再输入验证码，插件调用 `/login/cellphone`
  - 登录成功后会保存返回的 `cookie`
- `二维码登录`
  - 插件调用 `/login/qr/key` 和 `/login/qr/create`
  - 将接口返回的二维码 base64 图片解码后写入临时 PNG 文件，并用系统默认应用打开
  - 后台轮询 `/login/qr/check`，扫码确认成功后自动保存 `cookie`
- `手动输入 Cookie`
  - 适合从浏览器复制完整 Cookie，或只复制 `MUSIC_U=...`
  - 保存后插件会立刻调用 `/login/status` 校验登录态并同步 `uid`

登录相关信息通过 `lc.secrets` 保存，包括 `cookie`、`uid` 和最近一次使用的手机号。这样多台机器如果共享同一份 secrets，就可以复用登录态；后续即使 Cookie 失效，插件仍可尝试用保存下来的 `uid` 展示用户歌单。

## 依赖

- `NeteaseCloudMusicApi`
- `mpv.lazycmd`

## 接口

当前实现使用这些 API：

- `/login/status`
- `/captcha/sent`
- `/login/cellphone`
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
- `/cloudsearch`
- `/song/url/v1`
- `/lyric`

## 说明

- 这个插件目前聚焦“浏览 + 搜索 + 播放”主流程；已支持喜欢/取消喜欢、短信验证码登录、二维码登录、手动 Cookie 登录，但还没有实现歌单编辑等写操作
- `每日推荐歌单`、`每日推荐歌曲`、`我的歌单` 是否可用，取决于接口服务端是否接受当前 `cookie`
- API 响应会同时走内存缓存和 `lc.cache` 持久化缓存，TTL 按接口性质区分：登录态 60 秒，公开推荐/热门歌单 12 小时，我的歌单 3 小时，每日推荐 12 小时，歌单详情 3 小时，搜索 1 天，播放 URL 30 分钟，歌词 30 天
- `mpv.lazycmd` 会为延迟解析的 track 生成插件内部 localhost URL；每次开始请求某首歌时，网易云插件才会现取最新播放链接
