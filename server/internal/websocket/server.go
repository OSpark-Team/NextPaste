package websocket

import (
	"context"
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

// ClipboardCallback 剪贴板数据回调函数
type ClipboardCallback func(payload protocol.ClipboardPayload)

// Server WebSocket 服务器
type Server struct {
	address           string
	port              int
	server            *http.Server
	clients           map[string]*Client
	mu                sync.RWMutex
	ctx               context.Context
	cancel            context.CancelFunc
	isRunning         bool
	serverID          string
	logCb             LogCallback
	clipboardCallback ClipboardCallback
}

// NewServer 创建 WebSocket 服务器
func NewServer() *Server {
	return &Server{
		clients:  make(map[string]*Client),
		serverID: uuid.New().String(),
	}
}

// SetClipboardCallback 设置剪贴板数据回调
func (s *Server) SetClipboardCallback(cb ClipboardCallback) {
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
		s.log("INFO", fmt.Sprintf("WebSocket 服务器启动在 %s:%d", address, port))
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

// readPump 读取客户端消息
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
		_, message, err := client.Conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				s.log("ERROR", fmt.Sprintf("客户端 %s 异常断开: %v", client.ID, err))
			}
			break
		}

		s.handleMessage(client, message)
	}
}

// writePump 向客户端发送消息
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

			if err := client.Conn.WriteMessage(websocket.TextMessage, message); err != nil {
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

// handleMessage 处理客户端消息
func (s *Server) handleMessage(client *Client, data []byte) {
	msg, err := protocol.ParseMessage(data)
	if err != nil {
		s.log("ERROR", fmt.Sprintf("解析消息失败: %v", err))
		return
	}

	// 忽略来自服务器自己的消息
	if msg.SenderID == s.serverID {
		return
	}

	switch msg.Action {
	case protocol.ActionHandshake:
		s.handleHandshake(client, msg)
	case protocol.ActionClipboardSync:
		s.handleClipboardSync(client, msg)
	case protocol.ActionHeartbeat:
		s.handleHeartbeat(client, msg)
	default:
		s.log("WARNING", fmt.Sprintf("未知的消息类型: %s", msg.Action))
	}
}

// handleHandshake 处理握手消息
func (s *Server) handleHandshake(client *Client, msg *protocol.SyncMessage) {
	payload, err := protocol.ParseHandshakePayload(msg.Data)
	if err != nil {
		s.log("ERROR", fmt.Sprintf("解析握手消息失败: %v", err))
		return
	}

	client.mu.Lock()
	client.DeviceName = payload.DeviceName
	client.Platform = payload.Platform
	client.mu.Unlock()

	s.log("SUCCESS", fmt.Sprintf("客户端握手成功: %s (%s)", payload.DeviceName, payload.Platform))
}

// handleClipboardSync 处理剪贴板同步消息
func (s *Server) handleClipboardSync(client *Client, msg *protocol.SyncMessage) {
	payload, err := protocol.ParseClipboardPayload(msg.Data)
	if err != nil {
		s.log("ERROR", fmt.Sprintf("解析剪贴板消息失败: %v", err))
		return
	}

	client.mu.RLock()
	deviceName := client.DeviceName
	client.mu.RUnlock()

	s.log("INFO", fmt.Sprintf("收到剪贴板数据 [%s] 来自 %s", payload.Type, deviceName))

	// 调用回调函数（通知 App 层写入本地剪贴板）
	if s.clipboardCallback != nil {
		s.clipboardCallback(*payload)
	}

	// 广播给其他客户端
	s.broadcast(msg, client.ID)
}

// handleHeartbeat 处理心跳消息
func (s *Server) handleHeartbeat(client *Client, msg *protocol.SyncMessage) {
	// 心跳消息不需要特殊处理，只需要重置读取超时
}

// broadcast 广播消息给所有客户端（除了发送者）
func (s *Server) broadcast(msg *protocol.SyncMessage, excludeID string) {
	data, err := msg.ToJSON()
	if err != nil {
		s.log("ERROR", fmt.Sprintf("序列化消息失败: %v", err))
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

// BroadcastClipboard 广播剪贴板数据
func (s *Server) BroadcastClipboard(dataType, content string) error {

	s.log("INFO", fmt.Sprintf("广播剪贴板数据: %s", dataType))

	payload := protocol.ClipboardPayload{
		Type:     protocol.DataType(dataType),
		MimeType: getMimeType(dataType),
		Content:  content,
	}

	msg, err := protocol.CreateMessage(protocol.ActionClipboardSync, s.serverID, payload)
	if err != nil {
		return err
	}

	data, err := msg.ToJSON()
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

// getMimeType 根据数据类型获取 MIME 类型
func getMimeType(dataType string) string {
	switch dataType {
	case "text":
		return "text/plain"
	case "image":
		return "image/png"
	default:
		return "application/octet-stream"
	}
}
