// cos.go - 腾讯云 COS 对象存储服务
// 本文件实现了与腾讯云 COS（Cloud Object Storage）交互的功能
// 主要用于生成预签名上传 URL，允许前端直传文件到 COS
// 使用腾讯云 COS 的签名算法（HMAC-SHA1）生成临时授权
package cos

import (
	"crypto/hmac"  // HMAC 消息认证码
	"crypto/sha1"  // SHA1 哈希算法
	"encoding/base64" // Base64 编解码
	"encoding/hex"   // 十六进制编解码
	"encoding/json"   // JSON 编解码
	"fmt"            // 格式化输出
	"net/url"        // URL 解析和编码
	"strings"        // 字符串处理
	"time"           // 时间包

	"github.com/google/uuid" // UUID 生成器，用于生成唯一文件名
	"github.com/meme-launchpad/api/internal/config" // 配置结构体
)

// CosService 腾讯云 COS 服务
type CosService struct {
	secretID  string // 腾讯云 API 密钥 ID
	secretKey string // 腾讯云 API 密钥 Secret
	bucket    string // 存储桶名称（格式：bucket-appid）
	region    string // 存储桶区域（如 "ap-hongkong"）
	appID     string // 腾讯云 AppID
	domain    string // 自定义 CDN 域名
}

// NewCosService 创建 COS 服务实例
func NewCosService(cfg config.Config) *CosService {
	return &CosService{
		secretID:  cfg.Cos.SecretID,  // 密钥 ID
		secretKey: cfg.Cos.SecretKey, // 密钥 Secret
		bucket:    cfg.Cos.Bucket,    // 存储桶
		region:    cfg.Cos.Region,    // 区域
		appID:     cfg.Cos.AppID,     // AppID
		domain:    cfg.Cos.Domain,    // 自定义域名
	}
}

// PresignResult 预签名结果
type PresignResult struct {
	UploadUrl string `json:"uploadUrl"` // 临时上传 URL（前端使用此 URL 上传文件）
	PublicUrl string `json:"publicUrl"` // 文件的公开访问 URL
	FileName  string `json:"fileName"`  // 生成的唯一文件名
	Key       string `json:"key"`       // 文件在 COS 中的完整路径
	ExpiresAt int64  `json:"expiresAt"` // 预签名 URL 的过期时间戳
}

// GeneratePresignedUrl 生成预签名上传 URL
// 执行流程：
//   1. 根据文件类型生成唯一文件名（UUID + 扩展名）
//   2. 构建文件在 COS 中的存储路径（folder/chainId/filename）
//   3. 生成 PUT 方法的预签名 URL（有效期 1 小时）
//   4. 生成公开访问 URL
// 参数：
//   - folder: 存储目录（如 "token-logo"、"token-banner"）
//   - mimeType: 文件 MIME 类型
//   - chainId: 链 ID（用于构建存储路径）
func (s *CosService) GeneratePresignedUrl(folder string, mimeType string, chainId int) (*PresignResult, error) {
	// 根据 MIME 类型获取文件扩展名
	ext := getExtFromMimeType(mimeType)
	// 使用 UUID 生成唯一文件名，防止文件名冲突
	fileName := fmt.Sprintf("%s%s", uuid.New().String(), ext)
	// 构建存储路径：folder/chainId/filename
	// 例如：token-logo/97/550e8400-e29b-41d4-a716-446655440000.png
	key := fmt.Sprintf("%s/%d/%s", folder, chainId, fileName)

	// 计算过期时间（1 小时）
	expireTime := time.Now().Add(1 * time.Hour)
	expiresAt := expireTime.Unix()

	// 生成 PUT 方法的预签名 URL
	uploadUrl, err := s.generatePresignedPutUrl(key, expireTime)
	if err != nil {
		return nil, err
	}

	// 生成公开访问 URL
	publicUrl := s.getPublicUrl(key)

	return &PresignResult{
		UploadUrl: uploadUrl, // 上传 URL
		PublicUrl: publicUrl, // 访问 URL
		FileName:  fileName,  // 文件名
		Key:       key,       // 存储路径
		ExpiresAt: expiresAt, // 过期时间
	}, nil
}

