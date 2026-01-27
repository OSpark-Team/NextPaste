package main

import (
	"context"
	"fmt"
	"sync"

	"server/internal/clipboard"
	ws "server/internal/websocket"

	"github.com/wailsapp/wails/v2/pkg/runtime"
)

// LogEntry 日志条目
type LogEntry struct {
	Level     string `json:"level"`
	Message   string `json:"message"`
	Timestamp int64  `json:"timestamp"`
}

// App struct（V1.1 二进制协议版本）
type App struct {
	ctx          context.Context
	wsServer     *ws.Server
	wsClient     *ws.WSClient
	clipboardMon *clipboard.Monitor
	logs         []LogEntry
	logsMu       sync.RWMutex
	maxLogs      int
	mode         string // "server" 或 "client"
}

// NewApp creates a new App application struct
func NewApp() *App {
	return &App{
		wsServer:     ws.NewServer(),
		wsClient:     ws.NewWSClient("NextPaste Desktop", "Windows"),
		clipboardMon: clipboard.NewMonitor(),
		logs:         make([]LogEntry, 0),
		maxLogs:      500,
		mode:         "server", // 默认为服务器模式
	}
}

// ============================================
// 窗口控制方法
// ============================================

// ShowWindow 显示主窗口
func (a *App) ShowWindow() {
	runtime.WindowShow(a.ctx)
}

// HideWindow 隐藏主窗口
func (a *App) HideWindow() {
	runtime.WindowHide(a.ctx)
}

// Quit 完全退出应用
func (a *App) Quit() {
	runtime.Quit(a.ctx)
}

// startup is called when the app starts. The context is saved
// so we can call the runtime methods
func (a *App) startup(ctx context.Context) {
	a.ctx = ctx
}

// shutdown is called when the app is closing
func (a *App) shutdown(ctx context.Context) {
	a.StopServer()
	a.DisconnectClient()
}

// StartServer 启动 WebSocket 服务器
func (a *App) StartServer(address string, port int) error {
	if a.wsServer.IsRunning() {
		return fmt.Errorf("服务器已在运行中")
	}

	// 设置剪贴板数据接收回调（V1.1 二进制协议）
	a.wsServer.SetClipboardCallback(a.onClipboardReceivedBinary)

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
	if a.mode == "server" {
		a.clipboardMon.Stop()
	}
	return a.wsServer.Stop()
}

// ConnectClient 连接到远程 WebSocket 服务器（客户端模式）
func (a *App) ConnectClient(url string) error {
	if a.wsClient.IsConnected() {
		return fmt.Errorf("客户端已连接")
	}

	a.mode = "client"

	// 设置剪贴板数据接收回调（V1.1 二进制协议）
	a.wsClient.SetClipboardCallback(a.onClipboardReceivedBinary)

	// 设置连接成功回调 - 只有连接成功后才启动剪贴板监听
	a.wsClient.SetOnConnected(func() {
		a.onLog("INFO", "WebSocket 连接成功，启动剪贴板监听...")
		err := a.clipboardMon.Start(a.onClipboardChangeClient)
		if err != nil {
			a.onLog("ERROR", fmt.Sprintf("启动剪贴板监听失败: %v", err))
		} else {
			a.onLog("SUCCESS", "剪贴板监听已启动")
		}
	})

	// 连接到服务器（异步，会自动重连）
	err := a.wsClient.Connect(url, a.onLog)
	if err != nil {
		return err
	}

	return nil
}

// DisconnectClient 断开客户端连接
func (a *App) DisconnectClient() error {
	a.clipboardMon.Stop()
	return a.wsClient.Disconnect()
}

// GetClientStatus 获取客户端状态
func (a *App) GetClientStatus() map[string]any {
	return map[string]any{
		"isConnected": a.wsClient.IsConnected(),
	}
}

// GetServerStatus 获取服务器状态
func (a *App) GetServerStatus() map[string]any {
	return map[string]any{
		"isRunning":   a.wsServer.IsRunning(),
		"clientCount": a.wsServer.GetClientCount(),
	}
}

// GetMode 获取当前模式
func (a *App) GetMode() string {
	return a.mode
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
		Timestamp: 0,
	}

	a.logs = append([]LogEntry{entry}, a.logs...)
	if len(a.logs) > a.maxLogs {
		a.logs = a.logs[:a.maxLogs]
	}

	// 发送事件到前端
	runtime.EventsEmit(a.ctx, "logs:updated", a.logs)
}

// onClipboardChange 剪贴板变化回调（服务器模式，V1.1 二进制协议）
func (a *App) onClipboardChange(data clipboard.ClipboardData) {
	switch data.Type {
	case "text":
		a.onLog("INFO", fmt.Sprintf("检测到剪贴板文本变化: %d 字符", len(data.Content)))
	case "image":
		sizeMB := float64(len(data.Content)) / 1024 / 1024
		a.onLog("INFO", fmt.Sprintf("检测到剪贴板图片变化: %.2f MB", sizeMB))
	default:
		return
	}

	// 广播给所有客户端（V1.1 二进制协议）
	err := a.wsServer.BroadcastClipboardBinary(data.Type, data.Content)
	if err != nil {
		a.onLog("ERROR", fmt.Sprintf("广播剪贴板数据失败: %v", err))
	}
}

// onClipboardChangeClient 剪贴板变化回调（客户端模式，V1.1 二进制协议）
func (a *App) onClipboardChangeClient(data clipboard.ClipboardData) {
	switch data.Type {
	case "text":
		a.onLog("INFO", fmt.Sprintf("检测到剪贴板文本变化: %d 字符", len(data.Content)))
	case "image":
		sizeMB := float64(len(data.Content)) / 1024 / 1024
		a.onLog("INFO", fmt.Sprintf("检测到剪贴板图片变化: %.2f MB", sizeMB))
	default:
		return
	}

	// 发送给服务器（V1.1 二进制协议）
	err := a.wsClient.SendClipboardBinary(data.Type, data.Content)
	if err != nil {
		a.onLog("ERROR", fmt.Sprintf("发送剪贴板数据失败: %v", err))
	}
}

// onClipboardReceivedBinary 接收到远程剪贴板数据回调（V1.1 二进制协议）
// dataType: "text" 或 "image"
// content: 原始二进制数据
func (a *App) onClipboardReceivedBinary(dataType string, content []byte) {
	// 将接收到的数据写入本地剪贴板
	data := clipboard.ClipboardData{
		Type:    dataType,
		Content: content,
	}

	switch dataType {
	case "text":
		data.MimeType = "text/plain"
	case "image":
		data.MimeType = "image/png"
	}

	err := a.clipboardMon.SetClipboard(data)
	if err != nil {
		a.onLog("ERROR", fmt.Sprintf("写入剪贴板失败: %v", err))
		return
	}

	switch dataType {
	case "text":
		a.onLog("SUCCESS", fmt.Sprintf("已接收并写入文本数据: %d 字符", len(content)))
	case "image":
		sizeMB := float64(len(content)) / 1024 / 1024
		a.onLog("SUCCESS", fmt.Sprintf("已接收并写入图片数据: %.2f MB", sizeMB))
	}
}
