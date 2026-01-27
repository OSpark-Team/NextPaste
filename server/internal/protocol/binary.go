package protocol

import (
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"

	"github.com/google/uuid"
)

// ==========================================
// V1.1 二进制协议常量定义
// ==========================================

const (
	// ProtocolMagic 协议识别符 (ASCII 'NP')
	ProtocolMagic uint16 = 0x4E50
	// ProtocolVersion 协议版本
	ProtocolVersion uint8 = 0x01
	// HeaderSize 固定头部大小（33字节）
	// Magic(2) + VerType(1) + Flags(1) + Reserved(1) + MsgID(4) + Seq(4) + SenderID(16) + PayloadLen(4) = 33
	HeaderSize = 33
)

// MessageType 消息类型定义
type MessageType uint8

const (
	TypeHeartbeat MessageType = 0x0 // 心跳
	TypeHandshake MessageType = 0x1 // 握手
	TypeText      MessageType = 0x2 // 文本
	TypeImage     MessageType = 0x3 // 图片
	TypeFile      MessageType = 0x4 // 文件
)

// MessageFlags 标志位定义
type MessageFlags uint8

const (
	FlagNone    MessageFlags = 0x00 // 无标志
	FlagMF      MessageFlags = 0x01 // More Fragments，有后续分片
	FlagHasMeta MessageFlags = 0x02 // 包含元数据
)

// ==========================================
// 错误定义
// ==========================================

var (
	ErrInvalidMagic      = errors.New("无效的协议魔数")
	ErrPacketTooShort    = errors.New("数据包不足头部长度")
	ErrLoopbackDetected  = errors.New("检测到回环消息")
	ErrInvalidInput      = errors.New("输入参数无效")
	ErrMetaParseFailed   = errors.New("元数据解析失败")
	ErrUnsupportedFormat = errors.New("不支持的消息格式")
)

// ==========================================
// 数据结构定义
// ==========================================

// BinaryMessage 解析后的二进制消息
type BinaryMessage struct {
	Type       MessageType
	Flags      MessageFlags
	MsgID      uint32
	Seq        uint32
	SenderUUID []byte // 16字节
	Payload    []byte

	// 如果 Flags 包含 HAS_META，解析后的元数据
	Meta *TransferMeta
	// 如果 Flags 包含 HAS_META，剥离元数据后的纯二进制数据
	BinaryData []byte
}

// HandshakeMeta 握手消息元数据
type HandshakeMeta struct {
	Name string `json:"name"`
	OS   string `json:"os"`
	Ver  int    `json:"ver"`
}

// TransferMeta 文件/图片传输元数据
type TransferMeta struct {
	Name   string `json:"name,omitempty"`
	Mime   string `json:"mime,omitempty"`
	Size   int64  `json:"size,omitempty"`
	Hash   string `json:"hash,omitempty"`
	Width  int    `json:"width,omitempty"`
	Height int    `json:"height,omitempty"`
}

// ==========================================
// 二进制协议管理器
// ==========================================

// BinaryProtocolManager 二进制协议管理器
type BinaryProtocolManager struct {
	deviceUUID []byte // 16字节设备UUID
	msgCounter uint32 // 消息ID计数器
}

// NewBinaryProtocolManager 创建二进制协议管理器
func NewBinaryProtocolManager() *BinaryProtocolManager {
	// 生成随机UUID作为设备标识
	uuidBytes := make([]byte, 16)
	u := uuid.New()
	copy(uuidBytes, u[:])

	return &BinaryProtocolManager{
		deviceUUID: uuidBytes,
		msgCounter: 0,
	}
}

// GetDeviceUUID 获取设备UUID
func (m *BinaryProtocolManager) GetDeviceUUID() []byte {
	return m.deviceUUID
}

// getNextMsgID 获取下一个消息ID
func (m *BinaryProtocolManager) getNextMsgID() uint32 {
	m.msgCounter++
	return m.msgCounter
}

// ==========================================
// 封包方法
// ==========================================

// CreateHandshake 创建握手包
func (m *BinaryProtocolManager) CreateHandshake(deviceName, osName string) ([]byte, error) {
	meta := HandshakeMeta{
		Name: deviceName,
		OS:   osName,
		Ver:  11, // 协议版本 V1.1
	}

	payload, err := json.Marshal(meta)
	if err != nil {
		return nil, err
	}

	return m.pack(TypeHandshake, FlagNone, m.getNextMsgID(), 0, payload), nil
}

// CreateText 创建文本消息包
func (m *BinaryProtocolManager) CreateText(text string) ([]byte, error) {
	if len(text) == 0 {
		return nil, ErrInvalidInput
	}

	payload := []byte(text)
	return m.pack(TypeText, FlagNone, m.getNextMsgID(), 0, payload), nil
}