// generatePresignedPutUrl 生成 PUT 预签名 URL
// 实现腾讯云 COS 的签名算法（参考官方文档）
// 签名流程：
//   1. 计算 KeyTime（签名有效期的起止时间）
//   2. 使用 SecretKey 对 KeyTime 进行 HMAC-SHA1 得到 SignKey
//   3. 构建 FormatString（HTTP 方法 + URI + 参数 + 请求头）
//   4. 计算 FormatString 的 SHA1 哈希
//   5. 构建 StringToSign（签名算法 + KeyTime + FormatString 的哈希）
//   6. 使用 SignKey 对 StringToSign 进行 HMAC-SHA1 得到 Signature
//   7. 将签名参数附加到 URL 查询参数中
func (s *CosService) generatePresignedPutUrl(key string, expireTime time.Time) (string, error) {
	// 构建 COS 主机地址
	host := fmt.Sprintf("%s.cos.%s.myqcloud.com", s.bucket, s.region)

	// 签名有效期
	startTime := time.Now().Unix()
	endTime := expireTime.Unix()

	// 构建 HTTP 请求信息
	httpMethod := "put"  // PUT 方法用于上传文件
	uriPathname := "/" + key // 文件路径

	// 计算 KeyTime（格式：StartTime;EndTime）
	keyTime := fmt.Sprintf("%d;%d", startTime, endTime)
	// 使用 SecretKey 对 KeyTime 进行 HMAC-SHA1，得到 SignKey
	signKey := hmacSha1(s.secretKey, keyTime)

	// HTTP 参数（简化处理，不包含额外参数）
	httpParameters := ""
	httpParametersList := ""

	// HTTP 头部（简化处理，不包含额外头部）
	httpHeaders := ""
	httpHeadersList := ""

	// 构建 FormatString
	// 格式：HTTP方法\nURI\n查询参数\n请求头\n
	formatString := fmt.Sprintf("%s\n%s\n%s\n%s\n", httpMethod, uriPathname, httpParameters, httpHeaders)
	// 构建 StringToSign
	// 格式：签名算法\nKeyTime\nFormatString的SHA1哈希\n
	stringToSign := fmt.Sprintf("sha1\n%s\n%s\n", keyTime, sha1Hash(formatString))

	// 使用 SignKey 对 StringToSign 进行 HMAC-SHA1，得到签名
	signature := hmacSha1(signKey, stringToSign)

	// 构建 Authorization 字符串（格式参考腾讯云文档）
	authorization := fmt.Sprintf(
		"q-sign-algorithm=sha1&q-ak=%s&q-sign-time=%s&q-key-time=%s&q-header-list=%s&q-url-param-list=%s&q-signature=%s",
		s.secretID,
		keyTime,
		keyTime,
		httpHeadersList,
		httpParametersList,
		signature,
	)

	// 构建完整 URL（简化版本，使用查询参数方式传递签名，此版本被下面的正式版本覆盖）
	uploadUrl := fmt.Sprintf("https://%s%s?%s", host, uriPathname, url.QueryEscape(authorization))

	// 返回使用查询参数方式的预签名 URL
	params := url.Values{}
	params.Set("q-sign-algorithm", "sha1")   // 签名算法
	params.Set("q-ak", s.secretID)           // 密钥 ID
	params.Set("q-sign-time", keyTime)       // 签名有效期
	params.Set("q-key-time", keyTime)        // 密钥有效期
	params.Set("q-header-list", httpHeadersList)  // 参与签名的头部列表
	params.Set("q-url-param-list", httpParametersList) // 参与签名的参数列表
	params.Set("q-signature", signature)     // 签名值

	uploadUrl = fmt.Sprintf("https://%s%s?%s", host, uriPathname, params.Encode())

	return uploadUrl, nil
}

// getPublicUrl 获取文件的公开访问 URL
// 优先使用自定义域名，否则使用默认 COS 域名
func (s *CosService) getPublicUrl(key string) string {
	if s.domain != "" {
		// 使用自定义 CDN 域名
		domain := strings.TrimSuffix(s.domain, "/")
		return fmt.Sprintf("%s/%s", domain, key)
	}
	// 使用默认 COS 域名
	return fmt.Sprintf("https://%s.cos.%s.myqcloud.com/%s", s.bucket, s.region, key)
}

// GenerateSTSCredential 生成 STS 临时凭证
// 当前为简化实现，实际应调用腾讯云 STS API 获取临时凭证
// STS 方式比预签名 URL 更安全，可以限制上传权限和文件大小
func (s *CosService) GenerateSTSCredential(folder string, chainId int, durationSeconds int64) (map[string]interface{}, error) {
	// 计算过期时间
	expireTime := time.Now().Add(time.Duration(durationSeconds) * time.Second)
	expiresAt := expireTime.Unix()

	// 生成唯一文件名（固定为 PNG 格式）
	fileName := fmt.Sprintf("%s.png", uuid.New().String())
	key := fmt.Sprintf("%s/%d/%s", folder, chainId, fileName)

	// 使用预签名 URL 代替 STS 凭证（简化实现）
	uploadUrl, err := s.generatePresignedPutUrl(key, expireTime)
	if err != nil {
		return nil, err
	}

	publicUrl := s.getPublicUrl(key)

	// 返回类似 STS 凭证的结构
	return map[string]interface{}{
		"uploadUrl": uploadUrl, // 上传 URL
		"publicUrl": publicUrl, // 访问 URL
		"fileName":  fileName,  // 文件名
		"key":       key,       // 存储路径
		"expiresAt": expiresAt, // 过期时间
		"bucket":    s.bucket,  // 存储桶
		"region":    s.region,  // 区域
	}, nil
}

// ==================== 辅助函数 ====================

// hmacSha1 计算 HMAC-SHA1
// 用于腾讯云 COS 签名算法
func hmacSha1(key, data string) string {
	mac := hmac.New(sha1.New, []byte(key)) // 创建 HMAC-SHA1 实例
	mac.Write([]byte(data))                // 写入数据
	return hex.EncodeToString(mac.Sum(nil))  // 返回十六进制编码的 MAC 值
}

// sha1Hash 计算 SHA1 哈希
func sha1Hash(data string) string {
	h := sha1.New()
	h.Write([]byte(data))
	return hex.EncodeToString(h.Sum(nil))
}

// getExtFromMimeType 根据 MIME 类型获取文件扩展名
// 支持常见的图片格式
func getExtFromMimeType(mimeType string) string {
	mimeType = strings.ToLower(mimeType) // 统一转为小写
	switch mimeType {
	case "png", "image/png":
		return ".png"   // PNG 格式
	case "jpg", "jpeg", "image/jpeg":
		return ".jpg"   // JPEG 格式
	case "gif", "image/gif":
		return ".gif"   // GIF 格式
	case "webp", "image/webp":
		return ".webp"  // WebP 格式
	case "svg", "image/svg+xml":
		return ".svg"   // SVG 格式
	default:
		return ".png"   // 默认使用 PNG
	}
}

// base64Encode Base64 编码（用于 STS）
func base64Encode(data []byte) string {
	return base64.StdEncoding.EncodeToString(data)
}

// jsonEncode JSON 编码（用于 STS）
func jsonEncode(v interface{}) string {
	b, _ := json.Marshal(v)
	return string(b)
}
