# nucleagent-deploy

Nucleagent 部署配置 + 一键运维脚本。

## 服务端口

| 服务 | 后端端口 | 前端端口 |
|------|---------|---------|
| MySQL | 26606 | - |
| Redis | 26679 | - |
| nucleagent-auth | 26670 | 26678 |
| nucleagent-core | 26680 | 26688 |
| nucleagent-executor | 26690 | 26698 |
| nucleagent-web (微前端主壳) | - | 26600(dev) / 80(prod) |

## 架构

```
nucleagent-web (微前端主壳 :26600)
├── auth 子应用 (:26678)  -> auth 后端 (:26670)
├── core 子应用 (:26688)  -> core 后端 (:26680) <-> executor 后端 (:26690)
└── executor 子应用 (:26698)
```

所有服务基于 Prism Fusion 框架构建，子应用以 iframe 方式加载到主壳。

## 新机器一键引导

只需 clone 这一个 repo，运行 bootstrap 会自动 clone 其余 7 个 repo + 初始化环境：

```bash
git clone git@github.com:kwhitestone/nucleagent-deploy.git
cd nucleagent-deploy
./scripts/bootstrap.sh
# 或 make bootstrap
```

bootstrap 会：
1. 在上一级目录 clone 其余 7 个 repo（prism-fusion + nucleagent-{shared,core,auth,executor,web,docs}）
2. 从 `.env.example` 创建 `.env`（提醒修改密钥）
3. 同步依赖（go mod tidy + npm install）
4. 构建验证

完成后：
```bash
make dev          # 启动全部服务
# 访问 http://localhost:26600
```

## 日常命令（Makefile）

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

## 快速开始（已引导过的机器）

```bash
make update                # 更新所有 repo + 依赖 + 构建
make dev                   # 启动全部服务
# 访问 http://localhost:26600
```

## 脚本说明

| 脚本 | 作用 |
|------|------|
| `scripts/bootstrap.sh` | 新机器引导（clone 全部 repo + 初始化） |
| `scripts/update.sh` | 更新所有 repo（pull/deps/build） |
| `scripts/dev.sh` | 启动/停止/查看全部 dev 服务 |

服务日志在 `.dev-logs/<name>.log`（已 gitignore）。

## 环境变量

见 `.env.example`。关键变量：
- `JWT_SECRET` - auth/core 共享的 JWT 签名密钥
- `EXECUTOR_TOKEN` - core↔executor S2S 校验令牌
- `*_WEB_PORT` / `*_FRONTEND_URL` - 前端端口 + CORS 白名单
