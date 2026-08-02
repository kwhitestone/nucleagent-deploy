# nucleagent-deploy

Nucleagent 部署配置 + 一键运维脚本。

## 服务端口

| 服务 | 后端端口 | 前端端口 |
|------|---------|---------|
| MySQL | 13306 | - |
| Redis | 16379 | - |
| nucleagent-auth | 6670 | 6678 |
| nucleagent-core | 6680 | 6688 |
| nucleagent-executor | 6690 | 6698 |
| nucleagent-web (微前端主壳) | - | 3000(dev) / 80(prod) |

## 架构

```
nucleagent-web (微前端主壳 :3000)
├── auth 子应用 (:6678)  -> auth 后端 (:6670)
├── core 子应用 (:6688)  -> core 后端 (:6680) <-> executor 后端 (:6690)
└── executor 子应用 (:6698)
```

所有服务基于 Prism Fusion 框架构建，子应用以 iframe 方式加载到主壳。

## 一键命令（Makefile）

```bash
# 一键更新所有 repo（git pull + 依赖同步 + 构建验证）
make update

# 单独操作
make update-pull    # 只 git pull 8 个 repo
make update-deps    # 只同步依赖（go mod tidy + npm install）
make update-build   # 只构建验证

# 本地开发
make dev            # 启动全部 dev 服务（infra + 3 后端 + 4 前端）
make dev-stop       # 停止全部 dev 服务

# 基础设施
make up             # 拉起 MySQL + Redis
make down           # 停止
make ps             # 查看状态
make logs           # 查看日志
```

## 快速开始

```bash
cp .env.example .env       # 配置环境变量
make update                # 更新所有 repo + 依赖 + 构建
make dev                   # 启动全部服务
# 访问 http://localhost:3000
```

## 脚本说明

| 脚本 | 作用 |
|------|------|
| `scripts/update.sh` | 更新所有 repo（pull/deps/build 三步） |
| `scripts/dev.sh` | 启动/停止/查看全部 dev 服务 |

服务日志在 `.dev-logs/<name>.log`（已 gitignore）。

## 环境变量

见 `.env.example`。关键变量：
- `JWT_SECRET` - auth/core 共享的 JWT 签名密钥
- `EXECUTOR_TOKEN` - core↔executor S2S 校验令牌
- `*_WEB_PORT` / `*_FRONTEND_URL` - 前端端口 + CORS 白名单
