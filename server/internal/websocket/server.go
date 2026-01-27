package websocket

import (
	"context"
	"encoding/base64"
	"errors"
	"fmt"
	"log"
	"net"
	"net/http"
	"sync"
	"time"

	"server/internal/protocol"

	"github.com/google/uuid"
	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true // 允许所有来源
	},
}

// Client 表示一个 WebSocket 客户端
type Client struct {
	ID         string
	Conn       *websocket.Conn
	DeviceName string
	Platform   string
	ConnTime   time.Time
	Send       chan []byte
	mu         sync.RWMutex
}

// LogCallback 日志回调函数
type LogCallback func(level, message string)

// BinaryClipboardCallback 剪贴板数据回调函数（V1.1 二进制协议）
// dataType: "text" 或 "image"
// content: 文本字符串或图片二进制数据（不再是 Base64）
type BinaryClipboardCallback func(dataType string, content []byte)

// Server WebSocket 服务器（V1.1 二进制协议版本）
type Server struct {
	address           string
	port              int
	server            *http.Server
	clients           map[string]*Client
	mu                sync.RWMutex
	ctx               context.Context
	cancel            context.CancelFunc
	isRunning         bool
	logCb             LogCallback
	clipboardCallback BinaryClipboardCallback

	// V1.1 二进制协议管理器
	protocolMgr *protocol.BinaryProtocolManager
}

// NewServer 创建 WebSocket 服务器
func NewServer() *Server {
	return &Server{
		clients:     make(map[string]*Client),
		protocolMgr: protocol.NewBinaryProtocolManager(),
	}
}

// SetClipboardCallback 设置剪贴板数据回调（V1.1）
func (s *Server) SetClipboardCallback(cb BinaryClipboardCallback) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.clipboardCallback = cb
}

// Start 启动服务器
func (s *Server) Start(address string, port int, logCb LogCallback) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.isRunning {
		return fmt.Errorf("server is already running")
	}

	s.address = address
	s.port = port
	s.logCb = logCb
	s.ctx, s.cancel = context.WithCancel(context.Background())

	mux := http.NewServeMux()
	mux.HandleFunc("/ws", s.handleWebSocket)

	s.server = &http.Server{
		Addr:    fmt.Sprintf("%s:%d", address, port),
		Handler: mux,
	}

	s.isRunning = true

	go func() {
		s.log("INFO", fmt.Sprintf("WebSocket 服务器启动在 %s:%d (V1.1 二进制协议)", address, port))
		if err := s.server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			s.log("ERROR", fmt.Sprintf("服务器错误: %v", err))
		}
	}()

	return nil
}

// Stop 停止服务器
func (s *Server) Stop() error {
	s.mu.Lock()
	defer s.mu.Unlock()

	if !s.isRunning {
		return nil
	}

	if s.cancel != nil {
		s.cancel()
	}

	// 关闭所有客户端连接
	for _, client := range s.clients {
		client.Conn.Close()
		close(client.Send)
	}
	s.clients = make(map[string]*Client)

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := s.server.Shutdown(ctx); err != nil {
		s.log("ERROR", fmt.Sprintf("关闭服务器失败: %v", err))
		return err
	}

	s.isRunning = false
	s.log("INFO", "WebSocket 服务器已停止")
	return nil
}

// handleWebSocket 处理 WebSocket 连接
func (s *Server) handleWebSocket(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		s.log("ERROR", fmt.Sprintf("WebSocket 升级失败: %v", err))
		return
	}

	client := &Client{
		ID:       uuid.New().String(),
		Conn:     conn,
		ConnTime: time.Now(),
		Send:     make(chan []byte, 256),
	}

	s.mu.Lock()
	s.clients[client.ID] = client
	s.mu.Unlock()

	s.log("INFO", fmt.Sprintf("新客户端连接: %s (来自 %s)", client.ID, r.RemoteAddr))

	// 启动读写协程
	go s.readPump(client)
	go s.writePump(client)
}

// readPump 读取客户端消息（V1.1 二进制协议）
func (s *Server) readPump(client *Client) {
	defer func() {
		s.removeClient(client)
		client.Conn.Close()
	}()

	client.Conn.SetReadDeadline(time.Now().Add(60 * time.Second))
	client.Conn.SetPongHandler(func(string) error {
		client.Conn.SetReadDeadline(time.Now().Add(60 * time.Second))
		return nil
	})

	for {
		messageType, message, err := client.Conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				s.log("ERROR", fmt.Sprintf("客户端 %s 异常断开: %v", client.ID, err))
			}
			break
		}

		// V1.1 二进制协议：只处理二进制消息
		if messageType != websocket.BinaryMessage {
			s.log("WARNING", "收到非二进制消息，不兼容的协议版本")
			continue
		}

		s.handleBinaryMessage(client, message)
	}
}

