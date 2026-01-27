# **NextPaste 通信协议演进文档 (V1.0 \-\> V1.1)**

## **1\. 背景与目标**

**NextPaste V1.0** 采用了纯文本 JSON 协议，不仅实现了快速开发（MVP），也保证了良好的调试可读性。然而，随着图片和文件同步需求的增加，V1.0 暴露出了性能瓶颈。

**NextPaste V1.1** 引入了 **NPBP (NextPaste Binary Protocol)**，旨在通过二进制帧传输解决 Base64 带来的体积膨胀和编解码开销，同时保留对 V1.0 旧版客户端的兼容性。

## **2\. V1.0 协议回顾 (Legacy)**

V1.0 基于 WebSocket **Text Frame**。所有数据（包括图片）都被封装在一个大的 JSON 对象中。

### **2.1 V1.0 报文结构**

{  
  "action": "CLIPBOARD\_SYNC",  
  "id": "uuid-v4",  
  "timestamp": 1700000000,  
  "senderId": "device-id-123",  
  "data": {  
    "type": "image", // 或 "text"  
    "mimeType": "image/png",  
    "content": "iVBORw0KGgoAAAANSUhEUgAA..." // Base64 String  
  }  
}

### **2.2 V1.0 的局限性**

1. **体积膨胀**：Base64 编码会导致二进制数据体积增加约 **33%**。传输 10MB 图片实际需要传输 13.3MB。  
2. **内存与CPU开销**：发送端需要 Binary \-\> Base64 String，接收端需要 Base64 String \-\> Binary。在移动设备处理大图时，容易引发 OOM (Out Of Memory) 或 UI 卡顿。  
3. **无法分片**：JSON 是整体解析的，无法像流一样边收边写。

## **3\. V1.1 协议详解 (Binary Evolution)**

V1.1 基于 WebSocket **Binary Frame**。我们参考了 TCP/IP 头部设计，定义了固定长度的包头和变长载荷。

### **3.1 V1.1 报文结构 (NPBP)**

由 **33字节固定包头** \+ **载荷 (Payload)** 组成。

 0                   1                   2                   3  
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1  
\+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+  
|  Magic (NP)   |Ver|Type |  Flags  |   Reserved    | MsgID ... |  
\+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+  
| ... MsgID     |              Sequence Number                  |  
\+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+  
|                       Sender UUID (128 bit)                   |  
|                                                               |  
\+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+  
|                        Payload Length                         |  
\+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+  
|                        Payload Data...                        |  
\+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

### **3.2 关键字段定义**

* **Magic (0x4E50)**: 协议识别符 (ASCII 'NP')。  
* **Type (Message Type)**:  
  * 0x1: **HANDSHAKE** (握手)  
  * 0x2: **TEXT** (文本)  
  * 0x3: **IMAGE** (图片)  
  * 0x4: **FILE** (文件)  
* **Flags**:  
  * Bit 0 (MF): **More Fragments**. 1 表示后续还有分片，0 表示这是最后一个分片。  
  * Bit 1 (HAS\_META): 1 表示 Payload 头部包含 JSON 元数据（通常在分片的第一包）。

### **3.3 V1.1 载荷封装详解 (Payload Examples)**

V1.1 针对不同 Type 采用不同的 Payload 封装策略。**所有多字节数字均为大端序 (Big-Endian)**。

#### **A. 握手包 (Type 0x1)**

握手包通常不分片 (Flags: MF=0)。Payload 为纯 JSON。

* **Header**: Type=0x1, Flags=0  
* **Payload**:  
  {"name": "Mate60 Pro", "os": "HarmonyOS 5.0", "ver": 11}

#### **B. 文本同步 (Type 0x2)**

文本包通常不分片。Payload 为 UTF-8 字节流。

* **Header**: Type=0x2, Flags=0  
* **Payload**:  
  Hello NextPaste\! (UTF-8 Bytes)

#### **C. 图片同步 (Type 0x3) \- 混合元数据**

图片传输需要知道格式（png/jpg）。我们在 **Sequence 0** 中携带元数据，后续包仅携带数据。

* **分片 1 (Start Frame)**:  
  * **Header**: Type=0x3, Seq=0, Flags=MF=1 | HAS\_META=1  
  * **Payload 结构**: \[2字节 MetaLen\] \+ \[Meta JSON\] \+ \[Image Binary Part 1\]  
  * **Meta JSON**: {"mime": "image/png", "width": 1920, "height": 1080}  
* **分片 N (End Frame)**:  
  * **Header**: Type=0x3, Seq=N, Flags=MF=0  
  * **Payload 结构**: \[Image Binary Part N\]

#### **D. 文件传输 (Type 0x4) \- 核心新增**

文件传输与图片类似，但元数据更丰富（文件名、大小），且必须严格分片。

