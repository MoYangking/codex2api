# codex2api 单容器网关

这个镜像把 [james-6-23/codex2api](https://github.com/james-6-23/codex2api) 接入到原有的单容器、单端口结构中：容器内用 `supervisord` 管理多个辅助进程，对外只暴露 `7860`，由 OpenResty 统一反代。

当前组件：
- Codex2API：OpenAI / Anthropic 兼容 API 与内置管理后台，内部监听 `127.0.0.1:8080`
- OpenResty 网关：对外端口 `7860`
- Sync：可选的 GitHub 持久化同步服务，入口 `/sync/`
- SQLite 备份：定时把 `/data/codex2api.db` 备份到 `/home/user/backups/codex2api/`
- FileBrowser：入口 `/filebrowser/`
- GoTTY：入口 `/t/`
- 路由管理 UI：入口 `/admin/ui/`

已移除旧的 Xvfb、NapCat、sin-proxy、MaiBot、MaiBot Adapter 相关构建、脚本和 supervisor 进程。

## 路径

常用入口：
- `/admin/`：Codex2API 管理后台
- `/health`：Codex2API 健康检查
- `/v1/`：兼容 OpenAI 的 API
- `/admin/ui/`：OpenResty 动态路由管理，默认密码 `admin`
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
- `home/user/nginx/admin_config.json`
- `home/user/filebrowser-data/filebrowser.db`

没有配置 `GITHUB_REPO` / `GITHUB_PAT` 时，Sync 会自动空跑，Codex2API 不会等待同步。

## 环境变量

| 名称 | 默认值 | 说明 |
| --- | --- | --- |
| `CODEX_BIND` | `127.0.0.1` | Codex2API 内部监听地址 |
| `CODEX_PORT` | `8080` | Codex2API 内部端口 |
| `ADMIN_SECRET` | 空 | Codex2API 管理后台密钥；为空时按上游首次初始化流程设置 |
| `CODEX_API_KEYS` | 空 | 对外 API Key，逗号分隔 |
| `DATABASE_DRIVER` | `sqlite` | 数据库驱动 |
| `DATABASE_PATH` | `/data/codex2api.db` | SQLite 文件路径 |
| `CACHE_DRIVER` | `memory` | 缓存驱动 |
| `IMAGE_ASSET_DIR` | `/data/images` | 生图图库目录 |
| `BACKUP_INTERVAL` | `3600` | SQLite 备份间隔，`0` 表示只执行一次 |
| `BACKUP_RETENTION_DAYS` | `14` | 历史备份保留天数 |
| `GOTTY_USERNAME` | `admin` | `/t/` 登录用户名 |
| `GOTTY_PASSWORD` | `adminadminadmin` | `/t/` 登录密码 |

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

## 备份恢复

手动触发一次备份：

```bash
docker exec codex2api-gateway /home/user/scripts/backup-sqlite.sh
```

手动恢复最新备份：

```bash
docker exec -e RESTORE_SQLITE_ON_START=always codex2api-gateway /home/user/scripts/restore-sqlite-backup.sh
```

生产场景建议同时挂载 `/data` 或配置 GitHub Sync。GitHub Sync 负责把备份快照和图片资产带走，SQLite 运行库仍通过定时 `.backup` 生成一致快照。
