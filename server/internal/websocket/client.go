package websocket

import (
	"context"
	"encoding/base64"
	"errors"
	"fmt"
	"sync"
	"time"

	"server/internal/protocol"

	"github.com/gorilla/websocket"
)

// WSClient WebSocket 客户端（V1.1 二进制协议版本）
type WSClient struct {
	url               string
	conn              *websocket.Conn
	ctx               context.Context
	cancel            context.CancelFunc
	isConnected       bool
	everConnected     bool // 是否曾经连接成功过
	mu                sync.RWMutex
	deviceName        string
	platform          string
	logCb             LogCallback
	clipboardCallback BinaryClipboardCallback
	onConnected       func() // 连接成功回调
	reconnectInterval time.Duration
	heartbeatInterval time.Duration

	// V1.1 二进制协议管理器
	protocolMgr *protocol.BinaryProtocolManager
}

// NewWSClient 创建 WebSocket 客户端
func NewWSClient(deviceName, platform string) *WSClient {
	return &WSClient{
		deviceName:        deviceName,
		platform:          platform,
		reconnectInterval: 5 * time.Second,
		heartbeatInterval: 30 * time.Second,
		protocolMgr:       protocol.NewBinaryProtocolManager(),
	}
}

// SetClipboardCallback 设置剪贴板数据回调（V1.1）
func (c *WSClient) SetClipboardCallback(cb BinaryClipboardCallback) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.clipboardCallback = cb
}

// SetOnConnected 设置连接成功回调
func (c *WSClient) SetOnConnected(cb func()) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.onConnected = cb
}

// Connect 连接到 WebSocket 服务器
func (c *WSClient) Connect(url string, logCb LogCallback) error {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.isConnected {
		return fmt.Errorf("客户端已连接")
	}

	c.url = url
	c.logCb = logCb
	c.ctx, c.cancel = context.WithCancel(context.Background())

	// 启动连接协程
	go c.connectLoop()

	return nil
}

// Disconnect 断开连接
func (c *WSClient) Disconnect() error {
	c.mu.Lock()
	defer c.mu.Unlock()

	if !c.isConnected && c.conn == nil {
		return nil
	}

	if c.cancel != nil {
		c.cancel()
	}

	if c.conn != nil {
		c.conn.Close()
		c.conn = nil
	}

	c.isConnected = false
	c.everConnected = false // 重置连接状态
	c.log("INFO", "客户端已断开连接")
	return nil
}

// connectLoop 连接循环（支持自动重连）
func (c *WSClient) connectLoop() {
	for {
		select {
		case <-c.ctx.Done():
			return
		default:
			if err := c.doConnect(); err != nil {
				c.log("ERROR", fmt.Sprintf("连接失败: %v", err))

				// 检查是否曾经连接成功过
				c.mu.RLock()
				everConnected := c.everConnected
				c.mu.RUnlock()

				// 只有曾经连接成功过才自动重连
				if everConnected {
					c.log("INFO", fmt.Sprintf("将在 %v 后重试连接...", c.reconnectInterval))
					select {
					case <-time.After(c.reconnectInterval):
						continue
					case <-c.ctx.Done():
						return
					}
				} else {
					// 首次连接失败，不重连，直接退出
					c.log("ERROR", "首次连接失败，请检查服务器地址")
					return
				}
			}
		}
	}
}

// doConnect 执行连接
func (c *WSClient) doConnect() error {
	c.log("INFO", fmt.Sprintf("正在连接到 %s...", c.url))

	conn, _, err := websocket.DefaultDialer.Dial(c.url, nil)
	if err != nil {
		return err
	}

	c.mu.Lock()
	c.conn = conn
	c.isConnected = true
	c.everConnected = true // 标记曾经连接成功
	c.mu.Unlock()

	c.log("SUCCESS", "连接成功")

	// 发送握手消息（V1.1 二进制协议）
	if err := c.sendHandshake(); err != nil {
		c.log("ERROR", fmt.Sprintf("发送握手消息失败: %v", err))
		conn.Close()
		return err
	}

	// 调用连接成功回调
	c.mu.RLock()
	onConnected := c.onConnected
	c.mu.RUnlock()
	if onConnected != nil {
		onConnected()
	}

	// 启动读写协程
	go c.readPump()
	go c.heartbeatPump()

	// 等待连接关闭
	<-c.ctx.Done()
	return nil
}

// sendHandshake 发送握手消息（V1.1 二进制协议）
func (c *WSClient) sendHandshake() error {
	data, err := c.protocolMgr.CreateHandshake(c.deviceName, c.platform)
	if err != nil {
		return err
	}
	return c.sendBinaryData(data)
}

// readPump 读取服务器消息（V1.1 二进制协议）
func (c *WSClient) readPump() {
	defer func() {
		c.mu.Lock()
		if c.conn != nil {
			c.conn.Close()
		}
		c.isConnected = false
		c.mu.Unlock()
	}()

	for {
		select {
		case <-c.ctx.Done():
			return
		default:
			c.mu.RLock()
			conn := c.conn
			c.mu.RUnlock()

			if conn == nil {
				return
			}

			messageType, message, err := conn.ReadMessage()
			if err != nil {
				if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
					c.log("ERROR", fmt.Sprintf("连接异常断开: %v", err))
				}
				return
			}

			// V1.1 二进制协议：只处理二进制消息
			if messageType != websocket.BinaryMessage {
				c.log("WARNING", "收到非二进制消息，不兼容的协议版本")
				continue
			}

			c.handleBinaryMessage(message)
		}
	}
}

