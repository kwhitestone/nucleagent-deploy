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
| MySQL | 13306 | - |
| Redis | 16379 | - |
| auth | 6670 | 6678 |
| core | 6680 | 6688 |
| executor | 6690 | 6698 |
| web (主壳) | - | 80 |

## 边界

- **Always**: 新增服务必须在 docker-compose.yml 注册
- **Always**: 敏感配置通过 .env 传入，不硬编码
- **Never**: 禁止在本 repo 写业务代码
