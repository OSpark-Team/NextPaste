package main

import (
	"log"
	"net/http"
	"strings"
	"sync"
	"time"

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
	ID       string
	RoomID   string
	Conn     *websocket.Conn
	Send     chan []byte
	ConnTime time.Time
}

// Room 表示一个房间
type Room struct {
	ID      string
	Clients map[string]*Client
	mu      sync.RWMutex
}

// RelayServer 中继服务器
type RelayServer struct {
	rooms map[string]*Room
	mu    sync.RWMutex
}

// NewRelayServer 创建中继服务器
func NewRelayServer() *RelayServer {
	return &RelayServer{
		rooms: make(map[string]*Room),
	}
}

// HandleWebSocket 处理 WebSocket 连接
func (s *RelayServer) HandleWebSocket(w http.ResponseWriter, r *http.Request) {
	// 从 URL 路径提取房间 ID
	// 格式: /ws/{roomID}
	path := r.URL.Path
	parts := strings.Split(strings.Trim(path, "/"), "/")
	if len(parts) != 2 || parts[0] != "ws" {
		http.Error(w, "Invalid path format. Use: /ws/{roomID}", http.StatusBadRequest)
		return
	}

	roomID := parts[1]
	if roomID == "" {
		http.Error(w, "Room ID cannot be empty", http.StatusBadRequest)
		return
	}

	// 升级到 WebSocket
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("❌ WebSocket 升级失败: %v", err)
		return
	}

	// 创建客户端
	client := &Client{
		ID:       uuid.New().String(),
		RoomID:   roomID,
		Conn:     conn,
		Send:     make(chan []byte, 256),
		ConnTime: time.Now(),
	}

	// 获取或创建房间
	room := s.getOrCreateRoom(roomID)

	// 添加客户端到房间
	room.addClient(client)

	log.Printf("✅ 新客户端连接 [房间: %s] [客户端: %s] [来自: %s]", roomID, client.ID[:8], r.RemoteAddr)
	log.Printf("📊 房间 [%s] 当前客户端数: %d", roomID, room.getClientCount())

	// 启动读写协程
	go s.readPump(client, room)
	go s.writePump(client, room)
}

// getOrCreateRoom 获取或创建房间
func (s *RelayServer) getOrCreateRoom(roomID string) *Room {
	s.mu.Lock()
	defer s.mu.Unlock()

	room, exists := s.rooms[roomID]
	if !exists {
		room = &Room{
			ID:      roomID,
			Clients: make(map[string]*Client),
		}
		s.rooms[roomID] = room
		log.Printf("🏠 创建新房间: %s", roomID)
	}

	return room
}

// addClient 添加客户端到房间
func (r *Room) addClient(client *Client) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.Clients[client.ID] = client
}

// removeClient 从房间移除客户端
func (r *Room) removeClient(client *Client) {
	r.mu.Lock()
	defer r.mu.Unlock()
	delete(r.Clients, client.ID)
}

// getClientCount 获取房间客户端数量
func (r *Room) getClientCount() int {
	r.mu.RLock()
	defer r.mu.RUnlock()
	return len(r.Clients)
}

// broadcast 广播消息给房间内所有客户端（除了发送者）
func (r *Room) broadcast(message []byte, excludeID string) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	for id, client := range r.Clients {
		if id != excludeID {
			select {
			case client.Send <- message:
			default:
				log.Printf("⚠️  客户端 %s 发送队列已满", id[:8])
			}
		}
	}
}

// readPump 读取客户端消息
func (s *RelayServer) readPump(client *Client, room *Room) {
	defer func() {
		room.removeClient(client)
		client.Conn.Close()
		log.Printf("👋 客户端断开 [房间: %s] [客户端: %s]", client.RoomID, client.ID[:8])
		log.Printf("📊 房间 [%s] 当前客户端数: %d", client.RoomID, room.getClientCount())

		// 如果房间为空，删除房间
		if room.getClientCount() == 0 {
			s.removeRoom(client.RoomID)
		}
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
				log.Printf("❌ 客户端异常断开 [房间: %s] [客户端: %s]: %v", client.RoomID, client.ID[:8], err)
			}
			break
		}

		// 转发消息给房间内其他客户端
		log.Printf("📨 转发消息 [房间: %s] [来自: %s] [大小: %d 字节]", client.RoomID, client.ID[:8], len(message))
		room.broadcast(message, client.ID)
	}
}

// writePump 向客户端发送消息
func (s *RelayServer) writePump(client *Client, room *Room) {
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

// removeRoom 删除空房间
func (s *RelayServer) removeRoom(roomID string) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if room, exists := s.rooms[roomID]; exists {
		if room.getClientCount() == 0 {
			delete(s.rooms, roomID)
			log.Printf("🗑️  删除空房间: %s", roomID)
		}
	}
}

// Shutdown 关闭服务器
func (s *RelayServer) Shutdown() {
	s.mu.Lock()
	defer s.mu.Unlock()

	log.Printf("🔄 正在关闭所有连接...")

	for roomID, room := range s.rooms {
		room.mu.Lock()
		for _, client := range room.Clients {
			close(client.Send)
			client.Conn.Close()
		}
		room.mu.Unlock()
		log.Printf("✅ 房间 [%s] 已关闭", roomID)
	}

	s.rooms = make(map[string]*Room)
	log.Printf("✅ 所有连接已关闭")
}

// GetStats 获取服务器统计信息
func (s *RelayServer) GetStats() map[string]interface{} {
	s.mu.RLock()
	defer s.mu.RUnlock()

	totalClients := 0
	roomStats := make([]map[string]interface{}, 0)

	for roomID, room := range s.rooms {
		clientCount := room.getClientCount()
		totalClients += clientCount

		roomStats = append(roomStats, map[string]interface{}{
			"roomID":      roomID,
			"clientCount": clientCount,
		})
	}

	return map[string]interface{}{
		"totalRooms":   len(s.rooms),
		"totalClients": totalClients,
		"rooms":        roomStats,
	}
}
