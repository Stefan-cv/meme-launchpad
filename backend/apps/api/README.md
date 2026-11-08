# MEME Launchpad API

基于 go-zero 框架的 MEME 代币发射平台后端 API 服务。

## 项目结构

```
api/
├── api/                          # API 定义文件
│   ├── api.api                   # 主路由定义
│   └── types.api                 # 类型定义
├── etc/
│   └── api.yaml                  # 配置文件
├── internal/
│   ├── config/
│   │   └── config.go             # 配置解析
│   ├── handler/
│   │   ├── routes.go             # 路由注册
│   │   ├── user/                 # 用户相关处理器
│   │   └── token/                # 代币相关处理器
│   ├── logic/
│   │   ├── user/                 # 用户业务逻辑
│   │   └── token/                # 代币业务逻辑
│   ├── middleware/
│   │   └── authmiddleware.go     # JWT 认证中间件
│   ├── model/
│   │   ├── user.go               # 用户模型
│   │   ├── token.go              # 代币模型
│   │   ├── trade.go              # 交易模型
│   │   ├── comment.go            # 评论模型
│   │   ├── activity.go           # 活动模型
│   │   └── invite.go             # 邀请模型
│   ├── svc/
│   │   └── servicecontext.go     # 服务上下文
│   └── types/
│       └── types.go              # 请求/响应类型
├── migrations/
│   └── 001_init.sql              # 数据库初始化
├── Dockerfile
├── Makefile
├── go.mod
└── main.go
```

## 快速开始

### 1. 安装依赖

```bash
go mod download
```

### 2. 配置

编辑 `etc/api.yaml` 配置文件，修改数据库、Redis 等连接信息。

### 3. 初始化数据库

```bash
make migrate
```

### 4. 运行

```bash
# 开发模式
make dev

# 或编译后运行
make run
```

## API 接口

### 认证相关

| 方法 | 路径 | 说明 | 需要认证 |
|------|------|------|----------|
| GET | `/api/v1/user/sign-msg` | 获取签名消息 | ❌ |
| POST | `/api/v1/user/wallet-login` | 钱包登录 | ❌ |
| POST | `/api/v1/user/refresh-token` | 刷新令牌 | ❌ |
| GET | `/api/v1/user/overview-stats` | 获取用户统计 | ✅ |

### 代币相关

| 方法 | 路径 | 说明 | 需要认证 |
|------|------|------|----------|
| GET | `/api/v1/token/token-list` | 获取代币列表 | ❌ |
| GET | `/api/v1/token/detail` | 获取代币详情 | ❌ |
| GET | `/api/v1/token/hot-pick` | 获取热门代币 | ❌ |
| GET | `/api/v1/token/holders` | 获取持有者列表 | ❌ |
| POST | `/api/v1/token/create-token` | 创建代币 | ✅ |
| POST | `/api/v1/token/calculate-address` | 计算代币地址 | ✅ |
| POST | `/api/v1/token/favorite` | 收藏代币 | ✅ |
| POST | `/api/v1/token/unfavorite` | 取消收藏 | ✅ |

### 评论相关

| 方法 | 路径 | 说明 | 需要认证 |
|------|------|------|----------|
| GET | `/api/v1/comment/list` | 获取评论列表 | ❌ |
| POST | `/api/v1/comment/post-comment` | 发布评论 | ✅ |
| POST | `/api/v1/comment/delete` | 删除评论 | ✅ |

### 交易相关

| 方法 | 路径 | 说明 | 需要认证 |
|------|------|------|----------|
| GET | `/api/v1/trade/list` | 获取交易记录 | ❌ |
| GET | `/api/v1/trade/upcoming-token` | 即将上线代币 | ❌ |

### K线数据

| 方法 | 路径 | 说明 | 需要认证 |
|------|------|------|----------|
| GET | `/api/v1/kline/history` | 获取K线历史 | ❌ |
| GET | `/api/v1/kline/history-with-cursor` | 分页获取K线 | ❌ |

### 排行榜

| 方法 | 路径 | 说明 | 需要认证 |
|------|------|------|----------|
| GET | `/api/v1/token/ranking-token-list` | 排行榜列表 | ❌ |
| GET | `/api/v1/token/overview-rankings` | 概览排行榜 | ❌ |

### 邀请/代理

| 方法 | 路径 | 说明 | 需要认证 |
|------|------|------|----------|
| GET | `/api/v1/back/user-status` | 用户状态 | ❌ |
| GET | `/api/v1/back/user-commission` | 佣金信息 | ❌ |
| GET | `/api/v1/back/agent-detail` | 代理详情 | ✅ |

### 活动相关

| 方法 | 路径 | 说明 | 需要认证 |
|------|------|------|----------|
| GET | `/api/v1/act/user-participated` | 参与的活动 | ✅ |
| GET | `/api/v1/act/user-created` | 创建的活动 | ✅ |
| POST | `/api/v1/act/create` | 创建活动 | ✅ |

## 认证方式

使用 JWT Bearer Token 认证：

```
Authorization: Bearer <token>
```

### 登录流程

1. 调用 `/user/sign-msg` 获取签名消息
2. 使用钱包签名消息
3. 调用 `/user/wallet-login` 完成登录
4. 获取 `token` 和 `refreshToken`

## Docker 部署

```bash
# 构建镜像
make docker-build

# 运行容器
make docker-run
```

## 配置说明

```yaml
# 服务配置
Name: meme-api
Host: 0.0.0.0
Port: 8080

# JWT 配置
Auth:
  AccessSecret: your-secret-key
  AccessExpire: 86400     # 24小时
  RefreshExpire: 604800   # 7天

# 数据库配置
Database:
  Host: localhost
  Port: 5432
  User: postgres
  Password: password
  Name: metaland

# Redis 配置
Redis:
  Host: localhost:6379
  Pass: ""
  DB: 0

# 链配置
Chain:
  Name: BSC Testnet
  ChainID: 97
  RPC: https://bsc-testnet.infura.io/v3/xxx
  CoreContract: "0xB91288Fd6ab205623D72A2ddA29230efe04D6DFD"
```

## 开发说明

### 添加新接口

1. 在 `api/types.api` 中定义请求/响应类型
2. 在 `api/api.api` 中添加路由定义
3. 在 `internal/handler/` 中添加处理器
4. 在 `internal/logic/` 中实现业务逻辑
5. 在 `internal/handler/routes.go` 中注册路由

### 数据库操作

模型层位于 `internal/model/`，使用 `pgx` 直接操作 PostgreSQL。

### TODO

- [ ] 实现 CREATE2 地址计算
- [ ] 实现合约签名生成
- [ ] 实现 S3/OSS 文件上传
- [ ] 实现 K线数据聚合
- [ ] 实现 WebSocket 实时推送
- [ ] 添加限流和熔断
- [ ] 添加 Prometheus 监控