// writePump 向客户端发送消息（V1.1 二进制协议）
func (s *Server) writePump(client *Client) {
	ticker := time.NewTicker(30 * time.Second)
	defer func() {
		ticker.Stop()
		client.Conn.Close()
	}()

	for {
		select {
		case message, ok := <-client.Send:
			client.Conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if !ok {
				client.Conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}

			// V1.1: 使用二进制帧发送
			if err := client.Conn.WriteMessage(websocket.BinaryMessage, message); err != nil {
				return
			}

		case <-ticker.C:
			client.Conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if err := client.Conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

// handleBinaryMessage 处理二进制消息（V1.1）
func (s *Server) handleBinaryMessage(client *Client, data []byte) {
	msg, err := s.protocolMgr.Parse(data)
	if err != nil {
		// 回环消息静默忽略
		if errors.Is(err, protocol.ErrLoopbackDetected) {
			return
		}
		s.log("ERROR", fmt.Sprintf("解析二进制消息失败: %v", err))
		return
	}

	switch msg.Type {
	case protocol.TypeHandshake:
		s.handleBinaryHandshake(client, msg)
	case protocol.TypeText:
		s.handleBinaryText(client, msg)
	case protocol.TypeImage:
		s.handleBinaryImage(client, msg)
	case protocol.TypeHeartbeat:
		// 心跳消息只需重置读取超时，无需特殊处理
	default:
		s.log("WARNING", fmt.Sprintf("未知的消息类型: 0x%02X", msg.Type))
	}
}

// handleBinaryHandshake 处理握手消息（V1.1）
func (s *Server) handleBinaryHandshake(client *Client, msg *protocol.BinaryMessage) {
	meta, err := msg.GetHandshakeMeta()
	if err != nil {
		s.log("ERROR", fmt.Sprintf("解析握手消息失败: %v", err))
		return
	}

	client.mu.Lock()
	client.DeviceName = meta.Name
	client.Platform = meta.OS
	client.mu.Unlock()

	s.log("SUCCESS", fmt.Sprintf("客户端握手成功: %s (%s) [协议 V1.%d]", meta.Name, meta.OS, meta.Ver%10))
}

// handleBinaryText 处理文本消息（V1.1）
func (s *Server) handleBinaryText(client *Client, msg *protocol.BinaryMessage) {
	text := msg.GetTextContent()

	client.mu.RLock()
	deviceName := client.DeviceName
	client.mu.RUnlock()

	s.log("INFO", fmt.Sprintf("收到文本数据 [%d 字符] 来自 %s", len(text), deviceName))

	// 调用回调函数（通知 App 层写入本地剪贴板）
	if s.clipboardCallback != nil {
		s.clipboardCallback("text", []byte(text))
	}

	// 广播给其他客户端
	s.broadcastBinary(msg, client.ID)
}

// handleBinaryImage 处理图片消息（V1.1）
func (s *Server) handleBinaryImage(client *Client, msg *protocol.BinaryMessage) {
	imageData := msg.GetImageData()

	client.mu.RLock()
	deviceName := client.DeviceName
	client.mu.RUnlock()

	sizeMB := float64(len(imageData)) / 1024 / 1024
	s.log("INFO", fmt.Sprintf("收到图片数据 [%.2f MB] 来自 %s", sizeMB, deviceName))

	// 调用回调函数（通知 App 层写入本地剪贴板）
	if s.clipboardCallback != nil {
		s.clipboardCallback("image", imageData)
	}

	// 广播给其他客户端
	s.broadcastBinary(msg, client.ID)
}

// broadcastBinary 广播二进制消息给所有客户端（除了发送者）
func (s *Server) broadcastBinary(msg *protocol.BinaryMessage, excludeID string) {
	// 重新封装消息以使用服务器的 UUID
	var data []byte
	var err error

	switch msg.Type {
	case protocol.TypeText:
		data, err = s.protocolMgr.CreateText(msg.GetTextContent())
	case protocol.TypeImage:
		imageData := msg.GetImageData()
		mime := "image/png"
		if msg.Meta != nil && msg.Meta.Mime != "" {
			mime = msg.Meta.Mime
		}
		data, err = s.protocolMgr.CreateImageFrame(imageData, mime)
	default:
		return
	}

	if err != nil {
		s.log("ERROR", fmt.Sprintf("封装广播消息失败: %v", err))
		return
	}

	s.mu.RLock()
	defer s.mu.RUnlock()

	for id, client := range s.clients {
		if id != excludeID {
			select {
			case client.Send <- data:
			default:
				s.log("WARNING", fmt.Sprintf("客户端 %s 发送队列已满", id))
			}
		}
	}
}

// BroadcastClipboardBinary 广播剪贴板数据（V1.1 二进制协议）
// dataType: "text" 或 "image"
// content: 对于文本是字符串字节，对于图片是原始二进制数据
func (s *Server) BroadcastClipboardBinary(dataType string, content []byte) error {
	s.log("INFO", fmt.Sprintf("广播剪贴板数据: %s", dataType))

	var data []byte
	var err error

	switch dataType {
	case "text":
		data, err = s.protocolMgr.CreateText(string(content))
	case "image":
		data, err = s.protocolMgr.CreateImageFrame(content, "image/png")
	default:
		return fmt.Errorf("不支持的数据类型: %s", dataType)
	}

	if err != nil {
		return err
	}

	s.mu.RLock()
	defer s.mu.RUnlock()

	for _, client := range s.clients {
		select {
		case client.Send <- data:
		default:
			s.log("WARNING", fmt.Sprintf("客户端 %s 发送队列已满", client.ID))
		}
	}

	return nil
}

// BroadcastClipboard 广播剪贴板数据（兼容旧接口，内部将 Base64 转为二进制）
// 注意：此方法保留用于兼容，推荐使用 BroadcastClipboardBinary
func (s *Server) BroadcastClipboard(dataType, content string) error {
	switch dataType {
	case "text":
		return s.BroadcastClipboardBinary("text", []byte(content))
	case "image":
		// content 是 Base64 编码的图片，需要解码
		imageData, err := base64.StdEncoding.DecodeString(content)
		if err != nil {
			return fmt.Errorf("Base64 解码失败: %w", err)
		}
		return s.BroadcastClipboardBinary("image", imageData)
	default:
		return fmt.Errorf("不支持的数据类型: %s", dataType)
	}
}

// removeClient 移除客户端
func (s *Server) removeClient(client *Client) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, ok := s.clients[client.ID]; ok {
		delete(s.clients, client.ID)
		client.mu.RLock()
		deviceName := client.DeviceName
		client.mu.RUnlock()
		s.log("INFO", fmt.Sprintf("客户端断开: %s", deviceName))
	}
}

// GetClientCount 获取客户端数量
func (s *Server) GetClientCount() int {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return len(s.clients)
}

// GetClients 获取所有客户端信息
func (s *Server) GetClients() []map[string]interface{} {
	s.mu.RLock()
	defer s.mu.RUnlock()

	clients := make([]map[string]interface{}, 0, len(s.clients))
	for _, client := range s.clients {
		client.mu.RLock()
		clients = append(clients, map[string]interface{}{
			"id":         client.ID,
			"deviceName": client.DeviceName,
			"platform":   client.Platform,
			"connTime":   client.ConnTime.Format("2006-01-02 15:04:05"),
		})
		client.mu.RUnlock()
	}
	return clients
}

// IsRunning 检查服务器是否运行中
func (s *Server) IsRunning() bool {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.isRunning
}

// GetLocalIPs 获取本机所有 IP 地址
func (s *Server) GetLocalIPs() ([]string, error) {
	var ips []string

	interfaces, err := net.Interfaces()
	if err != nil {
		return nil, err
	}

	for _, iface := range interfaces {
		// 跳过未启用的接口
		if iface.Flags&net.FlagUp == 0 {
			continue
		}

		addrs, err := iface.Addrs()
		if err != nil {
			continue
		}

		for _, addr := range addrs {
			var ip net.IP
			switch v := addr.(type) {
			case *net.IPNet:
				ip = v.IP
			case *net.IPAddr:
				ip = v.IP
			}

			// 只返回 IPv4 地址，排除回环地址
			if ip != nil && ip.To4() != nil && !ip.IsLoopback() {
				ips = append(ips, ip.String())
			}
		}
	}

	return ips, nil
}

// log 记录日志
func (s *Server) log(level, message string) {
	if s.logCb != nil {
		s.logCb(level, message)
	} else {
		log.Printf("[%s] %s", level, message)
	}
}
