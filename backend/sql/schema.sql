--
-- PostgreSQL database dump
--

-- Dumped from database version 17.5 (Homebrew)
-- Dumped by pg_dump version 17.5 (Homebrew)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: activities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.activities (
    id integer NOT NULL,
    name character varying(200) NOT NULL,
    description text,
    category_type integer NOT NULL,
    play_type integer NOT NULL,
    reward_token_type integer NOT NULL,
    reward_amount character varying(78) NOT NULL,
    reward_slots character varying(20) NOT NULL,
    start_at timestamp without time zone NOT NULL,
    end_at timestamp without time zone NOT NULL,
    cover_image character varying(500),
    token_id integer,
    initiator_type integer NOT NULL,
    audience_type integer NOT NULL,
    creator_id integer,
    status integer DEFAULT 1,
    min_daily_trade_amount character varying(78),
    invite_min_count character varying(20),
    invitee_min_trade_amount character varying(78),
    heat_vote_target character varying(20),
    comment_min_count character varying(20),
    reward_token_id integer,
    reward_token_address character varying(42),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: activities_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.activities_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: activities_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.activities_id_seq OWNED BY public.activities.id;


--
-- Name: activity_participations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.activity_participations (
    id integer NOT NULL,
    activity_id integer NOT NULL,
    user_id integer NOT NULL,
    status integer DEFAULT 1,
    reward_claimed boolean DEFAULT false,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: activity_participations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.activity_participations_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: activity_participations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.activity_participations_id_seq OWNED BY public.activity_participations.id;


--
-- Name: agents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agents (
    id integer NOT NULL,
    user_id integer NOT NULL,
    address character varying(42) NOT NULL,
    invitation_code character varying(20) NOT NULL,
    level integer DEFAULT 1,
    parent_id integer,
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: agents_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.agents_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: agents_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.agents_id_seq OWNED BY public.agents.id;


--
-- Name: comments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.comments (
    id integer NOT NULL,
    token_id integer NOT NULL,
    user_id integer NOT NULL,
    content text,
    img character varying(500),
    holding_amount numeric(78,0) DEFAULT 0,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: comments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.comments_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: comments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.comments_id_seq OWNED BY public.comments.id;


--
-- Name: indexer_state; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.indexer_state (
    id integer NOT NULL,
    contract_address character varying(42) NOT NULL,
    last_block_number bigint NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: indexer_state_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.indexer_state_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: indexer_state_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.indexer_state_id_seq OWNED BY public.indexer_state.id;


--
-- Name: invites; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invites (
    id integer NOT NULL,
    inviter_id integer NOT NULL,
    invitee_id integer NOT NULL,
    inviter_address character varying(42) NOT NULL,
    invitee_address character varying(42) NOT NULL,
    invitation_code character varying(20) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: invites_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.invites_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: invites_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.invites_id_seq OWNED BY public.invites.id;


--
-- Name: klines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.klines (
    id integer NOT NULL,
    token_address character varying(42) NOT NULL,
    "interval" character varying(10) NOT NULL,
    open_time timestamp without time zone NOT NULL,
    open_price numeric(78,18) NOT NULL,
    high_price numeric(78,18) NOT NULL,
    low_price numeric(78,18) NOT NULL,
    close_price numeric(78,18) NOT NULL,
    volume numeric(78,0) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: klines_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.klines_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: klines_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.klines_id_seq OWNED BY public.klines.id;


--
-- Name: nonce_sequence; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.nonce_sequence (
    id integer NOT NULL,
    chain_id integer NOT NULL,
    current_nonce bigint DEFAULT 0 NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: nonce_sequence_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.nonce_sequence_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: nonce_sequence_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.nonce_sequence_id_seq OWNED BY public.nonce_sequence.id;


--
-- Name: rebate_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rebate_records (
    id integer NOT NULL,
    user_id integer NOT NULL,
    trader_id integer NOT NULL,
    user_address character varying(42) NOT NULL,
    amount numeric(18,8) NOT NULL,
    status integer DEFAULT 0,
    tx_hash character varying(66),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: rebate_records_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.rebate_records_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: rebate_records_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.rebate_records_id_seq OWNED BY public.rebate_records.id;


--
-- Name: token_balances; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.token_balances (
    id integer NOT NULL,
    token_address character varying(42) NOT NULL,
    holder_address character varying(42) NOT NULL,
    balance numeric(78,0) DEFAULT 0 NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: token_balances_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.token_balances_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: token_balances_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.token_balances_id_seq OWNED BY public.token_balances.id;


--
-- Name: token_bought_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.token_bought_events (
    id integer NOT NULL,
    token_address character varying(42) NOT NULL,
    buyer_address character varying(42) NOT NULL,
    bnb_amount numeric(78,0) NOT NULL,
    token_amount numeric(78,0) NOT NULL,
    trading_fee numeric(78,0) DEFAULT 0 NOT NULL,
    virtual_bnb_reserve numeric(78,0) DEFAULT 0 NOT NULL,
    virtual_token_reserve numeric(78,0) DEFAULT 0 NOT NULL,
    available_tokens numeric(78,0) DEFAULT 0 NOT NULL,
    collected_bnb numeric(78,0) DEFAULT 0 NOT NULL,
    transaction_hash character varying(66) NOT NULL,
    block_number bigint NOT NULL,
    block_timestamp timestamp without time zone NOT NULL,
    log_index integer NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: token_bought_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.token_bought_events_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: token_bought_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.token_bought_events_id_seq OWNED BY public.token_bought_events.id;


--
-- Name: token_created_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.token_created_events (
    id integer NOT NULL,
    token_address character varying(42) NOT NULL,
    creator_address character varying(42) NOT NULL,
    name character varying(255) NOT NULL,
    symbol character varying(50) NOT NULL,
    total_supply numeric(78,0) NOT NULL,
    request_id character varying(66) NOT NULL,
    transaction_hash character varying(66) NOT NULL,
    block_number bigint NOT NULL,
    block_timestamp timestamp without time zone NOT NULL,
    log_index integer NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: token_created_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.token_created_events_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: token_created_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.token_created_events_id_seq OWNED BY public.token_created_events.id;


--
-- Name: token_creation_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.token_creation_requests (
    id integer NOT NULL,
    request_id character varying(66) NOT NULL,
    creator_address character varying(42) NOT NULL,
    name character varying(100) NOT NULL,
    symbol character varying(50) NOT NULL,
    description text,
    logo character varying(500),
    banner character varying(500),
    total_supply numeric(78,0) NOT NULL,
    sale_amount numeric(78,0) NOT NULL,
    virtual_bnb_reserve numeric(78,0) NOT NULL,
    virtual_token_reserve numeric(78,0) NOT NULL,
    launch_mode integer DEFAULT 1 NOT NULL,
    launch_time bigint DEFAULT 0 NOT NULL,
    creation_fee numeric(78,0) DEFAULT 0,
    nonce integer NOT NULL,
    salt character varying(66),
    predicted_address character varying(42),
    signature character varying(132),
    encoded_data text,
    initial_buy_percentage integer DEFAULT 0,
    margin_bnb numeric(78,0) DEFAULT 0,
    margin_time bigint DEFAULT 0,
    vesting_allocations jsonb,
    website character varying(500),
    twitter character varying(500),
    telegram character varying(500),
    discord character varying(500),
    whitepaper character varying(500),
    contact_email character varying(255),
    contact_tg character varying(255),
    tags text[],
    status integer DEFAULT 0,
    tx_hash character varying(66),
    error_message text,
    "timestamp" bigint NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: token_creation_requests_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.token_creation_requests_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: token_creation_requests_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.token_creation_requests_id_seq OWNED BY public.token_creation_requests.id;


--
-- Name: token_graduated_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.token_graduated_events (
    id integer NOT NULL,
    token_address character varying(42) NOT NULL,
    liquidity_bnb numeric(78,0) NOT NULL,
    liquidity_tokens numeric(78,0) NOT NULL,
    liquidity_result numeric(78,0) NOT NULL,
    transaction_hash character varying(66) NOT NULL,
    block_number bigint NOT NULL,
    block_timestamp timestamp without time zone NOT NULL,
    log_index integer NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: token_graduated_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.token_graduated_events_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: token_graduated_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.token_graduated_events_id_seq OWNED BY public.token_graduated_events.id;


--
-- Name: token_sold_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.token_sold_events (
    id integer NOT NULL,
    token_address character varying(42) NOT NULL,
    seller_address character varying(42) NOT NULL,
    token_amount numeric(78,0) NOT NULL,
    bnb_amount numeric(78,0) NOT NULL,
    trading_fee numeric(78,0) DEFAULT 0 NOT NULL,
    virtual_bnb_reserve numeric(78,0) DEFAULT 0 NOT NULL,
    virtual_token_reserve numeric(78,0) DEFAULT 0 NOT NULL,
    available_tokens numeric(78,0) DEFAULT 0 NOT NULL,
    collected_bnb numeric(78,0) DEFAULT 0 NOT NULL,
    transaction_hash character varying(66) NOT NULL,
    block_number bigint NOT NULL,
    block_timestamp timestamp without time zone NOT NULL,
    log_index integer NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: token_sold_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.token_sold_events_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: token_sold_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.token_sold_events_id_seq OWNED BY public.token_sold_events.id;


--
-- Name: tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tokens (
    id integer NOT NULL,
    name character varying(100) NOT NULL,
    symbol character varying(50) NOT NULL,
    logo character varying(500) NOT NULL,
    banner character varying(500),
    description text,
    token_contract_address character varying(42) NOT NULL,
    creator_address character varying(42) NOT NULL,
    launch_mode integer DEFAULT 1 NOT NULL,
    launch_time bigint NOT NULL,
    bnb_current numeric(78,0) DEFAULT 0,
    bnb_target numeric(78,0) NOT NULL,
    margin_bnb numeric(78,0) DEFAULT 0,
    total_supply numeric(78,0) NOT NULL,
    status integer DEFAULT 1,
    website character varying(500),
    twitter character varying(500),
    telegram character varying(500),
    discord character varying(500),
    whitepaper character varying(500),
    tags text[],
    hot integer DEFAULT 0,
    token_lv integer DEFAULT 0,
    token_rank integer DEFAULT 0,
    request_id character varying(66),
    nonce integer NOT NULL,
    salt character varying(66),
    pre_buy_percent numeric(5,4) DEFAULT 0,
    margin_time bigint DEFAULT 0,
    contact_email character varying(255),
    contact_tg character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    available_tokens numeric(78,0) DEFAULT 0
);


--
-- Name: tokens_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tokens_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tokens_id_seq OWNED BY public.tokens.id;


--
-- Name: trades; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.trades (
    id integer NOT NULL,
    token_address character varying(42) NOT NULL,
    user_address character varying(42) NOT NULL,
    trade_type integer NOT NULL,
    bnb_amount numeric(78,0) NOT NULL,
    token_amount numeric(78,0) NOT NULL,
    price numeric(78,18) NOT NULL,
    usd_amount numeric(18,2),
    transaction_hash character varying(66) NOT NULL,
    block_number bigint NOT NULL,
    block_timestamp timestamp without time zone NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: trades_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.trades_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: trades_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.trades_id_seq OWNED BY public.trades.id;


--
-- Name: user_favorites; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_favorites (
    id integer NOT NULL,
    user_id integer NOT NULL,
    token_id integer NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: user_favorites_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.user_favorites_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_favorites_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.user_favorites_id_seq OWNED BY public.user_favorites.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id integer NOT NULL,
    address character varying(42) NOT NULL,
    username character varying(100),
    email character varying(255),
    avatar character varying(500),
    nonce character varying(64),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: activities id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activities ALTER COLUMN id SET DEFAULT nextval('public.activities_id_seq'::regclass);


--
-- Name: activity_participations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activity_participations ALTER COLUMN id SET DEFAULT nextval('public.activity_participations_id_seq'::regclass);


--
-- Name: agents id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agents ALTER COLUMN id SET DEFAULT nextval('public.agents_id_seq'::regclass);


--
-- Name: comments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comments ALTER COLUMN id SET DEFAULT nextval('public.comments_id_seq'::regclass);


--
-- Name: indexer_state id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.indexer_state ALTER COLUMN id SET DEFAULT nextval('public.indexer_state_id_seq'::regclass);


--
-- Name: invites id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invites ALTER COLUMN id SET DEFAULT nextval('public.invites_id_seq'::regclass);


--
-- Name: klines id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.klines ALTER COLUMN id SET DEFAULT nextval('public.klines_id_seq'::regclass);


--
-- Name: nonce_sequence id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nonce_sequence ALTER COLUMN id SET DEFAULT nextval('public.nonce_sequence_id_seq'::regclass);


--
-- Name: rebate_records id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rebate_records ALTER COLUMN id SET DEFAULT nextval('public.rebate_records_id_seq'::regclass);


--
-- Name: token_balances id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.token_balances ALTER COLUMN id SET DEFAULT nextval('public.token_balances_id_seq'::regclass);


--
-- Name: token_bought_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.token_bought_events ALTER COLUMN id SET DEFAULT nextval('public.token_bought_events_id_seq'::regclass);


--
-- Name: token_created_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.token_created_events ALTER COLUMN id SET DEFAULT nextval('public.token_created_events_id_seq'::regclass);


--
-- Name: token_creation_requests id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.token_creation_requests ALTER COLUMN id SET DEFAULT nextval('public.token_creation_requests_id_seq'::regclass);


--
-- Name: token_graduated_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.token_graduated_events ALTER COLUMN id SET DEFAULT nextval('public.token_graduated_events_id_seq'::regclass);


--
-- Name: token_sold_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.token_sold_events ALTER COLUMN id SET DEFAULT nextval('public.token_sold_events_id_seq'::regclass);


--
-- Name: tokens id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tokens ALTER COLUMN id SET DEFAULT nextval('public.tokens_id_seq'::regclass);


--
-- Name: trades id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trades ALTER COLUMN id SET DEFAULT nextval('public.trades_id_seq'::regclass);


--
-- Name: user_favorites id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_favorites ALTER COLUMN id SET DEFAULT nextval('public.user_favorites_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: activities activities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activities
    ADD CONSTRAINT activities_pkey PRIMARY KEY (id);


--
-- Name: activity_participations activity_participations_activity_id_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activity_participations
    ADD CONSTRAINT activity_participations_activity_id_user_id_key UNIQUE (activity_id, user_id);


--
-- Name: activity_participations activity_participations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activity_participations
    ADD CONSTRAINT activity_participations_pkey PRIMARY KEY (id);


--
-- Name: agents agents_address_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agents
    ADD CONSTRAINT agents_address_key UNIQUE (address);


--
-- Name: agents agents_invitation_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agents
    ADD CONSTRAINT agents_invitation_code_key UNIQUE (invitation_code);


--
-- Name: agents agents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agents
    ADD CONSTRAINT agents_pkey PRIMARY KEY (id);


--
-- Name: comments comments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT comments_pkey PRIMARY KEY (id);


--
-- Name: indexer_state indexer_state_contract_address_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.indexer_state
    ADD CONSTRAINT indexer_state_contract_address_key UNIQUE (contract_address);


--
-- Name: indexer_state indexer_state_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.indexer_state
    ADD CONSTRAINT indexer_state_pkey PRIMARY KEY (id);


--
-- Name: invites invites_invitee_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invites
    ADD CONSTRAINT invites_invitee_id_key UNIQUE (invitee_id);


--
-- Name: invites invites_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invites
    ADD CONSTRAINT invites_pkey PRIMARY KEY (id);


--
-- Name: klines klines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.klines
    ADD CONSTRAINT klines_pkey PRIMARY KEY (id, open_time);


--
-- Name: klines klines_token_address_interval_open_time_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.klines
    ADD CONSTRAINT klines_token_address_interval_open_time_key UNIQUE (token_address, "interval", open_time);


--
-- Name: nonce_sequence nonce_sequence_chain_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nonce_sequence
    ADD CONSTRAINT nonce_sequence_chain_id_key UNIQUE (chain_id);


--
-- Name: nonce_sequence nonce_sequence_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nonce_sequence
    ADD CONSTRAINT nonce_sequence_pkey PRIMARY KEY (id);


--
-- Name: rebate_records rebate_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rebate_records
    ADD CONSTRAINT rebate_records_pkey PRIMARY KEY (id);


--
-- Name: token_balances token_balances_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.token_balances
    ADD CONSTRAINT token_balances_pkey PRIMARY KEY (id);


--
-- Name: token_balances token_balances_token_address_holder_address_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.token_balances
    ADD CONSTRAINT token_balances_token_address_holder_address_key UNIQUE (token_address, holder_address);


--
-- Name: token_bought_events token_bought_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.token_bought_events
    ADD CONSTRAINT token_bought_events_pkey PRIMARY KEY (id);


--
-- Name: token_bought_events token_bought_events_transaction_hash_log_index_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.token_bought_events
    ADD CONSTRAINT token_bought_events_transaction_hash_log_index_key UNIQUE (transaction_hash, log_index);


--
-- Name: token_created_events token_created_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.token_created_events
    ADD CONSTRAINT token_created_events_pkey PRIMARY KEY (id);


--
-- Name: token_created_events token_created_events_transaction_hash_log_index_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.token_created_events
    ADD CONSTRAINT token_created_events_transaction_hash_log_index_key UNIQUE (transaction_hash, log_index);


--
-- Name: token_creation_requests token_creation_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.token_creation_requests
    ADD CONSTRAINT token_creation_requests_pkey PRIMARY KEY (id);


--
-- Name: token_creation_requests token_creation_requests_request_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.token_creation_requests
    ADD CONSTRAINT token_creation_requests_request_id_key UNIQUE (request_id);


--
-- Name: token_graduated_events token_graduated_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.token_graduated_events
    ADD CONSTRAINT token_graduated_events_pkey PRIMARY KEY (id);


--
-- Name: token_graduated_events token_graduated_events_transaction_hash_log_index_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.token_graduated_events
    ADD CONSTRAINT token_graduated_events_transaction_hash_log_index_key UNIQUE (transaction_hash, log_index);


--
-- Name: token_sold_events token_sold_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.token_sold_events
    ADD CONSTRAINT token_sold_events_pkey PRIMARY KEY (id);


--
-- Name: token_sold_events token_sold_events_transaction_hash_log_index_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.token_sold_events
    ADD CONSTRAINT token_sold_events_transaction_hash_log_index_key UNIQUE (transaction_hash, log_index);


--
-- Name: tokens tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tokens
    ADD CONSTRAINT tokens_pkey PRIMARY KEY (id);


--
-- Name: tokens tokens_token_contract_address_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tokens
    ADD CONSTRAINT tokens_token_contract_address_key UNIQUE (token_contract_address);


--
-- Name: trades trades_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trades
    ADD CONSTRAINT trades_pkey PRIMARY KEY (id);


--
-- Name: trades trades_transaction_hash_trade_type_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trades
    ADD CONSTRAINT trades_transaction_hash_trade_type_key UNIQUE (transaction_hash, trade_type);


--
-- Name: user_favorites user_favorites_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_favorites
    ADD CONSTRAINT user_favorites_pkey PRIMARY KEY (id);


--
-- Name: user_favorites user_favorites_user_id_token_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_favorites
    ADD CONSTRAINT user_favorites_user_id_token_id_key UNIQUE (user_id, token_id);


--
-- Name: users users_address_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_address_key UNIQUE (address);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: idx_activities_creator; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_activities_creator ON public.activities USING btree (creator_id);


--
-- Name: idx_activities_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_activities_status ON public.activities USING btree (status);


--
-- Name: idx_activities_token; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_activities_token ON public.activities USING btree (token_id);


--
-- Name: idx_agents_address; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agents_address ON public.agents USING btree (lower((address)::text));


--
-- Name: idx_agents_code; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agents_code ON public.agents USING btree (invitation_code);


--
-- Name: idx_agents_parent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agents_parent ON public.agents USING btree (parent_id);


--
-- Name: idx_comments_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_comments_created_at ON public.comments USING btree (created_at DESC);


--
-- Name: idx_comments_token; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_comments_token ON public.comments USING btree (token_id);


--
-- Name: idx_comments_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_comments_user ON public.comments USING btree (user_id);


--
-- Name: idx_invites_inviter; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invites_inviter ON public.invites USING btree (inviter_id);


--
-- Name: idx_invites_inviter_addr; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invites_inviter_addr ON public.invites USING btree (lower((inviter_address)::text));


--
-- Name: idx_klines_token_interval; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_klines_token_interval ON public.klines USING btree (lower((token_address)::text), "interval", open_time DESC);


--
-- Name: idx_rebate_address; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rebate_address ON public.rebate_records USING btree (lower((user_address)::text));


--
-- Name: idx_rebate_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rebate_status ON public.rebate_records USING btree (status);


--
-- Name: idx_rebate_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rebate_user ON public.rebate_records USING btree (user_id);


--
-- Name: idx_token_balances_balance; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_token_balances_balance ON public.token_balances USING btree (balance DESC);


--
-- Name: idx_token_balances_holder; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_token_balances_holder ON public.token_balances USING btree (lower((holder_address)::text));


--
-- Name: idx_token_balances_token; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_token_balances_token ON public.token_balances USING btree (lower((token_address)::text));


--
-- Name: idx_token_bought_block; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_token_bought_block ON public.token_bought_events USING btree (block_number);


--
-- Name: idx_token_bought_buyer; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_token_bought_buyer ON public.token_bought_events USING btree (buyer_address);


--
-- Name: idx_token_bought_timestamp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_token_bought_timestamp ON public.token_bought_events USING btree (block_timestamp DESC);


--
-- Name: idx_token_bought_token_address; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_token_bought_token_address ON public.token_bought_events USING btree (token_address);


--
-- Name: idx_token_created_block; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_token_created_block ON public.token_created_events USING btree (block_number);


--
-- Name: idx_token_created_creator; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_token_created_creator ON public.token_created_events USING btree (creator_address);


--
-- Name: idx_token_created_request_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_token_created_request_id ON public.token_created_events USING btree (request_id);


--
-- Name: idx_token_created_token_address; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_token_created_token_address ON public.token_created_events USING btree (token_address);


--
-- Name: idx_token_creation_requests_creator; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_token_creation_requests_creator ON public.token_creation_requests USING btree (lower((creator_address)::text));


--
-- Name: idx_token_creation_requests_predicted; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_token_creation_requests_predicted ON public.token_creation_requests USING btree (lower((predicted_address)::text));


--
-- Name: idx_token_creation_requests_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_token_creation_requests_status ON public.token_creation_requests USING btree (status);


--
-- Name: idx_token_graduated_block; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_token_graduated_block ON public.token_graduated_events USING btree (block_number);


--
-- Name: idx_token_graduated_token_address; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_token_graduated_token_address ON public.token_graduated_events USING btree (token_address);


--
-- Name: idx_token_sold_block; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_token_sold_block ON public.token_sold_events USING btree (block_number);


--
-- Name: idx_token_sold_seller; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_token_sold_seller ON public.token_sold_events USING btree (seller_address);


--
-- Name: idx_token_sold_timestamp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_token_sold_timestamp ON public.token_sold_events USING btree (block_timestamp DESC);


--
-- Name: idx_token_sold_token_address; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_token_sold_token_address ON public.token_sold_events USING btree (token_address);


--
-- Name: idx_tokens_address; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tokens_address ON public.tokens USING btree (lower((token_contract_address)::text));


--
-- Name: idx_tokens_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tokens_created_at ON public.tokens USING btree (created_at DESC);


--
-- Name: idx_tokens_creator; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tokens_creator ON public.tokens USING btree (lower((creator_address)::text));


--
-- Name: idx_tokens_hot; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tokens_hot ON public.tokens USING btree (hot DESC);


--
-- Name: idx_tokens_launch_mode; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tokens_launch_mode ON public.tokens USING btree (launch_mode);


--
-- Name: idx_tokens_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tokens_status ON public.tokens USING btree (status);


--
-- Name: idx_trades_timestamp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_trades_timestamp ON public.trades USING btree (block_timestamp DESC);


--
-- Name: idx_trades_token; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_trades_token ON public.trades USING btree (lower((token_address)::text));


--
-- Name: idx_trades_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_trades_type ON public.trades USING btree (trade_type);


--
-- Name: idx_trades_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_trades_user ON public.trades USING btree (lower((user_address)::text));


--
-- Name: idx_user_favorites_token; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_user_favorites_token ON public.user_favorites USING btree (token_id);


--
-- Name: idx_user_favorites_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_user_favorites_user ON public.user_favorites USING btree (user_id);


--
-- Name: idx_users_address; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_address ON public.users USING btree (lower((address)::text));


--
-- Name: activities activities_creator_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activities
    ADD CONSTRAINT activities_creator_id_fkey FOREIGN KEY (creator_id) REFERENCES public.users(id);


--
-- Name: activities activities_token_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activities
    ADD CONSTRAINT activities_token_id_fkey FOREIGN KEY (token_id) REFERENCES public.tokens(id);


--
-- Name: activity_participations activity_participations_activity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activity_participations
    ADD CONSTRAINT activity_participations_activity_id_fkey FOREIGN KEY (activity_id) REFERENCES public.activities(id);


--
-- Name: activity_participations activity_participations_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activity_participations
    ADD CONSTRAINT activity_participations_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: agents agents_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agents
    ADD CONSTRAINT agents_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.agents(id);


--
-- Name: agents agents_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agents
    ADD CONSTRAINT agents_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: comments comments_token_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT comments_token_id_fkey FOREIGN KEY (token_id) REFERENCES public.tokens(id);


--
-- Name: comments comments_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT comments_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: invites invites_invitee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invites
    ADD CONSTRAINT invites_invitee_id_fkey FOREIGN KEY (invitee_id) REFERENCES public.users(id);


--
-- Name: invites invites_inviter_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invites
    ADD CONSTRAINT invites_inviter_id_fkey FOREIGN KEY (inviter_id) REFERENCES public.users(id);


--
-- Name: rebate_records rebate_records_trader_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rebate_records
    ADD CONSTRAINT rebate_records_trader_id_fkey FOREIGN KEY (trader_id) REFERENCES public.users(id);


--
-- Name: rebate_records rebate_records_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rebate_records
    ADD CONSTRAINT rebate_records_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: user_favorites user_favorites_token_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_favorites
    ADD CONSTRAINT user_favorites_token_id_fkey FOREIGN KEY (token_id) REFERENCES public.tokens(id);


--
-- Name: user_favorites user_favorites_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_favorites
    ADD CONSTRAINT user_favorites_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- PostgreSQL database dump complete
--

