# MEME Launchpad 🚀

Bonding-curve meme token launchpad (pump.fun-style) on EVM — **full stack in one repo**: Solidity contracts + Go backend (API + Indexer) + TypeScript trading frontend.

```
contracts/   Foundry 项目：MEMECore(联合曲线) / MEMEFactory(CREATE2) / MEMEHelper / MEMEVesting
backend/     Go 双服务：apps/api (go-zero REST) + apps/indexer (链上事件索引)
web/         Vite + React + TS + ethers v6 + lightweight-charts 交易前端
```

## 架构

```
前端(Vite/React/TS) ──REST/SIWE──▶ Go API (go-zero)
      │                              │ ECDSA 签名发币参数
      ▼                              ▼
  ethers v6 ──────EVM 合约──────▶ MetaNodeCore (UUPS)
                                     │ TokenCreated/Bought/Sold 事件
                                     ▼
                              Go Indexer（eth_getLogs 批量拉取 + 自适应限流
                                     │ + 幂等落库 + K线聚合）
                                     ▼
                          PostgreSQL + Redis ──▶ API K线/行情 ──▶ 前端图表
```

## 快速开始（本地 anvil 全链路）

依赖：foundry、go 1.24+、node 20+、PostgreSQL、Redis

```bash
# 1. 数据库
createdb metaland -O postgres
psql metaland -f backend/sql/schema.sql
psql metaland -c "INSERT INTO nonce_sequence (chain_id, current_nonce) VALUES (31337, 0)"

# 2. 合约依赖 + 本地链
cd contracts && forge install foundry-rs/forge-std OpenZeppelin/openzeppelin-contracts OpenZeppelin/openzeppelin-contracts-upgradeable
anvil --host 127.0.0.1 --port 8545 --block-time 2

# 3. 部署（另开终端，anvil 账户 #0）
forge script script/DeployAll.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
forge script script/FixLocalHelper.s.sol --tc FixLocalHelper --rpc-url http://127.0.0.1:8545 --broadcast

# 4. 后端（复制 example 配置后按需修改合约地址）
cd backend/apps/api     && cp etc/api.example.yaml etc/api-local.yaml && go run . -f etc/api-local.yaml
cd backend/apps/indexer && cp config/config.example.yaml config/config-local.yaml && go run ./cmd/indexer -config config/config-local.yaml

# 5. 前端
cd web && pnpm install && pnpm dev   # http://127.0.0.1:5173
```

详细说明见 [web/README.md](web/README.md)。

## 核心设计

| 模块 | 要点 |
|---|---|
| 联合曲线 | 恒定乘积 x·y=k 合约内原生做市 + 虚拟储备；毕业自动加 PancakeSwap V2 流动性并销毁 LP |
| 发币流 | 后端 secp256k1 对参数签名（chainID+合约地址域分离防重放）→ 前端 `createToken(createArg, signature)` → Factory CREATE2 确定性部署 |
| Indexer | 双 goroutine（回填+WS 头订阅）、batch 自适应限流（RPC 限流减半/成功翻倍）、`ON CONFLICT` 幂等 + 断点续传、OHLCV 聚合 |
| 安全 | UUPS 可升级 + RBAC + ReentrancyGuard/Pausable + 三态防狙击状态机；Foundry fuzz（runs=1000，~4800 行测试） |
| 前端 | SIWE 登录、本地恒定乘积报价（与合约 helper 数学一致）、滑点保护、自动 approve、K线图 |

## License

MIT
