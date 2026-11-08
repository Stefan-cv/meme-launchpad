# ============================================================
# MEME Launchpad 构建、测试和部署命令
# ============================================================
#
# 使用方法：
#   make help           - 显示帮助信息
#   make build          - 编译合约
#   make test           - 运行所有本地测试
#   make deploy-testnet - 部署到测试网
#   make clean          - 清理构建产物
#
# ============================================================

# ============ 帮助信息 ============

.PHONY: help
help:
	@echo "MEME Launchpad 命令帮助"
	@echo ""
	@echo "构建命令："
	@echo "  make build          - 编译所有合约"
	@echo "  make clean          - 清理构建产物"
	@echo "  make fmt            - 格式化代码"
	@echo "  make fmt-check      - 检查代码格式"
	@echo ""
	@echo "测试命令："
	@echo "  make test           - 运行所有本地测试"
	@echo "  make test-v         - 运行测试（详细输出）"
	@echo "  make test-summary   - 显示测试摘要"
	@echo "  make test-gas       - 显示 gas 报告"
	@echo "  make coverage       - 生成覆盖率报告"
	@echo ""
	@echo "分模块测试："
	@echo "  make test-core      - 核心合约测试"
	@echo "  make test-vesting   - 归属功能测试"
	@echo "  make test-fee       - 费用机制测试"
	@echo "  make list-tests     - 列出所有测试"
	@echo ""
	@echo "部署命令（需要配置环境变量）："
	@echo "  make deploy-bsc-test    - 部署到 BSC 测试网"
	@echo "  make deploy-xlayer-test - 部署到 XLayer 测试网"
	@echo "  make deploy-bsc         - 部署到 BSC 主网"
	@echo "  make verify             - 验证合约"
	@echo ""
	@echo "环境变量配置："
	@echo "  PRIVATE_KEY         - 部署者私钥"
	@echo "  BSC_TEST_RPC        - BSC 测试网 RPC"
	@echo "  BSC_MAIN_RPC        - BSC 主网 RPC"
	@echo "  ETH_API_KEY         - BscScan API Key"

# ============ 基础命令 ============

# 编译所有合约
build:
	forge build

# 清理构建产物
clean:
	forge clean

# ============ 测试命令 ============

# 运行所有本地测试（排除需要 fork 的测试）
test:
	forge test --no-match-contract "BSCTest|XLayerTest"

# 运行所有本地测试（详细输出）
test-v:
	forge test --no-match-contract "BSCTest|XLayerTest" -vvv

# 运行所有本地测试（显示测试摘要表格）
test-summary:
	forge test --no-match-contract "BSCTest|XLayerTest" --summary

# 运行测试并显示 gas 报告
test-gas:
	forge test --no-match-contract "BSCTest|XLayerTest" --gas-report

# ============ 分模块测试 ============

# 核心合约测试 - 权限控制、保证金、交易限制、归属、黑名单
test-core:
	forge test --match-contract MetaNodeCoreTest -vvv

# 初始买入测试 - 预购功能、费用计算、退款机制
test-initial-buy:
	forge test --match-contract InitialBuyTest -vvv

# 归属测试 - 锁仓释放、多计划、线性/悬崖/销毁模式
test-vesting:
	forge test --match-contract VestingTest -vvv

# 费用综合测试 - 创建费、预购费、交易费
test-fee:
	forge test --match-contract ComprehensiveFeeTest -vvv

# 保证金测试 - 保证金存款、接收者设置
test-margin:
	forge test --match-contract MarginDepositTest -vvv

# 未来启动测试 - 延迟启动、启动时间限制
test-future-launch:
	forge test --match-contract FutureLaunchTest -vvv

# 计算函数测试 - calculateInitialBuyBNB 准确性
test-calculate:
	forge test --match-contract CalculateInitialBuyTest -vvv

# 预购+归属组合测试
test-vesting-prebuy:
	forge test --match-contract VestingPreBuyTest -vvv

# 靓号地址测试 - CREATE2 地址预测
test-vanity:
	forge test --match-contract VanityAddressTest -vvv

# ============ Fork 测试（需要配置 RPC）============

# BSC 测试网 fork 测试
# 需要设置环境变量：export BSC_TEST_RPC=https://data-seed-prebsc-1-s1.binance.org:8545
test-fork-bsc:
	forge test --match-contract BSCTest -vvv

# XLayer 测试网 fork 测试
# 需要设置环境变量：export XLAYER_TEST_RPC=<your_xlayer_rpc>
test-fork-xlayer:
	forge test --match-contract XLayerTest -vvv

# ============ 模糊测试 ============

# 运行模糊测试（增加运行次数）
test-fuzz:
	forge test --match-test "Fuzz" -vvv --fuzz-runs 10000

# ============ 覆盖率 ============

# 生成测试覆盖率报告
coverage:
	forge coverage --no-match-contract "BSCTest|XLayerTest"

# 生成 lcov 格式覆盖率报告
coverage-lcov:
	forge coverage --no-match-contract "BSCTest|XLayerTest" --report lcov

# ============ 部署命令 ============
# 注意：部署前需要配置以下环境变量：
#   PRIVATE_KEY    - 部署者私钥
#   BSC_TEST_RPC   - BSC 测试网 RPC（如：https://data-seed-prebsc-1-s1.binance.org:8545）
#   BSC_MAIN_RPC   - BSC 主网 RPC（如：https://bsc-dataseed.binance.org/）
#   XLAYER_TEST_RPC- XLayer 测试网 RPC
#   XLAYER_MAIN_RPC- XLayer 主网 RPC
#   ETH_API_KEY    - BscScan/Etherscan API Key（用于合约验证）

