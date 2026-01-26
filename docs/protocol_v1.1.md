# **NextPaste 跨设备剪切板共享协议 (V1.1)**

## **1\. 概述**

本协议基于 WebSocket，旨在实现 Windows/Mac/Linux 服务端与 HarmonyOS Next 客户端之间的剪切板数据（文本、图片、文件）实时同步。V1.1 版本在保留 V1.0 兼容性的基础上，新增了对大文件分片传输的支持。

## **2\. 通信基础**

### **2.1 数据格式**

所有通信数据帧均为标准 JSON 字符串。对于大文件实体数据，建议在 FILE\_TRANSFER\_CHUNK 动作中进行 Base64 编码，或在未来版本中升级为二进制帧。

### **2.2 通用消息结构**

{  
  "action": "ACTION\_ENUM",  
  "id": "UUID-v4",  
  "timestamp": 1700000000000,  
  "senderId": "Device-Unique-ID",  
  "data": { ... }  
}

## **3\. 动作定义 (Actions)**

### **3.1 HANDSHAKE (握手)**

连接建立后由客户端发起。V1.1 引入了能力协商机制。

* **data 结构**:

{  
  "deviceName": "My HarmonyOS Device",  
  "platform": "HarmonyOS",  
  "version": "1.1",  
  "capabilities": \["TEXT", "IMAGE", "FILE\_CHUNKED"\] // V1.1 新增：可选，用于声明支持的功能  
}

### **3.2 HEARTBEAT (心跳)**

用于维持 WebSocket 长连接，防止被系统防火墙或运营商断开。

* **data 结构**: null 或 {"uptime": 12345}

### **3.3 CLIPBOARD\_SYNC (剪切板同步)**

核心动作，用于广播剪切板内容变化。

#### **A. 文本 (Text)**

{  
  "type": "text",  
  "mimeType": "text/plain",  
  "content": "复制的文字内容"  
}

#### **B. 图片 (Image)**

{  
  "type": "image",  
  "mimeType": "image/png",  
  "content": "iVBORw0KGgoAAAANSUhEUgAAAAE...", // Base64 编码  
  "preview": "Base64缩略图(可选)"  
}

#### **C. 文件预告 (File Placeholder \- V1.1 新增)**

当检测到文件复制时发送，作为文件传输序列的引导消息。

{  
  "type": "file",  
  "mimeType": "application/octet-stream",  
  "content": "NextPaste\_File\_Transfer\_Pending",  
  "transferId": "unique-transfer-uuid" // 关联后续的文件流  
}

## **4\. 文件分片传输协议 (V1.1 新增)**

为避免大文件阻塞 WebSocket 队列，必须采用分片传输。

### **4.1 FILE\_TRANSFER\_START (初始化)**

告知接收端准备接收文件元数据。

* **data 结构**:

{  
  "transferId": "unique-transfer-uuid",  
  "fileName": "document.pdf",  
  "fileSize": 15728640,  
  "totalChunks": 240,  
  "fileHash": "sha256-or-md5-hash",  
  "mimeType": "application/pdf"  
}

### **4.2 FILE\_TRANSFER\_CHUNK (分片载荷)**

持续发送文件切片。

* **data 结构**:

{  
  "transferId": "unique-transfer-uuid",  
  "chunkIndex": 0,             // 从 0 开始  
  "chunkSize": 65536,          // 建议每片 64KB  
  "content": "BASE64\_DATA...", // 分片内容的 Base64  
  "isLast": false  
}

### **4.3 FILE\_TRANSFER\_STATUS (状态控制)**

用于传输中途的取消、暂停或成功确认。

* **data 结构**:

{  
  "transferId": "unique-transfer-uuid",  
  "status": "SUCCESS | CANCEL | ERROR",  
  "message": "Optional error info"  
}

## **5\. 业务逻辑约束**

### **5.1 回环防止 (Loopback Prevention)**

* **ID 校验**: 接收端必须记录自身的 Device-Unique-ID。  
* **丢弃逻辑**: 若收到的消息 senderId 与自身相同，**必须**丢弃该消息，严禁写入本地剪切板，防止产生死循环。

### **5.2 方向控制 (Direction Control)**

* **仅发送模式**: 监听到本地剪切板变化时发送消息，但不处理接收到的 CLIPBOARD\_SYNC。  
* **仅接收模式**: 处理接收到的消息并写入剪切板，但不监听本地剪切板变化。

### **5.3 分片传输细节 (Chunking Strategy)**

* **并发控制**: 同一时间只允许进行一个 transferId 的文件传输。  
* **流控**: 发送方在发送高频分片时，应观察 WebSocket 缓冲区状态，避免阻塞 HEARTBEAT 消息。  
* **临时存储**: 接收端应将分片写入临时文件目录（HarmonyOS 的 cache 目录），校验完整性后再移动到正式目录或写入剪切板。

### **5.4 兼容性说明**

* **增量更新**: V1.1 客户端能通过 capabilities 识别对方是否支持文件传输。  
* **向下兼容**: 若 V1.1 客户端连接到 V1.0 服务端，由于服务端不发送 FILE\_TRANSFER\_\* 动作，客户端将仅退化为文本和图片同步模式。

## **6\. 错误处理**

* **超时**: 若 FILE\_TRANSFER\_START 后 30 秒内未收到后续分片，接收端应自动销毁该传输任务并清理临时文件。  
* **校验失败**: 若最终合并的文件 fileHash 与起始消息不符，应提示用户并标记为错误。