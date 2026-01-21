package websocket

import (
	"context"
	"fmt"
	"sync"
	"time"

	"server/internal/protocol"

	"github.com/google/uuid"
	"github.com/gorilla/websocket"
)

// WSClient WebSocket 客户端
type WSClient struct {
	url               string
	conn              *websocket.Conn
	ctx               context.Context
	cancel            context.CancelFunc
	isConnected       bool
	everConnected     bool // 是否曾经连接成功过
	mu                sync.RWMutex
	clientID          string
	deviceName        string
	platform          string
	logCb             LogCallback
	clipboardCallback ClipboardCallback
	onConnected       func() // 连接成功回调
	reconnectInterval time.Duration
	heartbeatInterval time.Duration
}

// NewWSClient 创建 WebSocket 客户端
func NewWSClient(deviceName, platform string) *WSClient {
	return &WSClient{
		clientID:          uuid.New().String(),
		deviceName:        deviceName,
		platform:          platform,
		reconnectInterval: 5 * time.Second,
		heartbeatInterval: 30 * time.Second,
	}
}

// SetClipboardCallback 设置剪贴板数据回调
func (c *WSClient) SetClipboardCallback(cb ClipboardCallback) {
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

	// 发送握手消息
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

// sendHandshake 发送握手消息
func (c *WSClient) sendHandshake() error {
	payload := protocol.HandshakePayload{
		DeviceName: c.deviceName,
		Platform:   c.platform,
	}

	msg, err := protocol.CreateMessage(protocol.ActionHandshake, c.clientID, payload)
	if err != nil {
		return err
	}

	return c.sendMessage(msg)
}

// readPump 读取服务器消息
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

			_, message, err := conn.ReadMessage()
			if err != nil {
				if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
					c.log("ERROR", fmt.Sprintf("连接异常断开: %v", err))
				}
				return
			}

			c.handleMessage(message)
		}
	}
}

// heartbeatPump 发送心跳
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

// sendHeartbeat 发送心跳消息
func (c *WSClient) sendHeartbeat() error {
	payload := protocol.HeartbeatPayload{}
	msg, err := protocol.CreateMessage(protocol.ActionHeartbeat, c.clientID, payload)
	if err != nil {
		return err
	}
	return c.sendMessage(msg)
}

// handleMessage 处理服务器消息
func (c *WSClient) handleMessage(data []byte) {
	msg, err := protocol.ParseMessage(data)
	if err != nil {
		c.log("ERROR", fmt.Sprintf("解析消息失败: %v", err))
		return
	}

	// 忽略来自自己的消息（回环检测）
	if msg.SenderID == c.clientID {
		return
	}

	switch msg.Action {
	case protocol.ActionClipboardSync:
		c.handleClipboardSync(msg)
	case protocol.ActionHeartbeat:
		// 心跳消息不需要处理
	default:
		c.log("WARNING", fmt.Sprintf("未知的消息类型: %s", msg.Action))
	}
}

// handleClipboardSync 处理剪贴板同步消息
func (c *WSClient) handleClipboardSync(msg *protocol.SyncMessage) {
	payload, err := protocol.ParseClipboardPayload(msg.Data)
	if err != nil {
		c.log("ERROR", fmt.Sprintf("解析剪贴板消息失败: %v", err))
		return
	}

	c.log("INFO", fmt.Sprintf("收到剪贴板数据 [%s]", payload.Type))

	// 调用回调函数（通知 App 层写入本地剪贴板）
	if c.clipboardCallback != nil {
		c.clipboardCallback(*payload)
	}
}

// SendClipboard 发送剪贴板数据
func (c *WSClient) SendClipboard(dataType, content string) error {
	c.mu.RLock()
	if !c.isConnected {
		c.mu.RUnlock()
		return fmt.Errorf("客户端未连接")
	}
	c.mu.RUnlock()

	c.log("INFO", fmt.Sprintf("发送剪贴板数据: %s", dataType))

	payload := protocol.ClipboardPayload{
		Type:     protocol.DataType(dataType),
		MimeType: getMimeType(dataType),
		Content:  content,
	}

	msg, err := protocol.CreateMessage(protocol.ActionClipboardSync, c.clientID, payload)
	if err != nil {
		return err
	}

	return c.sendMessage(msg)
}

// sendMessage 发送消息
func (c *WSClient) sendMessage(msg *protocol.SyncMessage) error {
	data, err := msg.ToJSON()
	if err != nil {
		return err
	}

	c.mu.RLock()
	conn := c.conn
	c.mu.RUnlock()

	if conn == nil {
		return fmt.Errorf("连接未建立")
	}

	conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
	return conn.WriteMessage(websocket.TextMessage, data)
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
