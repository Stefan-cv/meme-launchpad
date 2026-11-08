# MEME 发射器后端系统

MEME 代币发射平台的后端服务系统，包含 API 服务和区块链事件索引服务。

## 📋 目录

- [系统概述](#系统概述)
- [系统架构](#系统架构)
- [项目结构](#项目结构)
- [快速开始](#快速开始)
- [服务说明](#服务说明)
- [配置说明](#配置说明)
- [开发指南](#开发指南)
- [API 文档](#api-文档)
- [部署指南](#部署指南)

## 系统概述

MEME 发射器后端系统由两个核心服务组成：

1. **API 服务** (`apps/api`) - 提供 RESTful API 接口，处理业务逻辑
2. **索引服务** (`apps/indexer`) - 扫描区块链事件，同步链上数据到数据库

### 核心功能

- 🪙 **代币管理**: 代币创建、查询、详情展示
- 💰 **交易系统**: 买入/卖出交易记录、K线数据
- 📊 **数据索引**: 实时同步链上事件到数据库
- 🔐 **用户认证**: 基于钱包签名的 JWT 认证
- 📈 **K线图表**: 多时间间隔的 K线数据聚合
- 💬 **社交功能**: 评论、收藏、排行榜

## 系统架构

```
┌─────────────┐
│  前端应用    │
└──────┬──────┘
       │ HTTP/REST
       ▼
┌─────────────────────────────────┐
│        API 服务 (api)            │
│  - 业务逻辑处理                  │
│  - 用户认证                      │
│  - 数据查询                      │
└──────┬──────────────────────────┘
       │
       ▼
┌─────────────────────────────────┐
│     PostgreSQL 数据库            │
│  - tokens (代币信息)             │
│  - trades (交易记录)             │
│  - klines (K线数据)              │
│  - users (用户信息)              │
│  - events (链上事件)              │
└──────┬──────────────────────────┘
       ▲
       │ 写入数据
       │
┌─────────────────────────────────┐
│   索引服务 (indexer)             │
│  - 扫描链上事件                  │
│  - 同步到数据库                  │
│  - 计算K线数据                   │
└──────┬──────────────────────────┘
       │
       ▼
┌─────────────────────────────────┐
│     区块链 (BSC Testnet)         │
│  - MEMECore 合约                 │
│  - TokenCreated 事件             │
│  - TokenBought/Sold 事件         │
└─────────────────────────────────┘
```

## 项目结构

```
backend/
├── apps/
│   ├── api/                      # API 服务
│   │   ├── api/                  # API 定义文件
│   │   │   ├── api.api           # 路由定义
│   │   │   └── types.api        # 类型定义
│   │   ├── cmd/                  # 命令行工具（如有）
│   │   ├── etc/                  # 配置文件
│   │   │   └── api.yaml         # API 服务配置
│   │   ├── internal/            # 内部代码
│   │   │   ├── config/          # 配置解析
│   │   │   ├── handler/         # HTTP 处理器
│   │   │   │   ├── routes.go    # 路由注册
│   │   │   │   ├── token/       # 代币相关处理器
│   │   │   │   └── user/        # 用户相关处理器
│   │   │   ├── logic/           # 业务逻辑层
│   │   │   │   ├── token/      # 代币业务逻辑
│   │   │   │   ├── user/       # 用户业务逻辑
│   │   │   │   └── kline/      # K线业务逻辑
│   │   │   ├── middleware/      # 中间件
│   │   │   │   └── authmiddleware.go  # JWT 认证
│   │   │   ├── model/           # 数据模型层
│   │   │   │   ├── token.go    # 代币模型
│   │   │   │   ├── trade.go    # 交易模型
│   │   │   │   ├── kline.go    # K线模型
│   │   │   │   ├── user.go     # 用户模型
│   │   │   │   └── ...
│   │   │   ├── service/         # 服务层
│   │   │   │   ├── token/      # 代币服务（签名、CREATE2）
│   │   │   │   ├── chain/      # 链上服务
│   │   │   │   ├── crypto/     # 加密服务
│   │   │   │   └── cos/        # 对象存储服务
│   │   │   ├── svc/            # 服务上下文
│   │   │   │   └── servicecontext.go
│   │   │   └── types/          # 类型定义
│   │   │       └── types.go
│   │   ├── migrations/         # 数据库迁移
│   │   │   └── 001_init.sql   # 初始化脚本
│   │   ├── main.go            # 程序入口
│   │   ├── Makefile           # 构建脚本
│   │   ├── Dockerfile         # Docker 镜像
│   │   ├── go.mod             # Go 依赖
│   │   └── README.md          # API 服务文档
│   │
│   └── indexer/                 # 索引服务
│       ├── cmd/
│       │   └── indexer/
│       │       └── main.go     # 程序入口
│       ├── config/
│       │   └── config.yaml    # 索引服务配置
│       ├── internal/
│       │   ├── config/         # 配置解析
│       │   ├── database/       # 数据库操作
│       │   │   ├── postgres.go # 数据库连接
│       │   │   └── events.go  # 事件存储逻辑
│       │   ├── indexer/        # 索引器核心
│       │   │   ├── abi.go     # 合约 ABI
│       │   │   └── indexer.go # 索引逻辑
│       │   ├── logger/        # 日志配置
│       │   └── types/         # 类型定义
│       │       └── events.go  # 事件类型
│       ├── Makefile           # 构建脚本
│       ├── Dockerfile         # Docker 镜像
│       ├── go.mod             # Go 依赖
│       └── README.md          # 索引服务文档
│
├── sql/                        # SQL 脚本
│   └── metaland_*.sql        # 数据库备份
│
├── swagger.json               # Swagger API 文档
└── README.md                  # 本文档
```

## 快速开始

### 前置要求

- Go 1.21+
- PostgreSQL 12+
- Redis (可选，用于缓存)
- 访问 BSC 测试网 RPC 节点

### 1. 克隆项目

```bash
git clone <repository-url>
cd meme-launchpad/others/backend
```

### 2. 配置数据库

创建 PostgreSQL 数据库：

```sql
CREATE DATABASE metaland;
```

### 3. 启动 API 服务

```bash
cd apps/api

# 安装依赖
go mod download

# 初始化数据库
make migrate

# 配置服务（编辑 etc/api.yaml）
# 修改数据库连接、链配置等

# 开发模式运行
make dev

# 或编译后运行
make build
./build/meme-api -f etc/api.yaml
```

API 服务默认运行在 `http://localhost:38080`

### 4. 启动索引服务

```bash
cd apps/indexer

# 安装依赖
go mod download

# 配置服务（编辑 config/config.yaml）
# 修改数据库连接、链配置、合约地址等

# 开发模式运行
make dev

# 或编译后运行
make build
./build/meme-indexer -config config/config.yaml
```

索引服务会开始扫描链上事件并同步到数据库。

## 服务说明

### API 服务 (`apps/api`)

基于 go-zero 框架的 RESTful API 服务，提供业务接口。

#### 主要功能

- **用户认证**: 钱包签名登录、JWT Token 管理
- **代币管理**: 创建代币、查询代币列表、详情、排行榜
- **交易查询**: 交易记录、24小时统计
- **K线数据**: 多时间间隔的 K线数据查询
- **社交功能**: 评论、收藏、关注
- **文件上传**: Logo、Banner 等文件上传（腾讯云 COS）

#### 技术栈

- **框架**: go-zero
- **数据库**: PostgreSQL (pgx)
- **缓存**: Redis
- **认证**: JWT
- **文件存储**: 腾讯云 COS

#### 启动命令

```bash
# 开发模式
make dev

# 生产模式
make build && ./build/meme-api -f etc/api.yaml
```

### 索引服务 (`apps/indexer`)

区块链事件索引服务，实时扫描并同步链上数据。

#### 主要功能

- **事件监听**: 监听 `TokenCreated`、`TokenBought`、`TokenSold`、`TokenGraduated` 事件
- **历史同步**: 从指定区块开始同步历史事件
- **实时订阅**: 通过 WebSocket 实时订阅新区块
- **数据同步**: 将事件数据同步到数据库
- **K线计算**: 根据交易事件自动计算并更新 K线数据

#### 监听的事件

1. **TokenCreated**: 代币创建事件
   - 同步到 `tokens` 表
   - 从 `token_creation_requests` 获取 logo 等信息

2. **TokenBought**: 代币买入事件
   - 同步到 `trades` 表
   - 更新 `tokens` 表的 `bnb_current` 和 `available_tokens`
   - 计算并更新 K线数据

3. **TokenSold**: 代币卖出事件
   - 同步到 `trades` 表
   - 更新 `tokens` 表的 `bnb_current` 和 `available_tokens`
   - 计算并更新 K线数据

4. **TokenGraduated**: 代币毕业事件
   - 更新 `tokens` 表状态为已毕业

#### 技术栈

- **区块链客户端**: go-ethereum
- **数据库**: PostgreSQL (pgx)
- **日志**: zap

#### 启动命令

```bash
# 开发模式
make dev

# 生产模式
make build && ./build/meme-indexer -config config/config.yaml
```

## 配置说明

### API 服务配置 (`apps/api/etc/api.yaml`)

```yaml
# 服务配置
Name: meme-api
Host: 0.0.0.0
Port: 38080

# JWT 配置
Auth:
  AccessSecret: your-access-secret-key-change-in-production
  AccessExpire: 86400      # 24小时
  RefreshExpire: 604800    # 7天

# 数据库配置
Database:
  Host: localhost
  Port: 5432
  User: postgres
  Password: your_password
  Name: metaland
  SSLMode: disable
  MaxOpenConns: 50
  MaxIdleConns: 10

# Redis 配置（可选）
Redis:
  Host: localhost:6379
  Pass: ""
  DB: 0

# 链配置
Chain:
  Name: BSC Testnet
  ChainID: 97
  RPC: https://bsc-testnet.infura.io/v3/xxx
  CoreContract: "0x..."      # MEMECore 合约地址
  FactoryContract: "0x..."  # Factory 合约地址
  TokenBytecode: "0x..."     # Token 合约字节码（用于 CREATE2）

# 签名私钥（用于生成合约签名）
SignerPrivateKey: your-private-key

# 腾讯云 COS 配置（文件上传）
Cos:
  SecretID: your-secret-id
  SecretKey: your-secret-key
  Bucket: your-bucket
  Region: ap-shanghai
  AppID: your-app-id
  Domain: https://your-domain.com
```

### 索引服务配置 (`apps/indexer/config/config.yaml`)

```yaml
# 服务配置
Server:
  Name: meme-indexer
  Host: 0.0.0.0
  Port: 8081

# 数据库配置
Database:
  Host: localhost
  Port: 5432
  User: postgres
  Password: your_password
  Name: metaland
  SSLMode: disable
  MaxOpenConns: 25
  MaxIdleConns: 5

# 链配置
Chain:
  Name: BSC Testnet
  ChainID: 97
  RPC: https://bsc-testnet.infura.io/v3/xxx
  WSS: wss://bsc-testnet.publicnode.com  # WebSocket 地址（可选）
  CoreContract: "0x..."      # MEMECore 合约地址
  StartBlock: 82800986        # 开始同步的区块号
  BlockBatchSize: 500         # 每次同步的区块数
  PollInterval: 3             # 轮询间隔（秒）

# 日志配置
Log:
  Level: info                 # debug, info, warn, error
  Format: json                # json, console
```

## 开发指南

### 添加新 API 接口

1. **定义类型** (`apps/api/api/types.api`)
```api
type NewRequest {
    Field string `json:"field"`
}

type NewResponse {
    Result string `json:"result"`
}
```

2. **定义路由** (`apps/api/api/api.api`)
```api
@server (
    prefix: /api/v1
    group:  new
)
service meme-api {
    @doc "新接口"
    @handler NewHandler
    get /new (NewRequest) returns (Response)
}
```

3. **实现处理器** (`apps/api/internal/handler/routes.go`)
```go
func newHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        var req types.NewRequest
        if err := httpx.Parse(r, &req); err != nil {
            httpx.OkJsonCtx(r.Context(), w, types.Error(400, "invalid request"))
            return
        }
        
        l := logic.NewNewLogic(r.Context(), svcCtx)
        resp, err := l.New(&req)
        if err != nil {
            httpx.OkJsonCtx(r.Context(), w, types.Error(500, err.Error()))
            return
        }
        httpx.OkJsonCtx(r.Context(), w, resp)
    }
}
```

4. **实现业务逻辑** (`apps/api/internal/logic/new/logic.go`)
```go
func (l *NewLogic) New(req *types.NewRequest) (*types.Response, error) {
    // 业务逻辑实现
    return types.Success(result), nil
}
```

5. **注册路由** (`apps/api/internal/handler/routes.go`)
```go
server.AddRoutes(
    []rest.Route{
        {
            Method:  http.MethodGet,
            Path:    "/new",
            Handler: newHandler(svcCtx),
        },
    },
    rest.WithPrefix("/api/v1"),
)
```

### 数据库操作

使用 Model 层进行数据库操作：

```go
// 在 internal/model/ 中定义模型
type TokenModel struct {
    db *pgxpool.Pool
}

// 实现查询方法
func (m *TokenModel) FindByAddress(ctx context.Context, address string) (*Token, error) {
    // SQL 查询
}
```

### 添加新的事件处理

在索引服务中添加新事件处理：

1. **定义事件类型** (`apps/indexer/internal/types/events.go`)
```go
type NewEvent struct {
    // 事件字段
}
```

2. **解析事件** (`apps/indexer/internal/indexer/indexer.go`)
```go
case idx.contractABI.Events["NewEvent"].ID:
    event, err := idx.parseNewEvent(vLog, timestamp)
    // 处理事件
```

3. **存储事件** (`apps/indexer/internal/database/events.go`)
```go
func (db *DB) InsertNewEvent(ctx context.Context, event *types.NewEvent) error {
    // 插入数据库
}
```

## API 文档

### 认证相关

| 方法 | 路径 | 说明 | 认证 |
|------|------|------|------|
| GET | `/api/v1/user/sign-msg` | 获取签名消息 | ❌ |
| POST | `/api/v1/user/wallet-login` | 钱包登录 | ❌ |
| POST | `/api/v1/user/refresh-token` | 刷新令牌 | ❌ |
| GET | `/api/v1/user/overview-stats` | 用户统计 | ✅ |

### 代币相关

| 方法 | 路径 | 说明 | 认证 |
|------|------|------|------|
| GET | `/api/v1/token/token-list` | 代币列表 | ❌ |
| GET | `/api/v1/token/detail` | 代币详情 | ❌ |
| GET | `/api/v1/token/hot-pick` | 热门代币 | ❌ |
| POST | `/api/v1/token/create-token` | 创建代币 | ✅ |
| POST | `/api/v1/token/favorite` | 收藏代币 | ✅ |

### 交易相关

| 方法 | 路径 | 说明 | 认证 |
|------|------|------|------|
| GET | `/api/v1/trade/list` | 交易记录 | ❌ |
| GET | `/api/v1/trade/upcoming-token` | 即将上线 | ❌ |

### K线数据

| 方法 | 路径 | 说明 | 认证 |
|------|------|------|------|
| GET | `/api/v1/kline/history` | K线历史 | ❌ |
| GET | `/api/v1/kline/history-with-cursor` | K线分页 | ❌ |

**K线接口示例**:
```
GET /api/v1/kline/history-with-cursor?tokenAddr=0x...&interval=1m&limit=300&chainId=97

响应:
{
  "code": 200,
  "message": "success",
  "data": {
    "cursor": "MjAyNS0xMi0yMlQxODo0NTowMFo",
    "klines": {
      "s": "",
      "t": [1766429100],
      "o": ["0.000000260481"],
      "h": ["0.000000290434057498"],
      "l": ["0.000000260481"],
      "c": ["0.000000290434057498"],
      "v": ["2968942.365683581026451"]
    }
  }
}
```

完整 API 文档请参考 `swagger.json` 或各服务的 README。

## 部署指南

### Docker 部署

#### API 服务

```bash
cd apps/api

# 构建镜像
make docker-build

# 运行容器
docker run -d \
  --name meme-api \
  -p 38080:38080 \
  -v $(pwd)/etc:/app/etc \
  meme-api:latest
```

#### 索引服务

```bash
cd apps/indexer

# 构建镜像
make docker-build

# 运行容器
docker run -d \
  --name meme-indexer \
  -v $(pwd)/config:/app/config \
  meme-indexer:latest
```

### 生产环境建议

1. **数据库**: 使用连接池，配置合理的连接数
2. **索引服务**: 设置合适的 `BlockBatchSize`，避免 RPC 限流
3. **监控**: 添加 Prometheus 监控指标
4. **日志**: 使用结构化日志，配置日志轮转
5. **安全**: 
   - 使用强密码和密钥
   - 启用 HTTPS
   - 配置防火墙规则

## 数据库表说明

### 核心业务表

- **tokens**: 代币信息表
  - 包含代币基本信息、logo、状态、BNB 数量等
  - 索引服务会自动更新 `bnb_current` 和 `available_tokens`

- **trades**: 交易记录表
  - 记录所有买入/卖出交易
  - 包含 BNB 金额、代币数量、价格等

- **klines**: K线数据表
  - 按时间间隔聚合的 OHLCV 数据
  - 支持 1m, 5m, 15m, 30m, 1h, 4h, 1d, 1w
  - 索引服务自动计算和更新

- **users**: 用户表
  - 钱包地址、用户信息

### 事件表（由索引服务维护）

- **token_created_events**: 代币创建事件
- **token_bought_events**: 代币买入事件
- **token_sold_events**: 代币卖出事件
- **token_graduated_events**: 代币毕业事件

## 常见问题

### Q: 索引服务如何保证数据一致性？

A: 索引服务使用事务确保数据一致性。每个事件处理都在事务中完成，包括：
- 插入事件表
- 更新业务表（tokens、trades）
- 更新 K线数据

### Q: K线数据如何计算？

A: K线数据从 `TokenBought` 和 `TokenSold` 事件计算：
- 价格 = BNB金额 / Token数量
- 按时间间隔聚合（1m, 5m 等）
- 自动计算 OHLCV（开盘价、最高价、最低价、收盘价、成交量）

### Q: 如何重置索引服务？

A: 删除 `indexer_state` 表中的记录，或修改配置中的 `StartBlock`。

### Q: API 服务如何获取代币 logo？

A: 索引服务在处理 `TokenCreated` 事件时，会从 `token_creation_requests` 表查询 logo 并更新到 `tokens` 表。

## 技术栈

- **语言**: Go 1.21+
- **框架**: go-zero (API), go-ethereum (Indexer)
- **数据库**: PostgreSQL
- **缓存**: Redis
- **认证**: JWT
- **文件存储**: 腾讯云 COS
- **容器化**: Docker

## 贡献指南

1. Fork 项目
2. 创建功能分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 开启 Pull Request

## 许可证

MIT License

## 联系方式

如有问题或建议，请提交 Issue 或联系开发团队。