# 部署到 BSC 测试网
deploy-bsc-test:
	@echo "部署到 BSC 测试网..."
	@echo "请确保已设置 PRIVATE_KEY 和 BSC_TEST_RPC 环境变量"
	forge script script/Deploy.s.sol:DeployScript \
		--rpc-url $(BSC_TEST_RPC) \
		--broadcast \
		--verify \
		--etherscan-api-key $(ETH_API_KEY) \
		--verifier etherscan \
		--legacy \
		--slow

# 部署到 BSC 测试网（不验证合约）
deploy-bsc-test-no-verify:
	@echo "部署到 BSC 测试网（不验证）..."
	forge script script/Deploy.s.sol:DeployScript \
		--rpc-url $(BSC_TEST_RPC) \
		--broadcast \
		--legacy \
		--slow

# 部署到 XLayer 测试网
deploy-xlayer-test:
	@echo "部署到 XLayer 测试网..."
	forge script script/Deploy.s.sol:DeployScript \
		--rpc-url $(XLAYER_TEST_RPC) \
		--broadcast \
		--legacy \
		--slow

# 部署到 BSC 主网（谨慎操作！）
deploy-bsc:
	@echo "⚠️  警告：即将部署到 BSC 主网！"
	@echo "请确保已在测试网完成测试"
	@read -p "确认部署？(y/N) " confirm && [ "$$confirm" = "y" ]
	forge script script/Deploy.s.sol:DeployScript \
		--rpc-url $(BSC_MAIN_RPC) \
		--broadcast \
		--verify \
		--etherscan-api-key $(ETH_API_KEY) \
		--verifier etherscan \
		--legacy \
		--slow

# 部署到 XLayer 主网
deploy-xlayer:
	@echo "⚠️  警告：即将部署到 XLayer 主网！"
	@read -p "确认部署？(y/N) " confirm && [ "$$confirm" = "y" ]
	forge script script/Deploy.s.sol:DeployScript \
		--rpc-url $(XLAYER_MAIN_RPC) \
		--broadcast \
		--legacy \
		--slow

# ============ 升级命令 ============

# 部署新的 Core 实现合约（用于升级）
deploy-core-impl:
	@echo "部署新的 MEMECore 实现合约..."
	forge script script/DeployNewCoreImpl.s.sol:DeployNewCoreImpl \
		--rpc-url $(BSC_TEST_RPC) \
		--broadcast \
		--verify \
		--etherscan-api-key $(ETH_API_KEY) \
		--legacy

# 部署新的 Factory 合约
deploy-factory:
	@echo "部署新的 MEMEFactory 合约..."
	@echo "需要设置 MEME_CORE_ADDRESS 环境变量"
	forge script script/DeployFactory.sol:DeployFactory \
		--rpc-url $(BSC_TEST_RPC) \
		--broadcast \
		--verify \
		--etherscan-api-key $(ETH_API_KEY) \
		--legacy

# ============ 配置命令 ============

# 更新合约配置（运行 setAll）
set-config:
	@echo "更新合约配置..."
	forge script script/Deploy.s.sol:DeployScript \
		--sig "setAll()" \
		--rpc-url $(BSC_TEST_RPC) \
		--broadcast \
		--legacy

# ============ 测试调用脚本 ============

# 运行测试调用脚本
test-call:
	@echo "运行测试调用脚本..."
	forge script script/TestCall.s.sol:TestCall \
		--rpc-url $(XLAYER_TEST_RPC) \
		--broadcast \
		--legacy

# 测试地址预测
test-prediction:
	@echo "测试地址预测..."
	forge script script/TestPrediction.s.sol:TestPrediction \
		--rpc-url $(BSC_TEST_RPC)

# ============ 合约验证 ============

# 验证合约（需要设置 CONTRACT_ADDRESS 环境变量）
verify:
	@echo "验证合约..."
	forge verify-contract $(CONTRACT_ADDRESS) MetaNodeCore \
		--chain-id 97 \
		--etherscan-api-key $(ETH_API_KEY) \
		--watch

# ============ 辅助命令 ============

# 显示所有测试合约
list-tests:
	@echo "测试合约列表："
	@echo "  - MetaNodeCoreTest    : 核心合约测试"
	@echo "  - InitialBuyTest      : 初始买入测试"
	@echo "  - VestingTest         : 归属功能测试"
	@echo "  - ComprehensiveFeeTest: 费用机制测试"
	@echo "  - MarginDepositTest   : 保证金测试"
	@echo "  - FutureLaunchTest    : 延迟启动测试"
	@echo "  - CalculateInitialBuyTest: 计算函数测试"
	@echo "  - VestingPreBuyTest   : 预购+归属测试"
	@echo "  - VanityAddressTest   : 靓号地址测试"
	@echo "  - BSCTest             : BSC Fork测试 (需要RPC)"
	@echo "  - XLayerTest          : XLayer Fork测试 (需要RPC)"

# 格式化代码
fmt:
	forge fmt

# 检查代码格式
fmt-check:
	forge fmt --check

# 安装依赖
install:
	forge install OpenZeppelin/openzeppelin-contracts
	forge install OpenZeppelin/openzeppelin-contracts-upgradeable
	forge install foundry-rs/forge-std

# 更新依赖
update:
	forge update

.PHONY: build clean test test-v test-summary test-gas \
        test-core test-initial-buy test-vesting test-fee test-margin \
        test-future-launch test-calculate test-vesting-prebuy test-vanity \
        test-fork-bsc test-fork-xlayer test-fuzz \
        coverage coverage-lcov list-tests fmt fmt-check \
        deploy-bsc-test deploy-bsc-test-no-verify deploy-xlayer-test \
        deploy-bsc deploy-xlayer deploy-core-impl deploy-factory \
        set-config test-call test-prediction verify install update help
