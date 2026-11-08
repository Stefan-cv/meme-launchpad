# MEME Launchpad · TS 前端（本地演示）

Vite + React + TypeScript + **ethers v6** 实现的 MEME 发射平台前端，对接本地 anvil 链、Go API 服务与 Indexer。

## 功能

- **钱包连接**：MetaMask（自动添加/切换 Anvil 31337 网络）+ Dev 钱包（anvil 预置账户，本地演示免装插件）；顶栏实时显示 ETH 余额、点击地址复制
- **SIWE 登录**：`GET /user/sign-msg` → 钱包 EIP-191 签名 → `POST /user/wallet-login` 换 JWT
- **发币**：`POST /token/create-token`（后端 ECDSA 签名 + CREATE2 预测地址）→ 链上 `Core.createToken(createArg, signature)`，支付 0.05 ETH 创建费；emoji 快捷选择、三步流程日志 + Toast 通知
- **代币市场**：每 5s 轮询 `/token/token-list`（Indexer 同步链上事件后自动出现新代币）；支持关键词搜索（名称/符号/地址）与排序（最新/募资/名称）
- **交易面板**：
  - 当前价格（虚拟储备比）+ 曲线储备四项指标，链上 `getBondingCurve` 实时读取
  - **K 线图**（lightweight-charts）：蜡烛 + 成交量，1m/5m/15m/1h/4h/1d 周期切换，数据来自 Indexer 的 OHLCV 聚合
  - 本地恒定乘积报价（与合约 helper 数学一致，含 1% 手续费），10% 滑点保护，快捷金额按钮
  - 买入：`Core.buy(token, minOut, deadline) {value}`；卖出：不足额度时自动 `ERC20.approve` → `Core.sell`
  - 最近交易：`/trade/list`（Indexer 同步），含方向徽章 / 交易哈希 / 相对时间
- **持仓展示**：ERC20 `balanceOf` 实时读取，MAX 一键填入

## 目录结构

```
src/
  config.ts               # RPC / API 地址 / 合约地址 / Dev 私钥（仅本地）
  abi/core.json           # 从 foundry out/ 提取的 MetaNodeCore ABI
  utils/format.ts         # 集中的数字/时间/地址格式化（wei→ETH、科学计数价格、相对时间）
  hooks/usePolling.ts     # 通用轮询 hook（列表/曲线/K线共用）
  lib/
    api.ts                # Go API 客户端（SIWE、发币签名、列表、交易、K线）
    wallet.tsx            # 钱包 Context（injected + dev 两种模式）
    chain.ts              # 合约交互 + 联合曲线报价数学
  components/
    Header.tsx            # 连接钱包 / ETH 余额 / 复制地址
    CreateTokenForm.tsx   # 发币表单（emoji 选择 + 三步流程日志）
    TokenList.tsx         # 代币市场（搜索 / 排序 / 实时徽标）
    TradePanel.tsx        # 交易弹窗（价格/曲线/K线/买卖/持仓/成交）
    KlineChart.tsx        # lightweight-charts 蜡烛图封装
    Toast.tsx             # 轻量 Toast 通知
```

## 本地一键启动

依赖：foundry（anvil/forge/cast）、go 1.24+、node 20+、PostgreSQL 17、Redis（本机 brew 服务）。

```bash
# 1. 数据库（首次）
createdb metaland -O postgres
psql metaland -f ../meme-launchpad-back-main/sql/metaland_2026-01-10_014823.sql
psql metaland -c "INSERT INTO nonce_sequence (chain_id, current_nonce) VALUES (31337, 0)"

# 2. anvil 本地链（2s 出块）
anvil --host 127.0.0.1 --port 8545 --block-time 2

# 3. 部署合约（另开终端）
cd ../meme-launchpad-main
PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  forge script script/DeployAll.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  forge script script/FixLocalHelper.s.sol --tc FixLocalHelper --rpc-url http://127.0.0.1:8545 --broadcast
#    （FixLocalHelper 部署 mock Pancake Router 并切换 Core 的 Helper，否则 getPairAddress 会 revert）

# 4. Go 后端（配置已指向本地链：api-local.yaml / config-local.yaml）
cd ../meme-launchpad-back-main/apps/api     && go run . -f etc/api-local.yaml          # :38080
cd ../meme-launchpad-back-main/apps/indexer && go run ./cmd/indexer -config config/config-local.yaml

# 5. 前端
pnpm install && pnpm dev   # http://127.0.0.1:5173
```

合约地址（anvil 上重复部署会变化，需同步更新 `src/config.ts` 与两个后端 local 配置）：

| 合约 | 地址 |
|---|---|
| MetaNodeCore | 0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9 |
| MEMEFactory | 0x5FbDB2315678afecb367f032d93F642f64180aa3 |
| MEMEHelper（本地 mock 版） | 0x0B306BF915C4d645ff596e518fAf3F9669b97016 |

## 使用流程

1. 点「Dev 钱包」连接（或 MetaMask 导入 anvil 账户）
2. 左侧表单填名称/符号/emoji → 「🚀 发射代币」→ 日志显示 SIWE 登录 → 后端签名 → 链上部署
3. 等 ~5s，右侧列表出现新代币 → 点击卡片打开交易面板
4. 买入（默认 0.1 ETH）→ 持仓显示 → MAX 卖出（自动 approve）
5. 面板下方「最近交易」由 Indexer 同步链上 TokenBought/TokenSold 事件生成

## 已知限制（本地演示）

- 后端 `TokenBytecode` 配置是 BSC 旧编译产物，CREATE2 **预测地址**与实际部署地址不一致（不影响发币与交易）
- 毕业（迁移 PancakeSwap 流动性）走 mock router，不可用——本地仅演示联合曲线内盘
- `price` / `usdAmount` 无喂价，为 0 / null