// CreateHeartbeat 创建心跳包
func (m *BinaryProtocolManager) CreateHeartbeat() []byte {
	return m.pack(TypeHeartbeat, FlagNone, m.getNextMsgID(), 0, nil)
}

// CreateImageChunks 创建图片分片消息
// chunkSize: 每个分片的 Payload 最大字节数 (建议 64*1024)
func (m *BinaryProtocolManager) CreateImageChunks(imageData []byte, mime string, chunkSize int) ([][]byte, error) {
	if len(imageData) == 0 {
		return nil, ErrInvalidInput
	}
	if chunkSize < 1024 {
		chunkSize = 64 * 1024 // 默认 64KB
	}

	msgID := m.getNextMsgID()
	meta := TransferMeta{
		Mime: mime,
		Size: int64(len(imageData)),
	}

	// 1. 准备元数据
	metaJSON, err := json.Marshal(meta)
	if err != nil {
		return nil, err
	}
	metaLen := len(metaJSON)

	// 计算首帧可用数据空间
	// 首帧 Header(33) + MetaLen(2) + MetaJSON + Data
	usedInPayload := 2 + metaLen
	firstChunkCap := chunkSize - usedInPayload
	if firstChunkCap < 0 {
		return nil, fmt.Errorf("元数据过大(%d)，无法放入单个分片(%d)", metaLen, chunkSize)
	}

	// 确定第一片数据
	var firstChunkData []byte
	var remainingData []byte

	if len(imageData) > firstChunkCap {
		firstChunkData = imageData[:firstChunkCap]
		remainingData = imageData[firstChunkCap:]
	} else {
		firstChunkData = imageData
		remainingData = nil
	}

	// 是否还有后续分片
	hasMore := len(remainingData) > 0

	// 创建首帧
	startFrame, err := m.createStartFrame(TypeImage, msgID, meta, firstChunkData, hasMore)
	if err != nil {
		return nil, err
	}

	chunks := [][]byte{startFrame}

	// 如果没有后续，直接返回
	if !hasMore {
		return chunks, nil
	}

	// 2. 创建后续分片
	seq := uint32(1)
	offset := 0
	totalRemaining := len(remainingData)

	for offset < totalRemaining {
		end := offset + chunkSize
		isLast := false
		if end >= totalRemaining {
			end = totalRemaining
			isLast = true
		}

		chunkData := remainingData[offset:end]

		flags := FlagNone
		if !isLast {
			flags = FlagMF
		}

		frame := m.pack(TypeImage, flags, msgID, seq, chunkData)
		chunks = append(chunks, frame)

		seq++
		offset = end
	}

	return chunks, nil
}

// CreateImageFrame 创建单帧图片消息 (仅适用于小图片)
func (m *BinaryProtocolManager) CreateImageFrame(imageData []byte, mime string) ([]byte, error) {
	if len(imageData) == 0 {
		return nil, ErrInvalidInput
	}

	meta := TransferMeta{
		Mime: mime,
		Size: int64(len(imageData)),
	}

	// 单帧意味着没有后续分片
	return m.createStartFrame(TypeImage, m.getNextMsgID(), meta, imageData, false)
}

// createStartFrame 创建带元数据的首帧
func (m *BinaryProtocolManager) createStartFrame(msgType MessageType, msgID uint32, meta TransferMeta, chunkData []byte, hasMore bool) ([]byte, error) {
	metaJSON, err := json.Marshal(meta)
	if err != nil {
		return nil, err
	}

	metaLen := len(metaJSON)
	if metaLen > 65535 {
		return nil, fmt.Errorf("元数据过大: %d bytes", metaLen)
	}

	// Payload 结构: [2字节元数据长度] + [元数据JSON] + [二进制数据]
	payloadLen := 2 + metaLen + len(chunkData)
	payload := make([]byte, payloadLen)

	// 元数据长度（大端序）
	binary.BigEndian.PutUint16(payload[0:2], uint16(metaLen))
	// 元数据内容
	copy(payload[2:2+metaLen], metaJSON)
	// 二进制数据
	copy(payload[2+metaLen:], chunkData)

	// 设置标志: HAS_META
	flags := FlagHasMeta
	if hasMore {
		flags |= FlagMF
	}

	return m.pack(msgType, flags, msgID, 0, payload), nil
}

