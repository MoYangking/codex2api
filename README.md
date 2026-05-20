# codex2api 单容器网关

这个镜像把 [james-6-23/codex2api](https://github.com/james-6-23/codex2api) 接入到原有的单容器、单端口结构中：容器内用 `supervisord` 管理多个辅助进程，对外只暴露 `7860`，由 OpenResty 统一反代。

当前组件：
- Codex2API：OpenAI / Anthropic 兼容 API 与内置管理后台，内部监听 `127.0.0.1:8001`
- OpenResty 网关：对外端口 `7860`
- Sync：可选的 GitHub 持久化同步服务，入口 `/sync/`
- SQLite 备份：定时把 `/data/codex2api.db` 备份到 `/home/user/backups/codex2api/`
- FileBrowser：入口 `/filebrowser/`
- GoTTY：入口 `/t/`

已移除旧的 Xvfb、NapCat、sin-proxy、MaiBot、MaiBot Adapter 相关构建、脚本和 supervisor 进程。
网关现在使用原生 nginx `location`，不再使用 JSON 动态路由配置。

## 路径

常用入口：
- `/admin/`：Codex2API 管理后台
- `/health`：Codex2API 健康检查
- `/v1/`：兼容 OpenAI 的 API
- `/sync/`：GitHub 同步管理页面
- `/filebrowser/`：文件管理
- `/t/`：Web 终端，默认账号 `admin`，密码 `adminadminadmin`

默认路由会把未命中的请求转发到 Codex2API。

## 数据与备份

Codex2API 使用 SQLite：

```env
DATABASE_DRIVER=sqlite
DATABASE_PATH=/data/codex2api.db
CACHE_DRIVER=memory
IMAGE_ASSET_DIR=/data/images
```

备份脚本默认每 3600 秒执行一次：

```env
BACKUP_DIR=/home/user/backups/codex2api
BACKUP_INTERVAL=3600
BACKUP_RETENTION_DAYS=14
RESTORE_SQLITE_ON_START=missing
```

备份文件包括：
- `latest.db`：最新快照
- `codex2api_YYYYmmdd_HHMMSS.db`：历史快照

启动时如果 `/data/codex2api.db` 不存在，会自动从 `latest.db` 或最新历史快照恢复。设置 `RESTORE_SQLITE_ON_START=always` 可强制覆盖恢复，设置 `never` 可关闭恢复。

## 可选 GitHub 同步

配置以下变量后，Sync 会把关键数据同步到 GitHub 仓库：

```env
GITHUB_REPO=<owner>/<repo>
GITHUB_PAT=<token>
GIT_BRANCH=main
```

默认同步目标：
- `home/user/backups/codex2api/`
- `data/images/`
- `home/user/filebrowser-data/filebrowser.db`

没有配置 `GITHUB_REPO` / `GITHUB_PAT` 时，Sync 会自动空跑，Codex2API 不会等待同步。

## 环境变量

| 名称 | 默认值 | 说明 |
| --- | --- | --- |
| `CODEX_BIND` | `127.0.0.1` | Codex2API 内部监听地址 |
| `CODEX_PORT` | `8001` | Codex2API 内部端口 |
| `ADMIN_SECRET` | 空 | Codex2API 管理后台密钥；为空时按上游首次初始化流程设置 |
| `BOOTSTRAP_ALLOWED_CIDR` | `0.0.0.0/0,::/0` | 首次初始化允许的客户端网段；初始化完成后可覆盖为你的出口 IP/CIDR |
| `CODEX_API_KEYS` | 空 | 对外 API Key，逗号分隔 |
| `DATABASE_DRIVER` | `sqlite` | 数据库驱动 |
| `DATABASE_PATH` | `/data/codex2api.db` | SQLite 文件路径 |
| `CACHE_DRIVER` | `memory` | 缓存驱动 |
| `IMAGE_ASSET_DIR` | `/data/images` | 生图图库目录 |
| `BACKUP_INTERVAL` | `3600` | SQLite 备份间隔，`0` 表示只执行一次 |
| `BACKUP_RETENTION_DAYS` | `14` | 历史备份保留天数 |
| `GOTTY_USERNAME` | `admin` | `/t/` 登录用户名 |
| `GOTTY_PASSWORD` | `adminadminadmin` | `/t/` 登录密码 |
| `CLOUDFLARE_TUNNEL_TOKEN` | 空 | Cloudflare Tunnel token；设置后自动执行 `cloudflared service install` 并启动隧道 |
| `CLOUDFLARE_QUICK_TUNNEL` | `0` | 设置为 `1` 时启动临时 trycloudflare 隧道 |

## 本地运行

构建：

```bash
docker build -t codex2api-gateway:latest .
```

启动：

```bash
docker run -d \
  -p 7860:7860 \
  -e ADMIN_SECRET="<strong-secret>" \
  --name codex2api-gateway \
  codex2api-gateway:latest
```

带 GitHub 同步：

```bash
docker run -d \
  -p 7860:7860 \
  -e ADMIN_SECRET="<strong-secret>" \
  -e GITHUB_REPO="<owner>/<repo>" \
  -e GITHUB_PAT="<token>" \
  --name codex2api-gateway \
  codex2api-gateway:latest
```

访问 `http://localhost:7860/admin/` 进入 Codex2API 管理后台。

首次初始化依赖 Codex2API 的来源 IP 校验。由于服务前面有 OpenResty 反代，镜像默认设置 `BOOTSTRAP_ALLOWED_CIDR=0.0.0.0/0,::/0`，确保公网域名也能完成第一次初始化；完成后可以在运行参数里覆盖为更窄的网段。

## Cloudflare Tunnel

镜像通过 Cloudflare 官方 apt 源安装 `cloudflared`。如果使用 Cloudflare Tunnel，就可以绕过会占用 `Authorization` 的平台前置代理，客户端恢复标准 OpenAI 配置：

```text
base_url = https://<你的域名>/v1
api_key = <你的 API Key>
```

在 Cloudflare Zero Trust 中创建 Tunnel，并把 Public Hostname 的 Service 指向：

```text
http://localhost:7860
```

然后启动容器时传入 token。容器启动后会读取 `CLOUDFLARE_TUNNEL_TOKEN`，执行等价于 `cloudflared service install "$CLOUDFLARE_TUNNEL_TOKEN"` 的初始化，并由 supervisor 托管前台隧道进程：

```bash
docker run -d \
  -e CLOUDFLARE_TUNNEL_TOKEN="<cloudflare tunnel token>" \
  --name codex2api-gateway \
  codex2api-gateway:latest
```

如果只想临时测试，也可以启用 trycloudflare 随机域名：

```text
CLOUDFLARE_QUICK_TUNNEL=1
```

临时 trycloudflare 隧道只建议用于测试；如果需要流式输出，请使用正式 Tunnel token。

## 备份恢复

手动触发一次备份：

```bash
docker exec -e BACKUP_INTERVAL=0 codex2api-gateway /home/user/scripts/backup-sqlite.sh
```

手动恢复最新备份时请先停止 Codex2API 进程，避免覆盖正在写入的 SQLite 文件：

```bash
docker exec -e RESTORE_SQLITE_ON_START=always codex2api-gateway /home/user/scripts/restore-sqlite-backup.sh
```

生产场景建议同时挂载 `/data` 或配置 GitHub Sync。GitHub Sync 负责把备份快照和图片资产带走，SQLite 运行库仍通过定时 `.backup` 生成一致快照。

## 常见问题

如果页面返回 `400 Bad Request: Request Header Or Cookie Too Large`，镜像已在 OpenResty 中提高请求头缓冲：

```nginx
client_header_buffer_size 128k;
large_client_header_buffers 16 512k;
```

重新构建并启动新镜像后生效。如果浏览器仍报错，清理该域名下的旧 Cookie 后再访问。

如果 `/t/` 提示“重定向次数过多”，原因通常是旧路由里存在 `/t -> /t/`，而 GoTTY 自身又把路径规范化回 `/t`。当前配置已经改为原生 nginx 代理 `/t` 与 `/t/`，不会再读取旧 JSON 路由。

`/filebrowser/` 出现同类重定向循环时也一样：当前配置参考 `jihuang` 的处理方式，`/filebrowser` 会直接代理到后端 `/filebrowser/`，避免外部 301 循环。
