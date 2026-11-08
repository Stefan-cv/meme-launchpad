// types 包：MEME Launchpad Indexer 的事件类型定义模块
// 本文件定义了四种链上事件对应的 Go 结构体，用于在索引器各层之间传递事件数据
// 这些结构体是索引器数据流的核心数据模型：
//   indexer（解析链上日志） -> types（事件结构体） -> database（持久化到数据库）
package types

// 导入所需的包
import "math/big" // 大整数包，用于表示链上的 uint256 类型数值
// *big.Int 是必须的，因为 Solidity 的 uint256 最大值为 2^256-1，
// 远超 Go 的 int64（2^63-1）和 uint64（2^64-1）的范围
// 例如：totalSupply 可能是 10^27 级别的数值

// TokenCreatedEvent 代币创建事件结构体
// 对应 Solidity 事件：event TokenCreated(address indexed token, address indexed creator, string name, string symbol, uint256 totalSupply, bytes32 requestId)
// 当用户在内盘创建新代币时触发该事件
// json 标签用于数据库字段映射和 API JSON 序列化
type TokenCreatedEvent struct {
	TokenAddress    string   `json:"token_address"`    // 代币合约地址（0x 开头的 42 字符十六进制字符串）
	// 来源：Topics[1]（indexed 参数），经 common.BytesToAddress 转换
	// 为什么用 string 而非 common.Address：方便直接存储和 JSON 序列化

	CreatorAddress  string   `json:"creator_address"`  // 代币创建者的钱包地址
	// 来源：Topics[2]（indexed 参数）
	// 用于标识谁创建了这个代币，可用于"我的创建"等功能

	Name            string   `json:"name"`             // 代币名称，如 "Pepe Coin"
	// 来源：Data（非 indexed 参数），ABI 解码获得
	// 长度不固定，Solidity string 类型

	Symbol          string   `json:"symbol"`           // 代币符号/代码，如 "PEPE"
	// 来源：Data（非 indexed 参数），ABI 解码获得
	// 通常是大写短字符串，3-10 个字符

	TotalSupply     *big.Int `json:"total_supply"`     // 代币总供应量
	// 来源：Data（非 indexed 参数），ABI 解码获得
	// 使用 *big.Int 因为 Solidity uint256 超出 Go 原生整数范围
	// 实际值通常是 10^18 到 10^27 级别（考虑 18 位小数精度）

	RequestID       string   `json:"request_id"`       // 创建请求 ID（0x 开头的 bytes32 哈希）
	// 来源：Data（非 indexed 参数），ABI 解码获得
	// 用于关联前端的代币创建请求（用户可能先上传 logo 再创建代币）
	// 通过该 ID 可以从 token_creation_requests 表查询 logo 等附加信息

	TransactionHash string   `json:"transaction_hash"` // 交易哈希（0x 开头的 66 字符十六进制字符串）
	// 来源：vLog.TxHash
	// 唯一标识这笔链上交易，与 log_index 组合作为事件去重键

	BlockNumber     uint64   `json:"block_number"`     // 区块号
	// 来源：vLog.BlockNumber
	// 用于按区块范围查询和排序事件

	BlockTimestamp  uint64   `json:"block_timestamp"`  // 区块时间戳（Unix 秒级）
	// 来源：block.Time()（通过 RPC 查询区块头获得）
	// 用于按时间范围查询事件，是 K 线时间对齐的基准

	LogIndex        uint     `json:"log_index"`        // 日志在区块内的索引
	// 来源：vLog.Index
	// 同一区块内可能有多条日志，log_index 标识日志的顺序
	// 与 transaction_hash 组合的 UNIQUE 约束保证事件不重复
}

// TokenBoughtEvent 代币购买事件结构体
// 对应 Solidity 事件：event TokenBought(address indexed token, address indexed buyer,
//   uint256 bnbAmount, uint256 tokenAmount, uint256 tradingFee,
//   uint256 virtualBNBReserve, uint256 virtualTokenReserve,
//   uint256 availableTokens, uint256 collectedBNB)
// 当用户用 BNB 在内盘购买代币时触发该事件
type TokenBoughtEvent struct {
	TokenAddress        string   `json:"token_address"`         // 代币合约地址
	// 来源：Topics[1]（indexed 参数）

	BuyerAddress        string   `json:"buyer_address"`         // 买家钱包地址
	// 来源：Topics[2]（indexed 参数）
	// 用于"我的交易"等功能

	BnbAmount           *big.Int `json:"bnb_amount"`            // 花费的 BNB 数量（含手续费）
	// 来源：Data（非 indexed 参数）
	// 这是用户实际支付的 BNB 总额，包含交易手续费
	// 单位：wei（1 BNB = 10^18 wei）

	TokenAmount         *big.Int `json:"token_amount"`          // 获得的代币数量
	// 来源：Data（非 indexed 参数）
	// 这是用户实际收到的代币数量（扣除了手续费影响后的数量）
	// 单位：代币最小单位（通常也是 10^18）

	TradingFee          *big.Int `json:"trading_fee"`           // 交易手续费（以 BNB 计）
	// 来源：Data（非 indexed 参数）
	// 手续费从 bnbAmount 中扣除，归入平台收益
	// 用于计算净价格：净价格 = (bnbAmount - tradingFee) / tokenAmount

	VirtualBNBReserve   *big.Int `json:"virtual_bnb_reserve"`   // AMM 虚拟 BNB 储备量
	// 来源：Data（非 indexed 参数）
	// 基于恒定乘积做市商模型（x*y=k），与 virtualTokenReserve 一起决定代币价格
	// 价格 = virtualBNBReserve / virtualTokenReserve
	// 买入后 BNB 储备增加，代币储备减少，价格上涨

	VirtualTokenReserve *big.Int `json:"virtual_token_reserve"` // AMM 虚拟代币储备量
	// 来源：Data（非 indexed 参数）
	// 与 virtualBNBReserve 配对使用，反映当前 AMM 池的状态

	AvailableTokens     *big.Int `json:"available_tokens"`      // 内盘剩余可购买代币数量
	// 来源：Data（非 indexed 参数）
	// 当该值为 0 时，代币自动触发毕业（TokenGraduated）
	// 每次买入减少，每次卖出增加

	CollectedBNB        *big.Int `json:"collected_bnb"`         // 该代币累计收集的 BNB 数量
	// 来源：Data（非 indexed 参数）
	// 当该值达到 bnbTarget（默认 24 BNB = 24000000000000000000 wei）时触发毕业
	// 买入时增加，卖出时减少

	TransactionHash     string   `json:"transaction_hash"`      // 交易哈希
	BlockNumber         uint64   `json:"block_number"`          // 区块号
	BlockTimestamp      uint64   `json:"block_timestamp"`       // 区块时间戳
	LogIndex            uint     `json:"log_index"`             // 日志索引
}

