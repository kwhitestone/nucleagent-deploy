# nucleagent-deploy

部署配置：docker-compose + Makefile + 环境变量。

## 构建

```bash
cp .env.example .env
make up              # 拉起 MySQL + Redis
make ps              # 查看状态
make down            # 停止
```

## 架构约束

- docker-compose.yml 定义全部服务（MySQL / Redis / auth / core / executor / web）
- 各服务的 Dockerfile 在各自 repo 里，deploy 只做编排
- 端口分配固定，不随意更改

## 端口分配

| 服务 | 后端 | 前端 |
|------|------|------|
| MySQL | 26606 | - |
| Redis | 26679 | - |
| auth | 26670 | 26678 |
| core | 26680 | 26688 |
| executor | 26690 | 26698 |
| web (主壳) | - | 80 |

## Nginx 反向代理

`nucleagent-web` 对外暴露 :80，由 Nginx 按子应用路径前缀反向代理到各子应用前端：

| 路径 | 目标 |
|------|------|
| /auth/* | auth 前端 (:26678) |
| /core/* | core 前端 (:26688) |
| /executor/* | executor 前端 (:26698) |
| / | web 主壳自身 |

子应用前端独立部署，Nginx 配置随 deploy repo 维护。

## 边界

- **Always**: 新增服务必须在 docker-compose.yml 注册
- **Always**: 敏感配置通过 .env 传入，不硬编码
- **Never**: 禁止在本 repo 写业务代码
