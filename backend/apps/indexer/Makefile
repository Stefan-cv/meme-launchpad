.PHONY: build run clean test tidy

# 项目名称
APP_NAME := meme-indexer
BUILD_DIR := ./build

# Go 编译参数
GOOS ?= $(shell go env GOOS)
GOARCH ?= $(shell go env GOARCH)
CGO_ENABLED ?= 0

# 版本信息
VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")
BUILD_TIME := $(shell date -u +"%Y-%m-%dT%H:%M:%SZ")
LDFLAGS := -ldflags "-s -w -X main.Version=$(VERSION) -X main.BuildTime=$(BUILD_TIME)"

# 构建
build:
	@echo "Building $(APP_NAME)..."
	@mkdir -p $(BUILD_DIR)
	CGO_ENABLED=$(CGO_ENABLED) GOOS=$(GOOS) GOARCH=$(GOARCH) \
		go build $(LDFLAGS) -o $(BUILD_DIR)/$(APP_NAME) ./cmd/indexer

# 运行
run:
	@echo "Running $(APP_NAME)..."
	go run ./cmd/indexer -config config/config.yaml

# 运行（开发模式，自动重启）
dev:
	@which air > /dev/null || go install github.com/cosmtrek/air@latest
	air

# 清理
clean:
	@echo "Cleaning..."
	@rm -rf $(BUILD_DIR)

# 测试
test:
	go test -v ./...

# 测试覆盖率
test-coverage:
	go test -v -coverprofile=coverage.out ./...
	go tool cover -html=coverage.out -o coverage.html

# 整理依赖
tidy:
	go mod tidy

# 下载依赖
deps:
	go mod download

# 代码检查
lint:
	@which golangci-lint > /dev/null || go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
	golangci-lint run

# 格式化代码
fmt:
	go fmt ./...

# 生成 Docker 镜像
docker-build:
	docker build -t $(APP_NAME):$(VERSION) .

# 显示帮助
help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  build           Build the binary"
	@echo "  run             Run the application"
	@echo "  dev             Run with hot reload (requires air)"
	@echo "  clean           Clean build artifacts"
	@echo "  test            Run tests"
	@echo "  test-coverage   Run tests with coverage"
	@echo "  tidy            Tidy go.mod"
	@echo "  deps            Download dependencies"
	@echo "  lint            Run linter"
	@echo "  fmt             Format code"
	@echo "  docker-build    Build Docker image"
	@echo "  help            Show this help"

