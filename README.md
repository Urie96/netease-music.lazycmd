# netease-music.lazycmd

网易云音乐插件，基于 `NeteaseCloudMusicApi` 提供浏览、搜索、歌词预览，以及把歌曲/歌单投递到 `mpv.lazycmd` 队列播放。

## 功能

- 一级目录显示：
  - `账号`：查看 `base_url` / `cookie` / `uid` 配置和登录状态
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
      cookie = os.getenv 'NETEASE_MUSIC_COOKIE',
      uid = os.getenv 'NETEASE_MUSIC_UID',
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
- `NETEASE_MUSIC_COOKIE`
- `NETEASE_MUSIC_UID`

`cookie` 和 `uid` 都是可选的，但登录相关页面需要它们之一。插件会优先使用 `setup()` 传入的值；如果接口返回新的 `cookie` 或 `uid`，也会缓存到 lazycmd 的本地 cache 中。

## 依赖

- `NeteaseCloudMusicApi`
- `mpv.lazycmd`

## 接口

当前实现使用这些 API：

- `/login/status`
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

- 这个插件目前聚焦“浏览 + 搜索 + 播放”主流程；已支持喜欢/取消喜欢，但还没有实现二维码登录和歌单编辑等写操作
- `每日推荐歌单`、`每日推荐歌曲`、`我的歌单` 是否可用，取决于接口服务端是否接受当前 `cookie`
- API 响应会同时走内存缓存和 `lc.cache` 持久化缓存，TTL 按接口性质区分：登录态 60 秒，公开推荐/热门歌单 12 小时，我的歌单 3 小时，每日推荐 12 小时，歌单详情 3 小时，搜索 1 天，播放 URL 30 分钟，歌词 30 天
