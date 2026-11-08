-- 添加 available_tokens 字段到 tokens 表
-- 如果字段已存在，则不会报错（使用 IF NOT EXISTS 需要 PostgreSQL 9.5+）
-- 对于旧版本，可以先检查字段是否存在

-- 方法1: 直接添加（如果字段不存在会报错，但可以忽略）
ALTER TABLE tokens ADD COLUMN IF NOT EXISTS available_tokens NUMERIC(78, 0) DEFAULT 0;

-- 如果上面的语句不支持（PostgreSQL < 9.5），可以使用下面的方法：
-- DO $$
-- BEGIN
--     IF NOT EXISTS (
--         SELECT 1 FROM information_schema.columns 
--         WHERE table_name = 'tokens' AND column_name = 'available_tokens'
--     ) THEN
--         ALTER TABLE tokens ADD COLUMN available_tokens NUMERIC(78, 0) DEFAULT 0;
--     END IF;
-- END $$;

