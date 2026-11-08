-- 用户表
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    address VARCHAR(42) NOT NULL UNIQUE,
    username VARCHAR(100),
    email VARCHAR(255),
    avatar VARCHAR(500),
    nonce VARCHAR(64),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_users_address ON users(LOWER(address));

-- 代币表
CREATE TABLE IF NOT EXISTS tokens (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    symbol VARCHAR(50) NOT NULL,
    logo VARCHAR(500) NOT NULL,
    banner VARCHAR(500),
    description TEXT,
    token_contract_address VARCHAR(42) NOT NULL UNIQUE,
    creator_address VARCHAR(42) NOT NULL,
    launch_mode INTEGER NOT NULL DEFAULT 1,
    launch_time BIGINT NOT NULL,
    bnb_current NUMERIC(78, 0) DEFAULT 0,
    bnb_target NUMERIC(78, 0) NOT NULL,
    available_tokens NUMERIC(78, 0) DEFAULT 0,
    margin_bnb NUMERIC(78, 0) DEFAULT 0,
    total_supply NUMERIC(78, 0) NOT NULL,
    status INTEGER DEFAULT 1,
    website VARCHAR(500),
    twitter VARCHAR(500),
    telegram VARCHAR(500),
    discord VARCHAR(500),
    whitepaper VARCHAR(500),
    tags TEXT[],
    hot INTEGER DEFAULT 0,
    token_lv INTEGER DEFAULT 0,
    token_rank INTEGER DEFAULT 0,
    request_id VARCHAR(66),
    nonce INTEGER NOT NULL,
    salt VARCHAR(66),
    pre_buy_percent NUMERIC(5, 4) DEFAULT 0,
    margin_time BIGINT DEFAULT 0,
    contact_email VARCHAR(255),
    contact_tg VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_tokens_address ON tokens(LOWER(token_contract_address));
CREATE INDEX IF NOT EXISTS idx_tokens_creator ON tokens(LOWER(creator_address));
CREATE INDEX IF NOT EXISTS idx_tokens_status ON tokens(status);
CREATE INDEX IF NOT EXISTS idx_tokens_launch_mode ON tokens(launch_mode);
CREATE INDEX IF NOT EXISTS idx_tokens_hot ON tokens(hot DESC);
CREATE INDEX IF NOT EXISTS idx_tokens_created_at ON tokens(created_at DESC);

-- 代币余额表
CREATE TABLE IF NOT EXISTS token_balances (
    id SERIAL PRIMARY KEY,
    token_address VARCHAR(42) NOT NULL,
    holder_address VARCHAR(42) NOT NULL,
    balance NUMERIC(78, 0) NOT NULL DEFAULT 0,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(token_address, holder_address)
);

CREATE INDEX IF NOT EXISTS idx_token_balances_token ON token_balances(LOWER(token_address));
CREATE INDEX IF NOT EXISTS idx_token_balances_holder ON token_balances(LOWER(holder_address));
CREATE INDEX IF NOT EXISTS idx_token_balances_balance ON token_balances(balance DESC);

-- 用户收藏表
CREATE TABLE IF NOT EXISTS user_favorites (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id),
    token_id INTEGER NOT NULL REFERENCES tokens(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, token_id)
);

CREATE INDEX IF NOT EXISTS idx_user_favorites_user ON user_favorites(user_id);
CREATE INDEX IF NOT EXISTS idx_user_favorites_token ON user_favorites(token_id);

-- 交易记录表
CREATE TABLE IF NOT EXISTS trades (
    id SERIAL PRIMARY KEY,
    token_address VARCHAR(42) NOT NULL,
    user_address VARCHAR(42) NOT NULL,
    trade_type INTEGER NOT NULL, -- 10=买入, 20=卖出
    bnb_amount NUMERIC(78, 0) NOT NULL,
    token_amount NUMERIC(78, 0) NOT NULL,
    price NUMERIC(78, 18) NOT NULL,
    usd_amount NUMERIC(18, 2),
    transaction_hash VARCHAR(66) NOT NULL,
    block_number BIGINT NOT NULL,
    block_timestamp TIMESTAMP NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(transaction_hash, trade_type)
);

