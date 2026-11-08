.PHONY: build run clean test fmt lint deps migrate api

# 变量
APP_NAME := meme-api
BUILD_DIR := build
CONFIG_FILE := etc/api.yaml

# 构建
build:
	@echo "Building $(APP_NAME)..."
	@mkdir -p $(BUILD_DIR)
	go build -o $(BUILD_DIR)/$(APP_NAME) .

# 运行
run: build
	@echo "Running $(APP_NAME)..."
	./$(BUILD_DIR)/$(APP_NAME) -f $(CONFIG_FILE)

# 开发模式运行
dev:
	@echo "Running in development mode..."
	go run . -f $(CONFIG_FILE)

# 清理
clean:
	@echo "Cleaning..."
	rm -rf $(BUILD_DIR)

# 测试
test:
	go test -v ./...

# 格式化
fmt:
	go fmt ./...
	goimports -w .

# 代码检查
lint:
	golangci-lint run ./...

# 安装依赖
deps:
	go mod download
	go mod tidy

# 生成 API 代码 (使用 goctl)
api:
	@echo "Generating API code..."
	goctl api go -api api/api.api -dir . -style go_zero

# 数据库迁移
migrate:
	@echo "Running database migrations..."
	@if [ -z "$(DATABASE_URL)" ]; then \
		echo "DATABASE_URL is not set, using config file"; \
		psql "postgresql://postgres:233333@Zj@localhost:5432/metaland" -f migrations/001_init.sql; \
	else \
		psql "$(DATABASE_URL)" -f migrations/001_init.sql; \
	fi

# Docker 构建
docker-build:
	docker build -t $(APP_NAME):latest .

# Docker 运行
docker-run:
	docker run -d --name $(APP_NAME) \
		-p 8080:8080 \
		-v $(PWD)/etc:/app/etc \
		$(APP_NAME):latest

# 帮助
help:
	@echo "Available targets:"
	@echo "  build       - Build the application"
	@echo "  run         - Build and run the application"
	@echo "  dev         - Run in development mode"
	@echo "  clean       - Clean build artifacts"
	@echo "  test        - Run tests"
	@echo "  fmt         - Format code"
	@echo "  lint        - Run linter"
	@echo "  deps        - Install dependencies"
	@echo "  api         - Generate API code from .api files"
	@echo "  migrate     - Run database migrations"
	@echo "  docker-build - Build Docker image"
	@echo "  docker-run   - Run Docker container"

