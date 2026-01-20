# **跨设备剪切板共享协议 (V1.0)**

## **1\. 概述**

本协议基于 WebSocket，用于 Windows 服务端与 HarmonyOS 客户端之间的剪切板数据同步。

## **2\. 通信格式**

所有数据帧均为 JSON 字符串。

### **2.1 消息结构**

{  
  "action": "ACTION\_ENUM",  
  "id": "UUID-v4",  
  "timestamp": 1700000000000,  
  "senderId": "Device-Unique-ID",  
  "data": { ... }  
}

## **3\. 动作定义 (Actions)**

### **3.1 HANDSHAKE (握手)**

连接建立后由客户端发送。

* **data**:  
  {  
    "deviceName": "My HarmonyOS Device",  
    "platform": "HarmonyOS"  
  }

### **3.2 CLIPBOARD\_SYNC (同步)**

传输剪切板内容。

**文本 (Text)**

{  
  "type": "text",  
  "mimeType": "text/plain",  
  "content": "复制的文字内容"  
}

**图片 (Image)**

{  
  "type": "image",  
  "mimeType": "image/png",  
  "content": "iVBORw0KGgoAAAANSUhEUgAAAAE...", // Base64 编码  
  "preview": "Base64缩略图(可选)"  
}

### **3.3 HEARTBEAT (心跳)**

* **data**: null 或 {"uptime": 12345}

## **4\. 逻辑约束**

1. **回环丢弃 (Loopback Drop)**:  
   * 接收端必须比较 senderId。如果 senderId 与自身 ID 相同，必须丢弃消息，**严禁**写入剪切板。  
2. **方向控制 (Direction Control)**:  
   * 客户端应维护 canSend 和 canReceive 状态。  
   * canSend \= false: 监听到系统剪切板变化时不发送 WS 消息。  
   * canReceive \= false: 收到 WS 消息时不写入系统剪切板。  
3. **图片大小限制**:  
   * 建议 Base64 后的字符串大小不超过 5MB (WebSocket 帧限制)。大图建议压缩后再传。