# MEME Launchpad Indexer

BSC 测试网区块链事件索引服务，用于监听和索引 MEME Core 合约的事件。

## 功能特性

- 🔍 **事件监听**: 监听 `TokenCreated`, `TokenBought`, `TokenSold`, `TokenGraduated` 事件
- 📊 **历史同步**: 支持从指定区块开始同步历史事件
- 🔄 **实时订阅**: 通过 WebSocket 实时订阅新区块
- 💾 **PostgreSQL**: 使用 PostgreSQL 存储索引数据
- 🚀 **高性能**: 批量处理和并发优化

## 目录结构

```
.
├── cmd/
│   └── indexer/
│       └── main.go          # 程序入口
├── config/
│   └── config.yaml          # 配置文件
├── internal/
│   ├── config/
│   │   └── config.go        # 配置解析
│   ├── database/
│   │   ├── postgres.go      # 数据库连接
│   │   └── events.go        # 事件存储
│   ├── indexer/
│   │   ├── abi.go           # 合约 ABI
│   │   └── indexer.go       # 索引器核心逻辑
│   ├── logger/
│   │   └── logger.go        # 日志配置
│   └── types/
│       └── events.go        # 事件类型定义
├── Dockerfile
├── Makefile
├── go.mod
├── go.sum
└── README.md
```

## 快速开始

### 1. 配置数据库

确保 PostgreSQL 数据库已启动，并创建数据库：

```sql
CREATE DATABASE metaland;
```

### 2. 修改配置

编辑 `config/config.yaml`：

```yaml
Database:
  Host: localhost
  Port: 5432
  User: postgres
  Password: your_password
  Name: metaland

Chain:
  CoreContract: "0xb58A9e7720A3Be24082C91178193fbd76020c079"
  StartBlock: 0  # 设置为合约部署的区块号
```

### 3. 安装依赖

```bash
go mod tidy
```

### 4. 运行

```bash
# 直接运行
make run

# 或者编译后运行
make build
./build/meme-indexer -config config/config.yaml
```

## 配置说明

| 配置项 | 说明 | 默认值 |
|--------|------|--------|
| `Server.Name` | 服务名称 | meme-indexer |
| `Server.Port` | HTTP 端口 | 8081 |
| `Database.Host` | 数据库地址 | localhost |
| `Database.Port` | 数据库端口 | 5432 |
| `Database.MaxOpenConns` | 最大连接数 | 25 |
| `Chain.RPC` | RPC 节点地址 | BSC 测试网 |
| `Chain.WSS` | WebSocket 节点地址 | BSC 测试网 |
| `Chain.CoreContract` | Core 合约地址 | - |
| `Chain.StartBlock` | 开始同步的区块号 | 0 |
| `Chain.BlockBatchSize` | 每次同步的区块数 | 1000 |
| `Chain.PollInterval` | 轮询间隔(秒) | 3 |

## 数据库表结构

### token_created_events

记录代币创建事件。

| 字段 | 类型 | 说明 |
|------|------|------|
| token_address | VARCHAR(42) | 代币合约地址 |
| creator_address | VARCHAR(42) | 创建者地址 |
| name | VARCHAR(255) | 代币名称 |
| symbol | VARCHAR(50) | 代币符号 |
| total_supply | NUMERIC(78,0) | 总供应量 |
| request_id | VARCHAR(66) | 请求 ID |

### token_bought_events

记录代币购买事件。

| 字段 | 类型 | 说明 |
|------|------|------|
| token_address | VARCHAR(42) | 代币合约地址 |
| buyer_address | VARCHAR(42) | 买家地址 |
| bnb_amount | NUMERIC(78,0) | BNB 金额 |
| token_amount | NUMERIC(78,0) | 代币数量 |
| trading_fee | NUMERIC(78,0) | 交易手续费 |

### token_sold_events

记录代币卖出事件。

| 字段 | 类型 | 说明 |
|------|------|------|
| token_address | VARCHAR(42) | 代币合约地址 |
| seller_address | VARCHAR(42) | 卖家地址 |
| token_amount | NUMERIC(78,0) | 代币数量 |
| bnb_amount | NUMERIC(78,0) | BNB 金额 |
| trading_fee | NUMERIC(78,0) | 交易手续费 |

### token_graduated_events

记录代币毕业事件。

| 字段 | 类型 | 说明 |
|------|------|------|
| token_address | VARCHAR(42) | 代币合约地址 |
| liquidity_bnb | NUMERIC(78,0) | 流动性 BNB |
| liquidity_tokens | NUMERIC(78,0) | 流动性代币 |
| liquidity_result | NUMERIC(78,0) | LP 代币数量 |

## Docker 部署

```bash
# 构建镜像
make docker-build

# 运行容器
docker run -d \
  --name meme-indexer \
  -v $(pwd)/config:/app/config \
  meme-indexer:latest
```

## 开发

```bash
# 安装 air 热重载工具
go install github.com/cosmtrek/air@latest

# 开发模式运行
make dev

# 运行测试
make test

# 代码格式化
make fmt

# 代码检查
make lint
```

## 监听的事件

### TokenCreated

当新代币被创建时触发。

```solidity
event TokenCreated(
    address indexed token,
    address indexed creator,
    string name,
    string symbol,
    uint256 totalSupply,
    bytes32 requestId
);
```

### TokenBought

当用户购买代币时触发。

```solidity
event TokenBought(
    address indexed token,
    address indexed buyer,
    uint256 bnbAmount,
    uint256 tokenAmount,
    uint256 tradingFee,
    uint256 virtualBNBReserve,
    uint256 virtualTokenReserve,
    uint256 availableTokens,
    uint256 collectedBNB
);
```

### TokenSold

当用户卖出代币时触发。

```solidity
event TokenSold(
    address indexed token,
    address indexed seller,
    uint256 tokenAmount,
    uint256 bnbAmount,
    uint256 tradingFee,
    uint256 virtualBNBReserve,
    uint256 virtualTokenReserve,
    uint256 availableTokens,
    uint256 collectedBNB
);
```

### TokenGraduated

当代币毕业（添加 DEX 流动性）时触发。

```solidity
event TokenGraduated(
    address indexed token,
    uint256 liquidityBNB,
    uint256 liquidityTokens,
    uint256 liquidityResult
);
```

## License

MIT