// pack 底层封包方法
func (m *BinaryProtocolManager) pack(msgType MessageType, flags MessageFlags, msgID uint32, seq uint32, payload []byte) []byte {
	totalLen := HeaderSize + len(payload)
	buffer := make([]byte, totalLen)

	// Magic (2 bytes)
	binary.BigEndian.PutUint16(buffer[0:2], ProtocolMagic)

	// Version (高4位) | Type (低4位)
	verType := (ProtocolVersion << 4) | uint8(msgType&0x0F)
	buffer[2] = verType

	// Flags
	buffer[3] = uint8(flags)

	// Reserved
	buffer[4] = 0

	// MsgID (4 bytes, 从偏移5开始)
	binary.BigEndian.PutUint32(buffer[5:9], msgID)

	// Sequence (4 bytes, 从偏移9开始)
	binary.BigEndian.PutUint32(buffer[9:13], seq)

	// Sender UUID (16 bytes, 从偏移13开始)
	copy(buffer[13:29], m.deviceUUID)

	// Payload Length (4 bytes, 从偏移29开始)
	binary.BigEndian.PutUint32(buffer[29:33], uint32(len(payload)))

	// Payload
	if len(payload) > 0 {
		copy(buffer[HeaderSize:], payload)
	}

	return buffer
}

// ==========================================
// 解包方法
// ==========================================

// Parse 解析二进制消息
func (m *BinaryProtocolManager) Parse(data []byte) (*BinaryMessage, error) {
	if len(data) < HeaderSize {
		return nil, ErrPacketTooShort
	}

	// 校验 Magic
	magic := binary.BigEndian.Uint16(data[0:2])
	if magic != ProtocolMagic {
		return nil, fmt.Errorf("%w: 0x%04X", ErrInvalidMagic, magic)
	}

	// 提取 Sender UUID 并检查回环
	senderUUID := make([]byte, 16)
	copy(senderUUID, data[13:29])
	if m.isLoopback(senderUUID) {
		return nil, ErrLoopbackDetected
	}

	// 解析头部字段
	verType := data[2]
	// version := (verType >> 4) & 0x0F  // 可用于版本校验
	msgType := MessageType(verType & 0x0F)

	flags := MessageFlags(data[3])
	msgID := binary.BigEndian.Uint32(data[5:9])
	seq := binary.BigEndian.Uint32(data[9:13])
	payloadLen := binary.BigEndian.Uint32(data[29:33])

	// 提取 Payload
	if len(data) < HeaderSize+int(payloadLen) {
		return nil, fmt.Errorf("数据包不完整: 期望 %d 字节，实际 %d 字节", HeaderSize+payloadLen, len(data))
	}

	payload := data[HeaderSize : HeaderSize+payloadLen]

	msg := &BinaryMessage{
		Type:       msgType,
		Flags:      flags,
		MsgID:      msgID,
		Seq:        seq,
		SenderUUID: senderUUID,
		Payload:    payload,
	}

	// 如果包含元数据，解析元数据
	if flags&FlagHasMeta != 0 && len(payload) >= 2 {
		metaLen := binary.BigEndian.Uint16(payload[0:2])
		if len(payload) >= 2+int(metaLen) {
			metaJSON := payload[2 : 2+metaLen]
			var meta TransferMeta
			if err := json.Unmarshal(metaJSON, &meta); err != nil {
				return nil, fmt.Errorf("%w: %v", ErrMetaParseFailed, err)
			}
			msg.Meta = &meta
			msg.BinaryData = payload[2+metaLen:]
		}
	}

	return msg, nil
}

// isLoopback 检测是否为回环消息
func (m *BinaryProtocolManager) isLoopback(senderUUID []byte) bool {
	if len(senderUUID) != 16 || len(m.deviceUUID) != 16 {
		return false
	}
	for i := 0; i < 16; i++ {
		if senderUUID[i] != m.deviceUUID[i] {
			return false
		}
	}
	return true
}

// ==========================================
// 辅助方法
// ==========================================

// GetTextContent 从文本消息中获取文本内容
func (msg *BinaryMessage) GetTextContent() string {
	if msg.Type != TypeText {
		return ""
	}
	return string(msg.Payload)
}

// GetHandshakeMeta 从握手消息中获取元数据
func (msg *BinaryMessage) GetHandshakeMeta() (*HandshakeMeta, error) {
	if msg.Type != TypeHandshake {
		return nil, fmt.Errorf("不是握手消息")
	}

	var meta HandshakeMeta
	if err := json.Unmarshal(msg.Payload, &meta); err != nil {
		return nil, err
	}
	return &meta, nil
}

// GetImageData 从图片消息中获取图片数据
func (msg *BinaryMessage) GetImageData() []byte {
	if msg.Type != TypeImage {
		return nil
	}
	// 如果有元数据，返回剥离后的二进制数据
	if msg.BinaryData != nil {
		return msg.BinaryData
	}
	// 否则返回完整 payload
	return msg.Payload
}
