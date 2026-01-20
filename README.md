# NextPaste

**NextPaste** 是一款旨在打破设备壁垒的跨设备剪切板同步工具。通过 WebSocket 协议，实现 HarmonyOS Next 设备与 Windows/Mac/Linux 设备之间文本、图片的实时无缝流转。

---

## 项目结构

本项目采用单仓风格管理，客户端与服务端代码共存：

```text
NextPaste/
├── entry/                # HarmonyOS 客户端 (ArkTS)
├── server/               # Windows 服务端 (Wails: Go + Vue3)
│   ├── frontend/         # 服务端管理界面 (Vue3 + TS)
│   └── main.go           # Wails 入口及 Go 后端逻辑
├── docs/                 # 项目文档及通信协议
└── README.md

```

---

## 功能特性

### HarmonyOS 客户端

* **全自动同步**：支持双向、仅发送、仅接收三种工作模式。
* **持久化后台**：利用长时任务确保息屏状态下依然可以实时接收同步。
* **响应式设计**：完美适配手机、平板及 2in1 设备。
* **实时监控**：内置详细的运行日志过滤系统，方便排查连接问题。

### PC 服务端

* **零配置启动**：自动检测本地所有 IP 地址，生成连接二维码或地址。
* **协议完整实现**：支持握手校验、心跳保持（Heartbeat）及数据广播。
* **状态看板**：实时显示当前连接的客户端数量及同步记录。

---

## 🛠 技术架构

### 架构模式

* **通信协议**：基于 WebSocket 的自定义 JSON 协议，包含 `HANDSHAKE`、`CLIPBOARD_SYNC` 和 `HEARTBEAT` 消息。
* **客户端**：严格遵循 **MVVM** 架构，通过服务分层（剪切板服务、网络服务、后台服务）解耦业务逻辑。
* **服务端**：利用 **Wails** 的桥接能力，在 Go 后端调用 Windows 原生 API 监听剪切板，通过 Vue3 构建桌面管理界面。

### 核心技术栈

* **Client**: HarmonyOS SDK, ArkUI, @ohos.net.webSocket, PersistentStorage.
* **Server**: Go 1.23, Wails v2, gorilla/websocket, golang.design/x/clipboard.

---

## 已知局限性

由于不同操作系统及应用对剪切板的处理逻辑差异，目前存在以下已知问题：

| 场景 | 状态 | 备注 |
| --- | --- | --- |
| **文本同步** | ✅ 正常 | 跨设备文本传输稳定 |
| **QQ/系统截图** | ✅ 正常 | 能够识别标准 PNG/DIB 格式并触发监听 |
| **微信截图** | ❌ 无法监听 | **微信在写入剪切板时使用了私有或特定的注册格式**，常规跨平台库可能无法捕获其变更事件。 |
| **大图传输** | ⚠️ 延迟 | 受限于局域网带宽，高分辨率图片（Base64 编码）可能存在一定的传输延迟。 |

---

## 快速开始

### 服务端部署

1. 进入 `server` 目录：`cd server`
2. 安装环境依赖（需 Go 1.23+, Node.js 16+, Wails CLI）。
3. 编译运行：
```bash
wails dev  # 开发模式
wails build # 构建正式版

```


4. 在界面点击 **“启动服务”**，记下显示的 `ws://` 地址。

### 客户端部署 (HarmonyOS)

1. 使用 DevEco Studio 打开项目根目录。
2. 将设备连接至同一局域网。
3. 在应用主页输入服务端的 WebSocket 地址。
4. 授予 **“读取剪切板”** 权限并点击 **“开始同步”**。

---

## 权限及安全说明

### 权限申请

* `ohos.permission.INTERNET`: 用于 WebSocket 通信。
* `ohos.permission.KEEP_BACKGROUND_RUNNING`: 用于申请后台长时任务。
* `ohos.permission.READ_PASTEBOARD`: 核心权限，用于读取本地剪切板。

### 网络安全

* 建议在受信任的局域网环境内使用。
* 若需通过公网同步，请配置防火墙并建议配合 **WSS (WebSocket over TLS)** 使用。

---

## 贡献与许可

* **许可证**：本项目基于 [MIT License](https://www.google.com/search?q=LICENSE) 开源，仅供学习和研究使用。
* **贡献**：欢迎提交 Issue 或 Pull Request 来改进微信截图兼容性或其他功能。

---

**NextPaste** —— 让你的剪切板触手可及。

---