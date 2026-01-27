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

// Message WebSocket 消息
type Message struct {
	Type int
	Data []byte
}

// Client 表示一个 WebSocket 客户端
type Client struct {
	ID       string
	RoomID   string
	Conn     *websocket.Conn
	Send     chan Message
	ConnTime time.Time
	IsV2     bool // 标记是否为 V2 客户端
}

// Room 表示一个房间
type Room struct {
	ID      string
	Clients map[string]*Client
	mu      sync.RWMutex
}

// RelayServer 中继服务器
type RelayServer struct {
	roomsV1 map[string]*Room
	roomsV2 map[string]*Room
	mu      sync.RWMutex
}

// NewRelayServer 创建中继服务器
func NewRelayServer() *RelayServer {
	return &RelayServer{
		roomsV1: make(map[string]*Room),
		roomsV2: make(map[string]*Room),
	}
}

// HandleWebSocket 处理 WebSocket 连接 (V1: /ws/{roomID})
func (s *RelayServer) HandleWebSocket(w http.ResponseWriter, r *http.Request) {
	// 从 URL 路径提取房间 ID
	// 格式: /ws/{roomID}
	path := r.URL.Path
	parts := strings.Split(strings.Trim(path, "/"), "/")
	if len(parts) != 2 || parts[0] != "ws" {
		http.Error(w, "Invalid path format. Use: /ws/{roomID}", http.StatusBadRequest)
		return
	}

	s.serveWS(w, r, parts[1], false)
}

// HandleWebSocketV2 处理 V2 WebSocket 连接 (/v2/ws/{roomID})
func (s *RelayServer) HandleWebSocketV2(w http.ResponseWriter, r *http.Request) {
	// 格式: /v2/ws/{roomID}
	path := r.URL.Path
	parts := strings.Split(strings.Trim(path, "/"), "/")
	if len(parts) != 3 || parts[0] != "v2" || parts[1] != "ws" {
		http.Error(w, "Invalid path format. Use: /v2/ws/{roomID}", http.StatusBadRequest)
		return
	}

	s.serveWS(w, r, parts[2], true)
}

// serveWS 通用 WebSocket 处理逻辑
func (s *RelayServer) serveWS(w http.ResponseWriter, r *http.Request, roomID string, isV2 bool) {
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
		Send:     make(chan Message, 256),
		ConnTime: time.Now(),
		IsV2:     isV2,
	}

	// 获取或创建房间
	room := s.getOrCreateRoom(roomID, isV2)

	// 添加客户端到房间
	room.addClient(client)

	log.Printf("✅ 新客户端连接 [房间: %s] [客户端: %s] [来自: %s]", roomID, client.ID[:8], r.RemoteAddr)
	log.Printf("📊 房间 [%s] 当前客户端数: %d", roomID, room.getClientCount())

	// 启动读写协程
	go s.readPump(client, room)
	go s.writePump(client, room)
}

// getOrCreateRoom 获取或创建房间
func (s *RelayServer) getOrCreateRoom(roomID string, isV2 bool) *Room {
	s.mu.Lock()
	defer s.mu.Unlock()

	var targetMap map[string]*Room
	if isV2 {
		targetMap = s.roomsV2
	} else {
		targetMap = s.roomsV1
	}

	room, exists := targetMap[roomID]
	if !exists {
		room = &Room{
			ID:      roomID,
			Clients: make(map[string]*Client),
		}
		targetMap[roomID] = room
		vStr := "V1"
		if isV2 {
			vStr = "V2"
		}
		log.Printf("🏠 创建新房间 (%s): %s", vStr, roomID)
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
func (r *Room) broadcast(msg Message, excludeID string) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	for id, client := range r.Clients {
		if id != excludeID {
			select {
			case client.Send <- msg:
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
			s.removeRoom(client.RoomID, client.IsV2)
		}
	}()

	client.Conn.SetReadDeadline(time.Now().Add(60 * time.Second))
	client.Conn.SetPongHandler(func(string) error {
		client.Conn.SetReadDeadline(time.Now().Add(60 * time.Second))
		return nil
	})

	for {
		msgType, message, err := client.Conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("❌ 客户端异常断开 [房间: %s] [客户端: %s]: %v", client.RoomID, client.ID[:8], err)
			}
			break
		}

		// 转发消息给房间内其他客户端
		// log.Printf("📨 转发消息 [房间: %s] [来自: %s] [类型: %d] [大小: %d 字节]", client.RoomID, client.ID[:8], msgType, len(message))
		room.broadcast(Message{Type: msgType, Data: message}, client.ID)
	}
}

// writePump 向客户端发送消息
func (s *RelayServer) writePump(client *Client, _ *Room) {
	ticker := time.NewTicker(30 * time.Second)
	defer func() {
		ticker.Stop()
		client.Conn.Close()
	}()

	for {
		select {
		case msg, ok := <-client.Send:
			client.Conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if !ok {
				client.Conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}

			if err := client.Conn.WriteMessage(msg.Type, msg.Data); err != nil {
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
func (s *RelayServer) removeRoom(roomID string, isV2 bool) {
	s.mu.Lock()
	defer s.mu.Unlock()

	var targetMap map[string]*Room
	if isV2 {
		targetMap = s.roomsV2
	} else {
		targetMap = s.roomsV1
	}

	if room, exists := targetMap[roomID]; exists {
		if room.getClientCount() == 0 {
			delete(targetMap, roomID)
			vStr := "V1"
			if isV2 {
				vStr = "V2"
			}
			log.Printf("🗑️  删除空房间 (%s): %s", vStr, roomID)
		}
	}
}

// Shutdown 关闭服务器
func (s *RelayServer) Shutdown() {
	s.mu.Lock()
	defer s.mu.Unlock()

	log.Printf("🔄 正在关闭所有连接...")

	closeRooms := func(rooms map[string]*Room) {
		for roomID, room := range rooms {
			room.mu.Lock()
			for _, client := range room.Clients {
				close(client.Send)
				client.Conn.Close()
			}
			room.mu.Unlock()
			log.Printf("✅ 房间 [%s] 已关闭", roomID)
		}
	}

	closeRooms(s.roomsV1)
	closeRooms(s.roomsV2)

	s.roomsV1 = make(map[string]*Room)
	s.roomsV2 = make(map[string]*Room)
	log.Printf("✅ 所有连接已关闭")
}

// GetStats 获取服务器统计信息
func (s *RelayServer) GetStats() map[string]interface{} {
	s.mu.RLock()
	defer s.mu.RUnlock()

	totalClients := 0
	roomStats := make([]map[string]interface{}, 0)

	collectStats := func(rooms map[string]*Room, version string) {
		for roomID, room := range rooms {
			clientCount := room.getClientCount()
			totalClients += clientCount

			roomStats = append(roomStats, map[string]interface{}{
				"roomID":      roomID,
				"version":     version,
				"clientCount": clientCount,
			})
		}
	}

	collectStats(s.roomsV1, "V1")
	collectStats(s.roomsV2, "V2")

	return map[string]interface{}{
		"totalRooms":   len(s.roomsV1) + len(s.roomsV2),
		"totalClients": totalClients,
		"rooms":        roomStats,
	}
}
