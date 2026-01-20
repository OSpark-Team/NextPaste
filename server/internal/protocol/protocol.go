package protocol

import (
	"encoding/json"
	"time"

	"github.com/google/uuid"
)

// SyncAction 定义消息动作类型
type SyncAction string

const (
	ActionHandshake     SyncAction = "HANDSHAKE"
	ActionClipboardSync SyncAction = "CLIPBOARD_SYNC"
	ActionHeartbeat     SyncAction = "HEARTBEAT"
)

// DataType 定义剪贴板数据类型
type DataType string

const (
	DataTypeText  DataType = "text"
	DataTypeImage DataType = "image"
	DataTypeHTML  DataType = "html"
)

// SyncMessage 定义协议消息结构
type SyncMessage struct {
	Action    SyncAction      `json:"action"`
	ID        string          `json:"id"`
	Timestamp int64           `json:"timestamp"`
	SenderID  string          `json:"senderId"`
	Data      json.RawMessage `json:"data"`
}

// HandshakePayload 握手消息负载
type HandshakePayload struct {
	DeviceName string `json:"deviceName"`
	Platform   string `json:"platform"`
}

// ClipboardPayload 剪贴板同步消息负载
type ClipboardPayload struct {
	Type     DataType `json:"type"`
	MimeType string   `json:"mimeType"`
	Content  string   `json:"content"`
	Preview  string   `json:"preview,omitempty"`
}

// HeartbeatPayload 心跳消息负载
type HeartbeatPayload struct {
	Uptime int64 `json:"uptime,omitempty"`
}

// CreateMessage 创建协议消息
func CreateMessage(action SyncAction, senderID string, data interface{}) (*SyncMessage, error) {
	dataBytes, err := json.Marshal(data)
	if err != nil {
		return nil, err
	}

	return &SyncMessage{
		Action:    action,
		ID:        uuid.New().String(),
		Timestamp: time.Now().UnixMilli(),
		SenderID:  senderID,
		Data:      dataBytes,
	}, nil
}

// ParseMessage 解析协议消息
func ParseMessage(data []byte) (*SyncMessage, error) {
	var msg SyncMessage
	if err := json.Unmarshal(data, &msg); err != nil {
		return nil, err
	}
	return &msg, nil
}

// ParseHandshakePayload 解析握手负载
func ParseHandshakePayload(data json.RawMessage) (*HandshakePayload, error) {
	var payload HandshakePayload
	if err := json.Unmarshal(data, &payload); err != nil {
		return nil, err
	}
	return &payload, nil
}

// ParseClipboardPayload 解析剪贴板负载
func ParseClipboardPayload(data json.RawMessage) (*ClipboardPayload, error) {
	var payload ClipboardPayload
	if err := json.Unmarshal(data, &payload); err != nil {
		return nil, err
	}
	return &payload, nil
}

// ParseHeartbeatPayload 解析心跳负载
func ParseHeartbeatPayload(data json.RawMessage) (*HeartbeatPayload, error) {
	var payload HeartbeatPayload
	if err := json.Unmarshal(data, &payload); err != nil {
		return nil, err
	}
	return &payload, nil
}

// ToJSON 将消息转换为 JSON 字符串
func (m *SyncMessage) ToJSON() ([]byte, error) {
	return json.Marshal(m)
}