**场景**：发送一个 report.pdf (10MB)。

* **Step 1: 首帧 (Sequence 0\)**  
  * **Header**:  
    * Type: 0x4 (FILE)  
    * Flags: MF=1 | HAS\_META=1 (表示未结束，且包含元数据)  
    * MsgID: 1001  
  * **Payload**:  
    1. **Meta Length (2 Bytes)**: e.g., 0x00 0x35 (53 bytes)  
    2. **Meta JSON**: {"name": "report.pdf", "size": 10485760, "hash": "sha256..."}  
    3. **Binary Data**: 文件的头 60KB 数据。  
* **Step 2: 中间帧 (Sequence 1...N-1)**  
  * **Header**:  
    * Type: 0x4  
    * Flags: MF=1 (无 HAS\_META)  
    * MsgID: 1001  
  * **Payload**: 纯文件二进制数据 (64KB chunks)。  
* **Step 3: 尾帧 (Sequence N)**  
  * **Header**:  
    * Type: 0x4  
    * Flags: MF=0 (传输结束)  
    * MsgID: 1001  
  * **Payload**: 剩余的文件数据。

## **4\. 兼容性设计：智能握手策略**

为了让 V1.1 的服务端（PC）能够同时服务 V1.0（旧版鸿蒙）和 V1.1（新版鸿蒙）客户端，我们采用 **协议嗅探 (Protocol Sniffing)** 机制。

### **4.1 原理**

WebSocket 规范本身区分消息类型：

* Opcode 0x1: **Text Frame** (文本帧)  
* Opcode 0x2: **Binary Frame** (二进制帧)

**V1.0 客户端只发送 Text Frame，V1.1 客户端主要发送 Binary Frame。**

### **4.2 握手流程 (Handshake Flow)**

服务端在建立连接后，不主动发送消息，而是**等待客户端的第一条消息**（握手包）。

sequenceDiagram  
    participant C1 as V1.0 Client (Old)  
    participant C2 as V1.1 Client (New)  
    participant S as Server (PC)

    Note over S: WebSocket Connected\<br/\>Wait for first message...

    alt V1.0 Legacy Connection  
        C1-\>\>S: Send Text Frame (JSON Handshake)  
        S-\>\>S: Detect Text Frame?  
        S-\>\>S: Mark Session as \[V1.0 Mode\]  
        S--\>\>C1: Reply Text Frame (JSON)  
        Note right of S: Subsequent comms use JSON  
    else V1.1 Binary Connection  
        C2-\>\>S: Send Binary Frame (Magic 0x4E50...)  
        S-\>\>S: Detect Binary Frame?  
        S-\>\>S: Check Magic Header  
        S-\>\>S: Mark Session as \[V1.1 Mode\]  
        S--\>\>C2: Reply Binary Frame (Ack)  
        Note right of S: Subsequent comms use Binary  
    end

### **4.3 服务端处理逻辑 (伪代码)**

在 Go (Wails) 后端中，我们可以这样处理：

func (s \*Server) HandleWebSocket(conn \*websocket.Conn) {  
    // 1\. 读取第一条消息  
    messageType, p, err := conn.ReadMessage()  
    if err \!= nil { return }

    client := \&Client{conn: conn}

    // 2\. 协议判断  
    if messageType \== websocket.TextMessage {  
        // \=== V1.0 兼容模式 \===  
        client.ProtocolVersion \= 1  
        handleJsonHandshake(client, p)  
          
    } else if messageType \== websocket.BinaryMessage {  
        // \=== V1.1 二进制模式 \===  
        if len(p) \>= 32 && p\[0\] \== 0x4E && p\[1\] \== 0x50 {  
            client.ProtocolVersion \= 11 // 1.1  
            handleBinaryHandshake(client, p)  
        }  
    }

    // 3\. 进入消息循环  
    for {  
        // 根据 client.ProtocolVersion 决定发送/接收逻辑  
        // 如果是 V1.0，发送时自动转 JSON \+ Base64  
        // 如果是 V1.1，发送时封装 Binary Header  
    }  
}

## **5\. 总结**

| 特性 | V1.0 (Legacy) | V1.1 (Current) | 优势 |
| :---- | :---- | :---- | :---- |
| **传输层** | WebSocket Text Frame | WebSocket Binary Frame | 符合数据类型本质 |
| **数据格式** | JSON String | Custom Binary Protocol | 解析更快 |
| **图片编码** | Base64 | Raw Bytes | **体积减少 33%，CPU 占用低** |
| **大文件** | 不支持 (易 OOM) | 支持 (分片 Flag MF) | 支持 GB 级文件传输 |
| **兼容性** | \- | 自动识别 V1.0 客户端降级 | 平滑过渡 |

