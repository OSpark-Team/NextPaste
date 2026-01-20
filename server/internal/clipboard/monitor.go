package clipboard

import (
	"context"
	"crypto/md5"
	"encoding/base64"
	"fmt"
	"sync"

	"golang.design/x/clipboard"
)

// ClipboardData 定义剪贴板统一数据结构
type ClipboardData struct {
	Type     string // 类型: "text" 或 "image"
	MimeType string // MIME 类型: "text/plain" 或 "image/png"
	Content  string // 文本内容或 Base64 编码后的图片数据
}

// ChangeCallback 剪贴板数据变化时的回调函数
type ChangeCallback func(data ClipboardData)

// Monitor 剪贴板监听器核心结构
type Monitor struct {
	callback ChangeCallback
	ctx      context.Context
	cancel   context.CancelFunc
	wg       sync.WaitGroup

	lastTextHash string
	lastImgHash  string
	mu           sync.Mutex
}

// NewMonitor 创建剪贴板监听器实例
func NewMonitor() *Monitor {
	return &Monitor{}
}

// Start 初始化并启动剪贴板监听任务
func (m *Monitor) Start(callback ChangeCallback) error {
	if m.cancel != nil {
		return fmt.Errorf("monitor already started")
	}

	if err := clipboard.Init(); err != nil {
		return fmt.Errorf("failed to initialize clipboard: %w", err)
	}

	m.callback = callback
	m.ctx, m.cancel = context.WithCancel(context.Background())

	m.mu.Lock()
	m.lastTextHash = m.calcHash(clipboard.Read(clipboard.FmtText))
	m.lastImgHash = m.calcHash(clipboard.Read(clipboard.FmtImage))
	m.mu.Unlock()

	m.wg.Add(1)
	go m.watchText()

	m.wg.Add(1)
	go m.watchImage()

	return nil
}

// Stop 停止监听并释放相关资源
func (m *Monitor) Stop() {
	if m.cancel != nil {
		m.cancel()
		m.wg.Wait()
		m.cancel = nil
	}
}

// SetClipboard 更新系统剪贴板内容并同步更新内部哈希值
func (m *Monitor) SetClipboard(data ClipboardData) error {
	var content []byte
	var format clipboard.Format

	switch data.Type {
	case "text":
		content = []byte(data.Content)
		format = clipboard.FmtText
	case "image":
		imageData, err := base64.StdEncoding.DecodeString(data.Content)
		if err != nil {
			return fmt.Errorf("failed to decode image: %w", err)
		}
		content = imageData
		format = clipboard.FmtImage
	default:
		return fmt.Errorf("unsupported type: %s", data.Type)
	}

	newHash := m.calcHash(content)
	m.mu.Lock()
	if data.Type == "text" {
		m.lastTextHash = newHash
	} else {
		m.lastImgHash = newHash
	}
	m.mu.Unlock()

	clipboard.Write(format, content)
	return nil
}

// watchText 循环监听文本类型变化
func (m *Monitor) watchText() {
	defer m.wg.Done()

	ch := clipboard.Watch(m.ctx, clipboard.FmtText)
	for {
		select {
		case <-m.ctx.Done():
			return
		case data, ok := <-ch:
			if !ok || len(data) == 0 {
				continue
			}

			currentHash := m.calcHash(data)
			m.mu.Lock()
			if currentHash == m.lastTextHash {
				m.mu.Unlock()
				continue
			}
			m.lastTextHash = currentHash
			m.mu.Unlock()

			if m.callback != nil {
				m.callback(ClipboardData{
					Type:     "text",
					MimeType: "text/plain",
					Content:  string(data),
				})
			}
		}
	}
}

// watchImage 循环监听图片类型变化
func (m *Monitor) watchImage() {
	defer m.wg.Done()

	ch := clipboard.Watch(m.ctx, clipboard.FmtImage)
	for {
		select {
		case <-m.ctx.Done():
			return
		case data, ok := <-ch:
			if !ok || len(data) == 0 {
				continue
			}

			currentHash := m.calcHash(data)
			m.mu.Lock()
			if currentHash == m.lastImgHash {
				m.mu.Unlock()
				continue
			}
			m.lastImgHash = currentHash
			m.mu.Unlock()

			if m.callback != nil {
				m.callback(ClipboardData{
					Type:     "image",
					MimeType: "image/png",
					Content:  base64.StdEncoding.EncodeToString(data),
				})
			}
		}
	}
}

// calcHash 生成数据的唯一摘要，针对大容量数据执行采样计算
func (m *Monitor) calcHash(data []byte) string {
	if len(data) == 0 {
		return ""
	}

	if len(data) < 128*1024 {
		h := md5.Sum(data)
		return fmt.Sprintf("%x", h)
	}

	h := md5.New()
	h.Write(data[:512])
	h.Write(data[len(data)/2 : len(data)/2+512])
	h.Write(data[len(data)-512:])
	return fmt.Sprintf("%x_%d", h.Sum(nil), len(data))
}
