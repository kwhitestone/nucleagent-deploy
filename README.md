# nucleagent-deploy

Nucleagent 部署配置。

## 服务端口

| 服务 | 后端端口 | 前端端口 |
|------|---------|---------|
| MySQL | 13306 | - |
| Redis | 16379 | - |
| nucleagent-auth | 6670 | 6678 |
| nucleagent-core | 6680 | 6688 |
| nucleagent-executor | 6690 | 6698 |
| nucleagent-web (微前端主壳) | - | 80 |

## 架构

```
nucleagent-web (micro-app 主壳 :80)
├── auth 子应用 (:6678)  -> auth 后端 (:6670)
├── core 子应用 (:6688)  -> core 后端 (:6680) <-> executor 后端 (:6690)
└── executor 子应用 (:6698)
```

所有服务基于 Prism Fusion 框架构建。

## 快速开始

```bash
cp .env.example .env
make up        # 拉起 MySQL + Redis
make ps        # 查看状态
make down      # 停止
```
