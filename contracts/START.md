# 🚀 MEME Launchpad 快速启动指南

## 📋 项目简介

MEME Launchpad 是一个去中心化的 MEME 代币发射平台，基于联合曲线（Bonding Curve）实现公平发射机制。

### 核心功能
- **联合曲线定价** - 基于恒定乘积公式 `k = x * y` 自动定价
- **初始买入（Pre-buy）** - 创建者可预购最高 99.9% 代币
- **归属计划（Vesting）** - 支持线性释放、悬崖释放、销毁三种模式
- **保证金机制** - 创建者可缴纳保证金增加可信度
- **延迟启动** - 支持设置未来启动时间
- **毕业机制** - 代币达标后自动添加 DEX 流动性

---

## 🛠️ 环境准备

### 1. 安装 Foundry

```bash
# 安装 Foundry
curl -L https://foundry.paradigm.xyz | bash

# 更新到最新版本
foundryup
```

### 2. 克隆项目并安装依赖

```bash
# 克隆项目
git clone <your-repo-url>
cd meme-launchpad

# 安装依赖（如果 lib/ 目录不存在）
make install
# 或手动安装
forge install OpenZeppelin/openzeppelin-contracts
forge install OpenZeppelin/openzeppelin-contracts-upgradeable
forge install foundry-rs/forge-std
```

---

## 🔨 编译合约

```bash
# 编译所有合约
make build

# 或直接使用 forge
forge build
```

---

## 🧪 运行测试

### 运行所有本地测试

```bash
# 快速测试
make test

# 详细输出
make test-v

# 显示测试摘要
make test-summary

# 显示 Gas 消耗报告
make test-gas
```

### 分模块测试

```bash
make test-core           # 核心合约测试（权限、保证金、交易限制）
make test-initial-buy    # 初始买入测试
make test-vesting        # 归属功能测试（锁仓释放）
make test-fee            # 费用机制测试
make test-margin         # 保证金测试
make test-future-launch  # 延迟启动测试
make test-calculate      # 联合曲线计算测试
make test-vesting-prebuy # 预购+归属组合测试
make test-vanity         # 靓号地址测试
```

### Fork 测试（需要 RPC）

```bash
# 设置环境变量
export BSC_TEST_RPC=https://data-seed-prebsc-1-s1.binance.org:8545

# 运行 BSC 测试网 fork 测试
make test-fork-bsc
```

---

## 📦 合约部署

### 1. 配置环境变量

创建 `.env` 文件：

```bash
# 私钥（不要提交到 Git！）
PRIVATE_KEY=your_private_key_here

# RPC 地址
BSC_TEST_RPC=https://data-seed-prebsc-1-s1.binance.org:8545
BSC_MAIN_RPC=https://bsc-dataseed.binance.org/
XLAYER_TEST_RPC=your_xlayer_test_rpc
XLAYER_MAIN_RPC=your_xlayer_main_rpc

# 区块浏览器 API Key（用于验证合约）
ETH_API_KEY=your_bscscan_api_key_here
```

加载环境变量：

```bash
source .env
```

### 2. 配置部署参数

创建部署配置文件 `deploy-config/{chain}/{env}.json`：

```json
{
  "Admin": "0x...",              
  "Signer": "0x...",             
  "PlatformFeeReceiver": "0x...",
  "MarginReceiver": "0x...",     
  "GraduateFeeReceiver": "0x...",
  "Router": "0xD99D1c33F9fC3444f8101754aBC46c52416550D1",
  "WBNB": "0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd",
  "MinLockTime": 86400,
  "MEMEHelper": "",
  "MEMEFactory": "",
  "MEMECore": "",
  "MEMEVesting": ""
}
```

配置说明：
| 字段 | 说明 |
|------|------|
| Admin | 管理员地址（最高权限） |
| Signer | 签名者地址（验证创建请求） |
| PlatformFeeReceiver | 平台费用接收地址 |
| MarginReceiver | 保证金接收地址 |
| GraduateFeeReceiver | 毕业费用接收地址 |
| Router | PancakeSwap V2 Router 地址 |
| WBNB | WBNB 合约地址 |
| MinLockTime | 最小锁仓时间（秒） |

### 3. 修改部署脚本网络配置

编辑 `script/Deploy.s.sol`，设置目标网络：

```solidity
function setUp() public override {
    // 取消注释目标网络
    projectName = "bnb_test/";      // BSC 测试网
    // projectName = "bnb/";        // BSC 主网
    // projectName = "xlayer_test/";// XLayer 测试网
    
    environment = "dev";            // 或 test/pre/prod
    super.setUp();
    // ...
}
```

### 4. 执行部署

#### 使用 Makefile（推荐）

```bash
# 部署到 BSC 测试网
make deploy-bsc-test

# 部署到 BSC 测试网（不验证合约）
make deploy-bsc-test-no-verify

# 部署到 XLayer 测试网
make deploy-xlayer-test

# 部署到 BSC 主网（谨慎！）
make deploy-bsc
```

#### 手动运行部署脚本

