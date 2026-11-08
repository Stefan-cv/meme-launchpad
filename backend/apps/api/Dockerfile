# Build stage
FROM golang:1.21-alpine AS builder

WORKDIR /app

# 安装依赖
RUN apk add --no-cache git ca-certificates tzdata

# 复制 go.mod 和 go.sum
COPY go.mod go.sum ./
RUN go mod download

# 复制源代码
COPY . .

# 构建
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o meme-api .

# Runtime stage
FROM alpine:3.19

WORKDIR /app

# 安装必要的运行时依赖
RUN apk --no-cache add ca-certificates tzdata

# 从 builder 阶段复制二进制文件
COPY --from=builder /app/meme-api .
COPY --from=builder /app/etc ./etc

# 设置时区
ENV TZ=Asia/Shanghai

# 暴露端口
EXPOSE 8080

# 运行
ENTRYPOINT ["./meme-api"]
CMD ["-f", "etc/api.yaml"]