CREATE INDEX IF NOT EXISTS idx_trades_token ON trades(LOWER(token_address));
CREATE INDEX IF NOT EXISTS idx_trades_user ON trades(LOWER(user_address));
CREATE INDEX IF NOT EXISTS idx_trades_timestamp ON trades(block_timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_trades_type ON trades(trade_type);

-- 评论表
CREATE TABLE IF NOT EXISTS comments (
    id SERIAL PRIMARY KEY,
    token_id INTEGER NOT NULL REFERENCES tokens(id),
    user_id INTEGER NOT NULL REFERENCES users(id),
    content TEXT,
    img VARCHAR(500),
    holding_amount NUMERIC(78, 0) DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_comments_token ON comments(token_id);
CREATE INDEX IF NOT EXISTS idx_comments_user ON comments(user_id);
CREATE INDEX IF NOT EXISTS idx_comments_created_at ON comments(created_at DESC);

-- 活动表
CREATE TABLE IF NOT EXISTS activities (
    id SERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    description TEXT,
    category_type INTEGER NOT NULL,
    play_type INTEGER NOT NULL,
    reward_token_type INTEGER NOT NULL,
    reward_amount VARCHAR(78) NOT NULL,
    reward_slots VARCHAR(20) NOT NULL,
    start_at TIMESTAMP NOT NULL,
    end_at TIMESTAMP NOT NULL,
    cover_image VARCHAR(500),
    token_id INTEGER REFERENCES tokens(id),
    initiator_type INTEGER NOT NULL,
    audience_type INTEGER NOT NULL,
    creator_id INTEGER REFERENCES users(id),
    status INTEGER DEFAULT 1,
    min_daily_trade_amount VARCHAR(78),
    invite_min_count VARCHAR(20),
    invitee_min_trade_amount VARCHAR(78),
    heat_vote_target VARCHAR(20),
    comment_min_count VARCHAR(20),
    reward_token_id INTEGER,
    reward_token_address VARCHAR(42),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_activities_status ON activities(status);
CREATE INDEX IF NOT EXISTS idx_activities_creator ON activities(creator_id);
CREATE INDEX IF NOT EXISTS idx_activities_token ON activities(token_id);

-- 活动参与记录表
CREATE TABLE IF NOT EXISTS activity_participations (
    id SERIAL PRIMARY KEY,
    activity_id INTEGER NOT NULL REFERENCES activities(id),
    user_id INTEGER NOT NULL REFERENCES users(id),
    status INTEGER DEFAULT 1,
    reward_claimed BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(activity_id, user_id)
);

-- 代理表
CREATE TABLE IF NOT EXISTS agents (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id),
    address VARCHAR(42) NOT NULL UNIQUE,
    invitation_code VARCHAR(20) NOT NULL UNIQUE,
    level INTEGER DEFAULT 1,
    parent_id INTEGER REFERENCES agents(id),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_agents_address ON agents(LOWER(address));
CREATE INDEX IF NOT EXISTS idx_agents_code ON agents(invitation_code);
CREATE INDEX IF NOT EXISTS idx_agents_parent ON agents(parent_id);

-- 邀请记录表
CREATE TABLE IF NOT EXISTS invites (
    id SERIAL PRIMARY KEY,
    inviter_id INTEGER NOT NULL REFERENCES users(id),
    invitee_id INTEGER NOT NULL REFERENCES users(id),
    inviter_address VARCHAR(42) NOT NULL,
    invitee_address VARCHAR(42) NOT NULL,
    invitation_code VARCHAR(20) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(invitee_id)
);

CREATE INDEX IF NOT EXISTS idx_invites_inviter ON invites(inviter_id);
CREATE INDEX IF NOT EXISTS idx_invites_inviter_addr ON invites(LOWER(inviter_address));

-- 返佣记录表
CREATE TABLE IF NOT EXISTS rebate_records (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id),
    trader_id INTEGER NOT NULL REFERENCES users(id),
    user_address VARCHAR(42) NOT NULL,
    amount NUMERIC(18, 8) NOT NULL,
    status INTEGER DEFAULT 0, -- 0=待发放, 1=已发放
    tx_hash VARCHAR(66),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_rebate_user ON rebate_records(user_id);
CREATE INDEX IF NOT EXISTS idx_rebate_address ON rebate_records(LOWER(user_address));
CREATE INDEX IF NOT EXISTS idx_rebate_status ON rebate_records(status);

-- K线数据表 (分区表，按时间分区)
CREATE TABLE IF NOT EXISTS klines (
    id SERIAL,
    token_address VARCHAR(42) NOT NULL,
    interval VARCHAR(10) NOT NULL, -- 1m, 5m, 15m, 1h, 4h, 1d, 1w
    open_time TIMESTAMP NOT NULL,
    open_price NUMERIC(78, 18) NOT NULL,
    high_price NUMERIC(78, 18) NOT NULL,
    low_price NUMERIC(78, 18) NOT NULL,
    close_price NUMERIC(78, 18) NOT NULL,
    volume NUMERIC(78, 0) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id, open_time),
    UNIQUE(token_address, interval, open_time)
);

CREATE INDEX IF NOT EXISTS idx_klines_token_interval ON klines(LOWER(token_address), interval, open_time DESC);

-- ==================== 扫链事件表 (来自 indexer) ====================

-- Token creation events table (从链上扫描)
CREATE TABLE IF NOT EXISTS token_created_events (
    id SERIAL PRIMARY KEY,
    token_address VARCHAR(42) NOT NULL,
    creator_address VARCHAR(42) NOT NULL,
    name VARCHAR(255) NOT NULL,
    symbol VARCHAR(50) NOT NULL,
    total_supply NUMERIC(78, 0) NOT NULL,
    request_id VARCHAR(66) NOT NULL,
    transaction_hash VARCHAR(66) NOT NULL,
    block_number BIGINT NOT NULL,
    block_timestamp TIMESTAMP NOT NULL,
    log_index INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(transaction_hash, log_index)
);

CREATE INDEX IF NOT EXISTS idx_token_created_token_address ON token_created_events(LOWER(token_address));
CREATE INDEX IF NOT EXISTS idx_token_created_creator ON token_created_events(LOWER(creator_address));
CREATE INDEX IF NOT EXISTS idx_token_created_block ON token_created_events(block_number);
CREATE INDEX IF NOT EXISTS idx_token_created_request_id ON token_created_events(request_id);

-- Token buy events table (从链上扫描)
CREATE TABLE IF NOT EXISTS token_bought_events (
    id SERIAL PRIMARY KEY,
    token_address VARCHAR(42) NOT NULL,
    buyer_address VARCHAR(42) NOT NULL,
    bnb_amount NUMERIC(78, 0) NOT NULL,
    token_amount NUMERIC(78, 0) NOT NULL,
    trading_fee NUMERIC(78, 0) DEFAULT 0,
    virtual_bnb_reserve NUMERIC(78, 0) DEFAULT 0,
    virtual_token_reserve NUMERIC(78, 0) DEFAULT 0,
    available_tokens NUMERIC(78, 0) DEFAULT 0,
    collected_bnb NUMERIC(78, 0) DEFAULT 0,
    transaction_hash VARCHAR(66) NOT NULL,
    block_number BIGINT NOT NULL,
    block_timestamp TIMESTAMP NOT NULL,
    log_index INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(transaction_hash, log_index)
);

CREATE INDEX IF NOT EXISTS idx_token_bought_token_address ON token_bought_events(LOWER(token_address));
CREATE INDEX IF NOT EXISTS idx_token_bought_buyer ON token_bought_events(LOWER(buyer_address));
CREATE INDEX IF NOT EXISTS idx_token_bought_block ON token_bought_events(block_number);
CREATE INDEX IF NOT EXISTS idx_token_bought_timestamp ON token_bought_events(block_timestamp DESC);

-- Token sell events table (从链上扫描)
CREATE TABLE IF NOT EXISTS token_sold_events (
    id SERIAL PRIMARY KEY,
    token_address VARCHAR(42) NOT NULL,
    seller_address VARCHAR(42) NOT NULL,
    token_amount NUMERIC(78, 0) NOT NULL,
    bnb_amount NUMERIC(78, 0) NOT NULL,
    trading_fee NUMERIC(78, 0) DEFAULT 0,
    virtual_bnb_reserve NUMERIC(78, 0) DEFAULT 0,
    virtual_token_reserve NUMERIC(78, 0) DEFAULT 0,
    available_tokens NUMERIC(78, 0) DEFAULT 0,
    collected_bnb NUMERIC(78, 0) DEFAULT 0,
    transaction_hash VARCHAR(66) NOT NULL,
    block_number BIGINT NOT NULL,
    block_timestamp TIMESTAMP NOT NULL,
    log_index INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(transaction_hash, log_index)
);

CREATE INDEX IF NOT EXISTS idx_token_sold_token_address ON token_sold_events(LOWER(token_address));
CREATE INDEX IF NOT EXISTS idx_token_sold_seller ON token_sold_events(LOWER(seller_address));
CREATE INDEX IF NOT EXISTS idx_token_sold_block ON token_sold_events(block_number);
CREATE INDEX IF NOT EXISTS idx_token_sold_timestamp ON token_sold_events(block_timestamp DESC);

-- Token graduated events table (从链上扫描)
CREATE TABLE IF NOT EXISTS token_graduated_events (
    id SERIAL PRIMARY KEY,
    token_address VARCHAR(42) NOT NULL,
    liquidity_bnb NUMERIC(78, 0) NOT NULL,
    liquidity_tokens NUMERIC(78, 0) NOT NULL,
    liquidity_result NUMERIC(78, 0) NOT NULL,
    transaction_hash VARCHAR(66) NOT NULL,
    block_number BIGINT NOT NULL,
    block_timestamp TIMESTAMP NOT NULL,
    log_index INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(transaction_hash, log_index)
);

CREATE INDEX IF NOT EXISTS idx_token_graduated_token_address ON token_graduated_events(LOWER(token_address));
CREATE INDEX IF NOT EXISTS idx_token_graduated_block ON token_graduated_events(block_number);

-- Indexer state table (to track last synced block)
CREATE TABLE IF NOT EXISTS indexer_state (
    id SERIAL PRIMARY KEY,
    contract_address VARCHAR(42) NOT NULL,
    last_block_number BIGINT NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(contract_address)
);

-- ==================== 创建代币请求表 ====================

-- 创建代币请求记录 (用于追踪创建代币的请求状态)
CREATE TABLE IF NOT EXISTS token_creation_requests (
    id SERIAL PRIMARY KEY,
    request_id VARCHAR(66) NOT NULL UNIQUE,
    creator_address VARCHAR(42) NOT NULL,
    name VARCHAR(100) NOT NULL,
    symbol VARCHAR(50) NOT NULL,
    description TEXT,
    logo VARCHAR(500),
    banner VARCHAR(500),
    total_supply NUMERIC(78, 0) NOT NULL,
    sale_amount NUMERIC(78, 0) NOT NULL,
    virtual_bnb_reserve NUMERIC(78, 0) NOT NULL,
    virtual_token_reserve NUMERIC(78, 0) NOT NULL,
    launch_mode INTEGER NOT NULL DEFAULT 1,
    launch_time BIGINT NOT NULL DEFAULT 0,
    creation_fee NUMERIC(78, 0) DEFAULT 0,
    nonce INTEGER NOT NULL,
    salt VARCHAR(66),
    predicted_address VARCHAR(42),
    signature VARCHAR(132),
    encoded_data TEXT,
    initial_buy_percentage INTEGER DEFAULT 0,
    margin_bnb NUMERIC(78, 0) DEFAULT 0,
    margin_time BIGINT DEFAULT 0,
    vesting_allocations JSONB,
    website VARCHAR(500),
    twitter VARCHAR(500),
    telegram VARCHAR(500),
    discord VARCHAR(500),
    whitepaper VARCHAR(500),
    contact_email VARCHAR(255),
    contact_tg VARCHAR(255),
    tags TEXT[],
    status INTEGER DEFAULT 0, -- 0=待创建, 1=已提交, 2=已确认, 3=失败
    tx_hash VARCHAR(66),
    error_message TEXT,
    timestamp BIGINT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_token_creation_requests_creator ON token_creation_requests(LOWER(creator_address));
CREATE INDEX IF NOT EXISTS idx_token_creation_requests_status ON token_creation_requests(status);
CREATE INDEX IF NOT EXISTS idx_token_creation_requests_predicted ON token_creation_requests(LOWER(predicted_address));

-- ==================== Nonce 序列表 ====================

CREATE TABLE IF NOT EXISTS nonce_sequence (
    id SERIAL PRIMARY KEY,
    chain_id INTEGER NOT NULL,
    current_nonce BIGINT NOT NULL DEFAULT 0,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(chain_id)
);

-- 初始化 nonce (BSC Testnet chain_id = 97)
INSERT INTO nonce_sequence (chain_id, current_nonce) VALUES (97, 0) ON CONFLICT (chain_id) DO NOTHING;