```bash
# BSC 测试网部署
forge script script/Deploy.s.sol:DeployScript \
    --rpc-url $BSC_TEST_RPC \
    --broadcast \
    --verify \
    --etherscan-api-key $ETH_API_KEY \
    --verifier etherscan \
    --legacy \
    --slow

# XLayer 测试网部署（无验证）
forge script script/Deploy.s.sol:DeployScript \
    --rpc-url $XLAYER_TEST_RPC \
    --broadcast \
    --legacy \
    --slow
```

### 5. 部署后配置

部署完成后，运行配置脚本确保所有权限正确设置：

```bash
make set-config
```

---

## 🔄 合约升级

### 升级 Core 合约

1. 部署新的实现合约：

```bash
make deploy-core-impl
```

2. 通过管理员/多签调用升级：

```solidity
// 在已部署的代理合约上调用
proxy.upgradeToAndCall(newImplementation, "")
```

### 部署新 Factory

```bash
export MEME_CORE_ADDRESS=0x...  # 设置 Core 地址
make deploy-factory
```

---

## 📁 项目结构

```
meme-launchpad/
├── src/                          # 源代码
│   ├── MEMECore.sol             # 核心合约（代币创建、买卖、毕业）
│   ├── MEMEFactory.sol          # 工厂合约（CREATE2 部署代币）
│   ├── MEMEHelper.sol           # 辅助合约（曲线计算、DEX 交互）
│   ├── MEMEVesting.sol          # 归属合约（锁仓释放）
│   ├── MEMEToken.sol            # 代币合约（ERC20 + 转账限制）
│   └── interfaces/              # 接口定义
│       ├── IMEMECore.sol
│       ├── IMEMEFactory.sol
│       ├── IMEMEHelper.sol
│       ├── IMEMEVesting.sol
│       ├── IBondingCurveParams.sol
│       └── IVestingParams.sol
├── test/                         # 测试代码
│   ├── MEMECore.t.sol           # 核心合约测试
│   ├── InitialBuy.t.sol         # 初始买入测试
│   ├── Vesting.t.sol            # 归属功能测试
│   ├── ComprehensiveFeeTest.t.sol # 费用测试
│   └── mocks/                   # 模拟合约
├── script/                       # 部署脚本
│   ├── Deploy.s.sol             # 主部署脚本
│   ├── DeployConfig.s.sol       # 配置管理
│   ├── Deployer.sol             # 部署器基类
│   ├── Chains.sol               # 链信息管理
│   ├── DeployNewCoreImpl.s.sol  # Core 升级脚本
│   ├── DeployFactory.sol        # Factory 部署脚本
│   └── TestCall.s.sol           # 功能测试脚本
├── deploy-config/               # 部署配置文件
│   ├── bnb_test/               # BSC 测试网配置
│   │   └── dev.json
│   ├── bnb/                    # BSC 主网配置
│   │   └── prod.json
│   └── xlayer_test/            # XLayer 测试网配置
├── deployments/                 # 部署记录
├── lib/                         # 依赖库
├── Makefile                     # 常用命令
└── foundry.toml                 # Foundry 配置
```

---

## 📊 费用说明

| 费用类型 | 说明 | 默认值 |
|---------|------|--------|
| creationFee | 创建代币固定费用 | 0.01 BNB |
| preBuyFeeRate | 预购手续费率 | 1% (100/10000) |
| tradingFeeRate | 交易手续费率 | 1% (100/10000) |
| platformGraduationFeeRate | 毕业平台费率 | 5.5% (550/10000) |
| creatorGraduationFeeRate | 毕业创建者费率 | 2.5% (250/10000) |

---

## 🔗 常用命令速查

### 构建与测试

```bash
# 编译
make build

# 测试
make test                # 运行所有测试
make test-v              # 详细输出
make test-summary        # 测试摘要

# 单独测试某个合约
forge test --match-contract MetaNodeCoreTest -vvv

# 单独测试某个函数
forge test --match-test testCreateTokenWithMargin -vvv

# 覆盖率报告
make coverage

# 格式化代码
make fmt
```

### 部署与配置

```bash
# 部署到 BSC 测试网
make deploy-bsc-test

# 部署到 XLayer 测试网
make deploy-xlayer-test

# 更新配置
make set-config

# 部署 Core 升级
make deploy-core-impl

# 运行测试脚本
make test-call
```

### 帮助信息

```bash
# 显示所有可用命令
make help

# 显示所有测试合约
make list-tests
```

---

## 🌐 支持的网络

| 网络 | Chain ID | 说明 |
|------|----------|------|
| BSC 主网 | 56 | BNB Chain |
| BSC 测试网 | 97 | BNB Testnet |
| XLayer 主网 | 196 | XLayer |
| XLayer 测试网 | 1952 | XLayer Testnet |
| Base 主网 | 8453 | Base |
| Base Sepolia | 84532 | Base 测试网 |

---

## ⚠️ 注意事项

1. **私钥安全** - 永远不要将私钥提交到 Git 仓库
2. **测试优先** - 主网部署前务必在测试网完整测试
3. **合约验证** - 部署后及时在区块浏览器验证合约源码
4. **权限管理** - 部署后及时转移管理员权限到多签钱包
5. **配置检查** - 部署前仔细检查配置文件中的地址
6. **升级谨慎** - UUPS 升级需要管理员权限，升级前备份

---

## 📞 联系方式

如有问题，请提交 Issue 或联系开发团队。
