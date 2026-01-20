package main

import (
	"context"
	"fmt"
	"sync"

	"server/internal/clipboard"
	"server/internal/protocol"
	ws "server/internal/websocket"

	"github.com/wailsapp/wails/v2/pkg/runtime"
)

// LogEntry 日志条目
type LogEntry struct {
	Level     string `json:"level"`
	Message   string `json:"message"`
	Timestamp int64  `json:"timestamp"`
}

// App struct
type App struct {
	ctx          context.Context
	wsServer     *ws.Server
	clipboardMon *clipboard.Monitor
	logs         []LogEntry
	logsMu       sync.RWMutex
	maxLogs      int
}

// NewApp creates a new App application struct
func NewApp() *App {
	return &App{
		wsServer:     ws.NewServer(),
		clipboardMon: clipboard.NewMonitor(),
		logs:         make([]LogEntry, 0),
		maxLogs:      500,
	}
}

// startup is called when the app starts. The context is saved
// so we can call the runtime methods
func (a *App) startup(ctx context.Context) {
	a.ctx = ctx
}

// shutdown is called when the app is closing
func (a *App) shutdown(ctx context.Context) {
	a.StopServer()
}

// StartServer 启动 WebSocket 服务器
func (a *App) StartServer(address string, port int) error {
	if a.wsServer.IsRunning() {
		return fmt.Errorf("服务器已在运行中")
	}

	// 设置剪贴板数据接收回调
	a.wsServer.SetClipboardCallback(a.onClipboardReceived)

	// 启动 WebSocket 服务器
	err := a.wsServer.Start(address, port, a.onLog)
	if err != nil {
		return err
	}

	// 启动剪贴板监听
	err = a.clipboardMon.Start(a.onClipboardChange)
	if err != nil {
		a.wsServer.Stop()
		return err
	}

	return nil
}

// StopServer 停止 WebSocket 服务器
func (a *App) StopServer() error {
	a.clipboardMon.Stop()
	return a.wsServer.Stop()
}

// GetServerStatus 获取服务器状态
func (a *App) GetServerStatus() map[string]interface{} {
	return map[string]interface{}{
		"isRunning":   a.wsServer.IsRunning(),
		"clientCount": a.wsServer.GetClientCount(),
	}
}

// GetLocalIPs 获取本机 IP 地址列表
func (a *App) GetLocalIPs() ([]string, error) {
	return a.wsServer.GetLocalIPs()
}

// GetLogs 获取日志列表
func (a *App) GetLogs() []LogEntry {
	a.logsMu.RLock()
	defer a.logsMu.RUnlock()

	// 返回副本
	logs := make([]LogEntry, len(a.logs))
	copy(logs, a.logs)
	return logs
}

// ClearLogs 清空日志
func (a *App) ClearLogs() {
	a.logsMu.Lock()
	defer a.logsMu.Unlock()
	a.logs = make([]LogEntry, 0)
	runtime.EventsEmit(a.ctx, "logs:updated", a.logs)
}

// onLog 日志回调
func (a *App) onLog(level, message string) {
	a.logsMu.Lock()
	defer a.logsMu.Unlock()

	entry := LogEntry{
		Level:     level,
		Message:   message,
		Timestamp: getCurrentTimestamp(),
	}

	a.logs = append([]LogEntry{entry}, a.logs...)
	if len(a.logs) > a.maxLogs {
		a.logs = a.logs[:a.maxLogs]
	}

	// 发送事件到前端
	runtime.EventsEmit(a.ctx, "logs:updated", a.logs)
}

// onClipboardChange 剪贴板变化回调（本地剪贴板变化）
func (a *App) onClipboardChange(data clipboard.ClipboardData) {
	var dataType string
	switch data.Type {
	case "text":
		dataType = string(protocol.DataTypeText)
		a.onLog("INFO", fmt.Sprintf("检测到剪贴板文本变化: %d 字符", len(data.Content)))
	case "image":
		dataType = string(protocol.DataTypeImage)
		a.onLog("INFO", "检测到剪贴板图片变化")
	default:
		return
	}

	// 广播给所有客户端
	err := a.wsServer.BroadcastClipboard(dataType, data.Content)
	if err != nil {
		a.onLog("ERROR", fmt.Sprintf("广播剪贴板数据失败: %v", err))
	}
}

// onClipboardReceived 接收到远程剪贴板数据回调
func (a *App) onClipboardReceived(payload protocol.ClipboardPayload) {
	// 将接收到的数据写入本地剪贴板
	data := clipboard.ClipboardData{
		Type:     string(payload.Type),
		MimeType: payload.MimeType,
		Content:  payload.Content,
	}

	err := a.clipboardMon.SetClipboard(data)
	if err != nil {
		a.onLog("ERROR", fmt.Sprintf("写入剪贴板失败: %v", err))
		return
	}

	switch payload.Type {
	case protocol.DataTypeText:
		a.onLog("SUCCESS", fmt.Sprintf("已接收并写入文本数据: %d 字符", len(payload.Content)))
	case protocol.DataTypeImage:
		a.onLog("SUCCESS", "已接收并写入图片数据")
	}
}

// getCurrentTimestamp 获取当前时间戳（毫秒）
func getCurrentTimestamp() int64 {
	return 0 // 将在前端使用 Date.now()
}
