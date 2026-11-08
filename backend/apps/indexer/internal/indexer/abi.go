// indexer 包：MEME Token Launchpad Indexer 的合约 ABI 定义
// 本文件定义了 MEMECore 智能合约的事件 ABI（Application Binary Interface）
// ABI 是 Solidity 合约与外部世界交互的接口描述，包含函数和事件的参数类型信息
// 索引器使用该 ABI 定义来：
// 1. 匹配合约日志中的事件类型（通过 Topics[0] 事件签名哈希）
// 2. 解码日志 Data 部分中的非索引参数（通过 UnpackIntoInterface）
package indexer

// MEMECoreABI MEMECore 合约的 ABI 定义（仅包含需要解析的事件）
// 该常量以 JSON 数组格式定义了四种核心事件：
//   - TokenCreated: 代币创建事件，当代币在内盘首次创建时触发
//   - TokenBought: 代币购买事件，当用户用 BNB 购买代币时触发
//   - TokenSold: 代币卖出事件，当用户卖出代币获得 BNB 时触发
//   - TokenGraduated: 代币毕业事件，当内盘募资达标并迁移到 DEX 时触发
// 注意：该 ABI 仅包含事件定义，不包含函数定义，因为索引器只需要解析事件
	const MEMECoreABI = `[
		{
			"anonymous": false,
			"inputs": [
				{"indexed": true, "internalType": "address", "name": "token", "type": "address"},
				{"indexed": true, "internalType": "address", "name": "creator", "type": "address"},
				{"indexed": false, "internalType": "string", "name": "name", "type": "string"},
				{"indexed": false, "internalType": "string", "name": "symbol", "type": "string"},
				{"indexed": false, "internalType": "uint256", "name": "totalSupply", "type": "uint256"},
				{"indexed": false, "internalType": "bytes32", "name": "requestId", "type": "bytes32"}
			],
			"name": "TokenCreated",
			"type": "event"
		},
		{
			"anonymous": false,
			"inputs": [
				{"indexed": true, "internalType": "address", "name": "token", "type": "address"},
				{"indexed": true, "internalType": "address", "name": "buyer", "type": "address"},
				{"indexed": false, "internalType": "uint256", "name": "bnbAmount", "type": "uint256"},
				{"indexed": false, "internalType": "uint256", "name": "tokenAmount", "type": "uint256"},
				{"indexed": false, "internalType": "uint256", "name": "tradingFee", "type": "uint256"},
				{"indexed": false, "internalType": "uint256", "name": "virtualBNBReserve", "type": "uint256"},
				{"indexed": false, "internalType": "uint256", "name": "virtualTokenReserve", "type": "uint256"},
				{"indexed": false, "internalType": "uint256", "name": "availableTokens", "type": "uint256"},
				{"indexed": false, "internalType": "uint256", "name": "collectedBNB", "type": "uint256"}
			],
			"name": "TokenBought",
			"type": "event"
		},
		{
			"anonymous": false,
			"inputs": [
				{"indexed": true, "internalType": "address", "name": "token", "type": "address"},
				{"indexed": true, "internalType": "address", "name": "seller", "type": "address"},
				{"indexed": false, "internalType": "uint256", "name": "tokenAmount", "type": "uint256"},
				{"indexed": false, "internalType": "uint256", "name": "bnbAmount", "type": "uint256"},
				{"indexed": false, "internalType": "uint256", "name": "tradingFee", "type": "uint256"},
				{"indexed": false, "internalType": "uint256", "name": "virtualBNBReserve", "type": "uint256"},
				{"indexed": false, "internalType": "uint256", "name": "virtualTokenReserve", "type": "uint256"},
				{"indexed": false, "internalType": "uint256", "name": "availableTokens", "type": "uint256"},
				{"indexed": false, "internalType": "uint256", "name": "collectedBNB", "type": "uint256"}
			],
			"name": "TokenSold",
			"type": "event"
		},
		{
			"anonymous": false,
			"inputs": [
				{"indexed": true, "internalType": "address", "name": "token", "type": "address"},
				{"indexed": false, "internalType": "uint256", "name": "liquidityBNB", "type": "uint256"},
				{"indexed": false, "internalType": "uint256", "name": "liquidityTokens", "type": "uint256"},
				{"indexed": false, "internalType": "uint256", "name": "liquidityResult", "type": "uint256"}
			],
			"name": "TokenGraduated",
			"type": "event"
		}
	]`