// TokenSoldEvent 代币卖出事件结构体
// 对应 Solidity 事件：event TokenSold(address indexed token, address indexed seller,
//   uint256 tokenAmount, uint256 bnbAmount, uint256 tradingFee,
//   uint256 virtualBNBReserve, uint256 virtualTokenReserve,
//   uint256 availableTokens, uint256 collectedBNB)
// 当用户在内盘卖出代币获得 BNB 时触发该事件
// 结构与 TokenBoughtEvent 对称，主要区别：
//   - seller 替代 buyer
//   - tokenAmount 在前（卖出代币获得 BNB）
type TokenSoldEvent struct {
	TokenAddress        string   `json:"token_address"`         // 代币合约地址
	// 来源：Topics[1]（indexed 参数）

	SellerAddress       string   `json:"seller_address"`        // 卖家钱包地址
	// 来源：Topics[2]（indexed 参数）
	// 注意：与 TokenBoughtEvent 的 BuyerAddress 对应

	TokenAmount         *big.Int `json:"token_amount"`          // 卖出的代币数量
	// 来源：Data（非 indexed 参数）
	// 注意：Solidity 事件定义中 tokenAmount 在 bnbAmount 前面（卖出先出代币）

	BnbAmount           *big.Int `json:"bnb_amount"`            // 获得的 BNB 数量（扣手续费后）
	// 来源：Data（非 indexed 参数）
	// 这是卖家实际收到的 BNB 数量

	TradingFee          *big.Int `json:"trading_fee"`           // 交易手续费
	VirtualBNBReserve   *big.Int `json:"virtual_bnb_reserve"`   // AMM 虚拟 BNB 储备量
	// 卖出后 BNB 储备减少，代币储备增加，价格下跌

	VirtualTokenReserve *big.Int `json:"virtual_token_reserve"` // AMM 虚拟代币储备量
	AvailableTokens     *big.Int `json:"available_tokens"`      // 内盘剩余可购买代币数量
	// 卖出后代币回到内盘，该值增加

	CollectedBNB        *big.Int `json:"collected_bnb"`         // 累计收集的 BNB
	// 卖出时 BNB 流出内盘，该值减少

	TransactionHash     string   `json:"transaction_hash"`      // 交易哈希
	BlockNumber         uint64   `json:"block_number"`          // 区块号
	BlockTimestamp      uint64   `json:"block_timestamp"`       // 区块时间戳
	LogIndex            uint     `json:"log_index"`             // 日志索引
}

// TokenGraduatedEvent 代币毕业事件结构体
// 对应 Solidity 事件：event TokenGraduated(address indexed token,
//   uint256 liquidityBNB, uint256 liquidityTokens, uint256 liquidityResult)
// 当代币内盘募资达到目标后，自动迁移到 DEX 时触发
// 毕业是代币生命周期的里程碑事件：
//   - 毕业前：代币在内盘交易（基于 AMM 虚拟储备定价）
//   - 毕业后：代币在 DEX 交易（如 PancakeSwap，基于真实流动性池定价）
type TokenGraduatedEvent struct {
	TokenAddress    string   `json:"token_address"`     // 代币合约地址
	// 来源：Topics[1]（indexed 参数，唯一一个 indexed 参数）

	LiquidityBNB    *big.Int `json:"liquidity_bnb"`     // 注入 DEX 的 BNB 数量
	// 来源：Data（非 indexed 参数）
	// 这些 BNB 来自内盘募集的资金
	// 将与代币一起注入 DEX 创建流动性池

	LiquidityTokens *big.Int `json:"liquidity_tokens"`  // 注入 DEX 的代币数量
	// 来源：Data（非 indexed 参数）
	// 这些代币来自内盘剩余的代币
	// 与 BNB 按一定比例注入，形成初始价格

	LiquidityResult *big.Int `json:"liquidity_result"`  // 流动性添加结果
	// 来源：Data（非 indexed 参数）
	// 可能是 LP Token 数量或操作状态码
	// LP Token 代表在 DEX 流动性池中的份额

	TransactionHash string   `json:"transaction_hash"`  // 交易哈希
	BlockNumber     uint64   `json:"block_number"`      // 区块号
	BlockTimestamp  uint64   `json:"block_timestamp"`   // 区块时间戳
	LogIndex        uint     `json:"log_index"`         // 日志索引
}