// heartbeatPump 发送心跳（V1.1 二进制协议）
func (c *WSClient) heartbeatPump() {
	ticker := time.NewTicker(c.heartbeatInterval)
	defer ticker.Stop()

	for {
		select {
		case <-c.ctx.Done():
			return
		case <-ticker.C:
			if err := c.sendHeartbeat(); err != nil {
				c.log("ERROR", fmt.Sprintf("发送心跳失败: %v", err))
				return
			}
		}
	}
}

// sendHeartbeat 发送心跳消息（V1.1 二进制协议）
func (c *WSClient) sendHeartbeat() error {
	data := c.protocolMgr.CreateHeartbeat()
	return c.sendBinaryData(data)
}

// handleBinaryMessage 处理二进制消息（V1.1）
func (c *WSClient) handleBinaryMessage(data []byte) {
	msg, err := c.protocolMgr.Parse(data)
	if err != nil {
		// 回环消息静默忽略
		if errors.Is(err, protocol.ErrLoopbackDetected) {
			return
		}
		c.log("ERROR", fmt.Sprintf("解析二进制消息失败: %v", err))
		return
	}

	switch msg.Type {
	case protocol.TypeText:
		c.handleBinaryText(msg)
	case protocol.TypeImage:
		c.handleBinaryImage(msg)
	case protocol.TypeHeartbeat:
		// 心跳消息不需要处理
	case protocol.TypeHandshake:
		// 收到握手响应
		c.log("INFO", "收到握手响应")
	default:
		c.log("WARNING", fmt.Sprintf("未知的消息类型: 0x%02X", msg.Type))
	}
}

// handleBinaryText 处理文本消息（V1.1）
func (c *WSClient) handleBinaryText(msg *protocol.BinaryMessage) {
	text := msg.GetTextContent()
	c.log("INFO", fmt.Sprintf("收到文本数据 [%d 字符]", len(text)))

	// 调用回调函数（通知 App 层写入本地剪贴板）
	if c.clipboardCallback != nil {
		c.clipboardCallback("text", []byte(text))
	}
}

// handleBinaryImage 处理图片消息（V1.1）
func (c *WSClient) handleBinaryImage(msg *protocol.BinaryMessage) {
	imageData := msg.GetImageData()
	sizeMB := float64(len(imageData)) / 1024 / 1024
	c.log("INFO", fmt.Sprintf("收到图片数据 [%.2f MB]", sizeMB))

	// 调用回调函数（通知 App 层写入本地剪贴板）
	if c.clipboardCallback != nil {
		c.clipboardCallback("image", imageData)
	}
}

// SendClipboardBinary 发送剪贴板数据（V1.1 二进制协议）
// dataType: "text" 或 "image"
// content: 对于文本是字符串字节，对于图片是原始二进制数据
func (c *WSClient) SendClipboardBinary(dataType string, content []byte) error {
	c.mu.RLock()
	if !c.isConnected {
		c.mu.RUnlock()
		return fmt.Errorf("客户端未连接")
	}
	c.mu.RUnlock()

	c.log("INFO", fmt.Sprintf("发送剪贴板数据: %s", dataType))

	var data []byte
	var err error

	switch dataType {
	case "text":
		data, err = c.protocolMgr.CreateText(string(content))
	case "image":
		data, err = c.protocolMgr.CreateImageFrame(content, "image/png")
	default:
		return fmt.Errorf("不支持的数据类型: %s", dataType)
	}

	if err != nil {
		return err
	}

	return c.sendBinaryData(data)
}

// SendClipboard 发送剪贴板数据（兼容旧接口，内部将 Base64 转为二进制）
// 注意：此方法保留用于兼容，推荐使用 SendClipboardBinary
func (c *WSClient) SendClipboard(dataType, content string) error {
	switch dataType {
	case "text":
		return c.SendClipboardBinary("text", []byte(content))
	case "image":
		// content 是 Base64 编码的图片，需要解码
		imageData, err := base64.StdEncoding.DecodeString(content)
		if err != nil {
			return fmt.Errorf("Base64 解码失败: %w", err)
		}
		return c.SendClipboardBinary("image", imageData)
	default:
		return fmt.Errorf("不支持的数据类型: %s", dataType)
	}
}

// sendBinaryData 发送二进制数据
func (c *WSClient) sendBinaryData(data []byte) error {
	c.mu.RLock()
	conn := c.conn
	c.mu.RUnlock()

	if conn == nil {
		return fmt.Errorf("连接未建立")
	}

	conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
	return conn.WriteMessage(websocket.BinaryMessage, data)
}

// IsConnected 检查是否已连接
func (c *WSClient) IsConnected() bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.isConnected
}

// log 记录日志
func (c *WSClient) log(level, message string) {
	if c.logCb != nil {
		c.logCb(level, message)
	}
}
