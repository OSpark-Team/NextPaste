package main

import (
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
)

var (
	host = flag.String("host", "0.0.0.0", "监听地址")
	port = flag.Int("port", 8080, "监听端口")
)

func main() {
	// 解析命令行参数
	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, "NextPaste 中继服务器 - WebSocket 房间隔离中继服务\n\n")
		fmt.Fprintf(os.Stderr, "用法:\n")
		fmt.Fprintf(os.Stderr, "  %s [选项]\n\n", os.Args[0])
		fmt.Fprintf(os.Stderr, "选项:\n")
		flag.PrintDefaults()
		fmt.Fprintf(os.Stderr, "\n连接方式:\n")
		fmt.Fprintf(os.Stderr, "  ws://<host>:<port>/ws/<roomID>\n")
		fmt.Fprintf(os.Stderr, "\n示例:\n")
		fmt.Fprintf(os.Stderr, "  %s --host 0.0.0.0 --port 8080\n", os.Args[0])
		fmt.Fprintf(os.Stderr, "  客户端连接: ws://localhost:8080/ws/my-room-123\n\n")
	}
	flag.Parse()

	// 创建中继服务器
	server := NewRelayServer()

	// 设置路由
	http.HandleFunc("/ws/", server.HandleWebSocket)
	http.HandleFunc("/", handleRoot)
	http.HandleFunc("/health", handleHealth)

	// 启动服务器
	addr := fmt.Sprintf("%s:%d", *host, *port)
	log.Printf("🚀 NextPaste 中继服务器启动")
	log.Printf("📡 监听地址: %s", addr)
	log.Printf("🔗 连接格式: ws://%s/ws/<roomID>", addr)
	log.Printf("💡 提示: 使用 Ctrl+C 停止服务器\n")

	// 启动 HTTP 服务器
	go func() {
		if err := http.ListenAndServe(addr, nil); err != nil {
			log.Fatalf("❌ 服务器启动失败: %v", err)
		}
	}()

	// 等待中断信号
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)
	<-sigChan

	log.Println("\n👋 正在关闭服务器...")
	server.Shutdown()
	log.Println("✅ 服务器已关闭")
}

// handleRoot 处理根路径
func handleRoot(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}

	html := `<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>NextPaste 中继服务器</title>
    <style>
        body { font-family: Arial, sans-serif; max-width: 800px; margin: 50px auto; padding: 20px; }
        h1 { color: #333; }
        code { background: #f4f4f4; padding: 2px 6px; border-radius: 3px; }
        .info { background: #e7f3ff; padding: 15px; border-left: 4px solid #2196F3; margin: 20px 0; }
    </style>
</head>
<body>
    <h1>🚀 NextPaste 中继服务器</h1>
    <p>WebSocket 房间隔离中继服务正在运行</p>
    
    <div class="info">
        <h3>连接方式</h3>
        <p>WebSocket URL: <code>ws://` + r.Host + `/ws/&lt;roomID&gt;</code></p>
        <p>示例: <code>ws://` + r.Host + `/ws/my-room-123</code></p>
    </div>
    
    <div class="info">
        <h3>功能说明</h3>
        <ul>
            <li>支持无限数量的房间</li>
            <li>同一房间内的客户端可以互相共享剪贴板</li>
            <li>不同房间之间完全隔离</li>
            <li>兼容 NextPaste 协议（HANDSHAKE、CLIPBOARD_SYNC、HEARTBEAT）</li>
        </ul>
    </div>
    
    <p><a href="/health">健康检查</a></p>
</body>
</html>`

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Write([]byte(html))
}

// handleHealth 健康检查
func handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.Write([]byte(`{"status":"ok","service":"nextpaste-relay"}`))
}

