# Build stage
FROM golang:1.21-alpine AS builder

WORKDIR /app

# 安装必要的构建工具
RUN apk add --no-cache git make

# 复制依赖文件
COPY go.mod go.sum ./
RUN go mod download

# 复制源代码
COPY . .

# 构建
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /app/indexer ./cmd/indexer

# Runtime stage
FROM alpine:3.19

WORKDIR /app

# 安装 CA 证书（用于 HTTPS 请求）
RUN apk --no-cache add ca-certificates tzdata

# 设置时区
ENV TZ=Asia/Shanghai

# 从构建阶段复制二进制文件
COPY --from=builder /app/indexer /app/indexer
COPY --from=builder /app/config /app/config

# 创建非 root 用户
RUN adduser -D -g '' appuser
USER appuser

EXPOSE 8081

ENTRYPOINT ["/app/indexer"]
CMD ["-config", "/app/config/config.yaml"]

