import { webSocket } from '@kit.NetworkKit';
import {
  BinaryProtocolManager,
  BinaryMessage,
  MessageType,
  MessageFlags,
  BinaryProtocolError,
  BinaryErrorCode,
  TransferMeta
} from '../protocol/BinaryProtocol';

/**
 * WebSocket 连接状态回调
 */
export type ConnectionStatusCallback = (connected: boolean) => void;

/**
 * 消息接收回调（V1.1 二进制协议）
 */
export type MessageReceivedCallback = (message: BinaryMessage) => void;

/**
 * 错误回调
 */
export type ErrorCallback = (error: string) => void;

/**
 * WebSocket 连接管理器（V1.1 二进制协议版本）
 * 负责 WebSocket 连接、心跳、消息发送和接收
 * 使用 NPBP (NextPaste Binary Protocol) 二进制帧传输
 */
export class WebSocketManager {
  private ws: webSocket.WebSocket | null = null;
  private serverUrl: string = '';
  private isConnected: boolean = false;
  private heartbeatTimer: number = -1;
  private heartbeatInterval: number = 15000; // 心跳间隔 15 秒
  private reconnectTimer: number = -1;
  private reconnectInterval: number = 3000; // 重连间隔 3 秒
  private shouldReconnect: boolean = false;
  // 消息ID计数器，用于生成唯一的消息ID
  private messageIdCounter: number = Math.floor(Math.random() * 0xFFFFFFFF);

  private connectionStatusCallback: ConnectionStatusCallback | null = null;
  private messageReceivedCallback: MessageReceivedCallback | null = null;
  private errorCallback: ErrorCallback | null = null;

  // 分片重组状态
  private pendingMsgId: number = 0;
  private pendingBuffer: Uint8Array | null = null;
  private pendingMeta: TransferMeta | null = null;

  /**
   * 设置连接状态回调
   * @param callback 回调函数
   */
  public setConnectionStatusCallback(callback: ConnectionStatusCallback): void {
    this.connectionStatusCallback = callback;
  }

  /**
   * 设置消息接收回调
   * @param callback 回调函数
   */
  public setMessageReceivedCallback(callback: MessageReceivedCallback): void {
    this.messageReceivedCallback = callback;
  }

  /**
   * 设置错误回调
   * @param callback 回调函数
   */
  public setErrorCallback(callback: ErrorCallback): void {
    this.errorCallback = callback;
  }

  /**
   * 连接到 WebSocket 服务器
   * @param url 服务器地址
   */
  public async connect(url: string): Promise<boolean> {
    if (this.isConnected) {
      return true;
    }

    this.serverUrl = url;
    this.shouldReconnect = true;

    try {
      this.ws = webSocket.createWebSocket();

      // 设置事件监听
      this.ws.on('open', () => {
        this.onOpen();
      });

      this.ws.on('message', (err, value) => {
        this.onMessage(err, value);
      });

      this.ws.on('close', (err, value) => {
        this.onClose(err, value);
      });

      this.ws.on('error', (err) => {
        this.onError(err);
      });

      // 连接服务器
      await this.ws.connect(url);

      return true;
    } catch (error) {
      console.error('WebSocket 连接失败:', JSON.stringify(error));
      if (this.errorCallback) {
        this.errorCallback('连接失败: ' + JSON.stringify(error));
      }
      return false;
    }
  }

  /**
   * 断开连接
   */
  public async disconnect(): Promise<void> {
    this.shouldReconnect = false;
    this.stopHeartbeat();
    this.stopReconnect();

    if (this.ws && this.isConnected) {
      try {
        await this.ws.close();
      } catch (error) {
        console.error('关闭 WebSocket 连接失败:', JSON.stringify(error));
      }
    }

    this.ws = null;
    this.isConnected = false;

    if (this.connectionStatusCallback) {
      this.connectionStatusCallback(false);
    }
  }

  /**
   * 发送文本消息（V1.1 二进制协议）
   * @param text 文本内容
   */
  public async sendText(text: string): Promise<boolean> {
    if (!this.isConnected || !this.ws) {
      return false;
    }

    try {
      // 使用二进制协议封装文本消息
      const frame = BinaryProtocolManager.createText(text);
      await this.ws.send(frame);
      return true;
    } catch (error) {
      console.error('发送文本消息失败:', JSON.stringify(error));
      return false;
    }
  }

  /**
   * 发送图片消息（V1.1 二进制协议 - 直接传输二进制数据）
   * @param pngData PNG 格式的图片二进制数据
   */
  public async sendImage(pngData: ArrayBuffer): Promise<boolean> {
    if (!this.isConnected || !this.ws) {
      return false;
    }

    try {
      // 获取唯一消息ID
      const msgId = this.getNextMessageId();

      // 构建图片元数据
      const meta: TransferMeta = {
        mime: 'image/png',
        size: pngData.byteLength
      };

      // 将 ArrayBuffer 转换为 Uint8Array
      const imageBytes = new Uint8Array(pngData);
      
      // 分片大小 64KB
      const CHUNK_SIZE = 64 * 1024;
      let offset = 0;
      const totalLen = imageBytes.byteLength;
      
      // 1. 发送首帧（预留空间给元数据，使用最大32KB数据以确保首帧不过大）
      const firstChunkSize = Math.min(32 * 1024, totalLen);
      const firstChunkData = imageBytes.subarray(0, firstChunkSize);
      offset += firstChunkSize;
      
      const startFrame = BinaryProtocolManager.createStartFrame(
        MessageType.IMAGE,
        msgId,
        meta,
        firstChunkData
      );
      
      // 注意：createStartFrame 默认包含 MF 和 HAS_META 标志
      // 如果图片很小，一次就能发完（offset >= totalLen），我们需要手动清除 MF 标志
      if (offset >= totalLen) {
          const view = new Uint8Array(startFrame);
          // Flags 在偏移 3
          view[3] &= ~MessageFlags.MF;
      }
      
      await this.ws.send(startFrame);
      
      // 2. 循环发送后续分片
      let seq = 1;
      while (offset < totalLen) {
          const end = Math.min(offset + CHUNK_SIZE, totalLen);
          const chunkData = imageBytes.subarray(offset, end);
          const isLast = end >= totalLen;
          
          const chunkFrame = BinaryProtocolManager.createChunkFrame(
              MessageType.IMAGE,
              msgId,
              seq,
              chunkData,
              isLast
          );
          
          await this.ws.send(chunkFrame);
          offset = end;
          seq++;
      }

      return true;
    } catch (error) {
      console.error('发送图片消息失败:', JSON.stringify(error));
      return false;
    }
  }

  /**
   * 获取下一个消息ID
   */
  private getNextMessageId(): number {
    this.messageIdCounter = (this.messageIdCounter + 1) % 0xFFFFFFFF;
    return this.messageIdCounter;
  }

  /**
   * 连接打开事件处理
   */
  private onOpen(): void {
    console.info('WebSocket 连接已打开');
    this.isConnected = true;

    if (this.connectionStatusCallback) {
      this.connectionStatusCallback(true);
    }

    // 发送握手消息（V1.1 二进制协议）
    this.sendHandshake();

    // 启动心跳
    this.startHeartbeat();
  }

  /**
   * 消息接收事件处理（V1.1 二进制协议）
   * @param err 错误信息
   * @param value 消息内容
   */
  private onMessage(err: Error, value: string | ArrayBuffer): void {
    if (err) {
      console.error('接收消息错误:', JSON.stringify(err));
      return;
    }

    try {
      // V1.1 二进制协议：仅处理二进制帧
      if (!(value instanceof ArrayBuffer)) {
        // 收到文本帧，表示可能是旧版协议或不兼容的消息
        console.warn('收到非二进制消息，不兼容的协议版本');
        return;
      }

      // 使用二进制协议解析消息
      const message = BinaryProtocolManager.parse(value);

      // 分片重组逻辑
      if (message.flags & MessageFlags.HAS_META) {
          // 首帧
          this.pendingMsgId = message.msgId;
          this.pendingMeta = message.meta || null;
          
          // 如果解析器已经提取了 binaryData (剥离元数据后)，使用它；否则使用 payload
          // 注意：需要确认 BinaryMessage 定义。假设 parse 方法处理了元数据提取。
          let data = message.binaryData ? new Uint8Array(message.binaryData) : new Uint8Array(message.payload);
          this.pendingBuffer = data;
      } else if (this.pendingBuffer && message.msgId === this.pendingMsgId) {
          // 后续分片
          const newChunk = new Uint8Array(message.payload);
          const newData = new Uint8Array(this.pendingBuffer.length + newChunk.length);
          newData.set(this.pendingBuffer);
          newData.set(newChunk, this.pendingBuffer.length);
          this.pendingBuffer = newData;
      } else if (message.flags & MessageFlags.MF) {
          // 孤立分片或ID不匹配，忽略
          return;
      }

      // 检查是否有后续
      if (message.flags & MessageFlags.MF) {
          return;
      }

      // 如果经历了重组，更新消息内容
      if (this.pendingBuffer) {
          // 修复：直接赋值 Uint8Array，不要转换为 ArrayBuffer（因为接口定义是 Uint8Array）
          message.payload = this.pendingBuffer;
          // 修复：强制更新 binaryData，不仅仅是当它存在时（因为最后一片可能没有 binaryData）
          message.binaryData = this.pendingBuffer;
          
          if (this.pendingMeta) {
             // 修复：类型断言，解决 Structural typing 报错
             message.meta = this.pendingMeta as Record<string, Object>;
          }
          // Reset
          this.pendingBuffer = null;
          this.pendingMeta = null;
          this.pendingMsgId = 0;
      }

      // 触发回调
      if (this.messageReceivedCallback) {
        this.messageReceivedCallback(message);
      }
    } catch (error) {
      if (error instanceof BinaryProtocolError) {
        // 处理已知的协议错误
        if (error.code === BinaryErrorCode.LOOPBACK_DETECTED) {
          // 回环消息，静默忽略
          return;
        }
        console.warn('二进制协议解析错误:', error.message);
      } else {
        console.error('处理接收消息失败:', JSON.stringify(error));
      }
    }
  }

  /**
   * 连接关闭事件处理
   * @param _err 错误信息
   * @param _value 关闭信息
   */
  private onClose(_err: Error, _value: webSocket.CloseResult): void {
    console.info('WebSocket 连接已关闭');
    this.isConnected = false;
    this.stopHeartbeat();

    if (this.connectionStatusCallback) {
      this.connectionStatusCallback(false);
    }

    // 如果需要重连
    if (this.shouldReconnect) {
      this.startReconnect();
    }
  }

  /**
   * 错误事件处理
   * @param err 错误信息
   */
  private onError(err: Error): void {
    console.error('WebSocket 错误:', JSON.stringify(err));
    if (this.errorCallback) {
      this.errorCallback('WebSocket 错误: ' + JSON.stringify(err));
    }
  }

  /**
   * 发送握手消息（V1.1 二进制协议）
   */
  private async sendHandshake(): Promise<void> {
    if (!this.ws || !this.isConnected) {
      return;
    }

    try {
      // 使用二进制协议封装握手包（自动获取设备信息）
      const handshakeFrame = BinaryProtocolManager.createHandshake();
      await this.ws.send(handshakeFrame);
      console.info('已发送握手消息（V1.1 二进制协议）');
    } catch (error) {
      console.error('发送握手消息失败:', JSON.stringify(error));
    }
  }

  /**
   * 启动心跳
   */
  private startHeartbeat(): void {
    this.stopHeartbeat();

    this.heartbeatTimer = setInterval(() => {
      this.sendHeartbeat();
    }, this.heartbeatInterval);
  }

  /**
   * 停止心跳
   */
  private stopHeartbeat(): void {
    if (this.heartbeatTimer !== -1) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = -1;
    }
  }

  /**
   * 发送心跳消息（V1.1 二进制协议）
   * 使用 HEARTBEAT 类型（Type 0x0）的简单二进制帧
   */
  private async sendHeartbeat(): Promise<void> {
    if (!this.ws || !this.isConnected) {
      return;
    }

    try {
      // 创建一个空载荷的心跳包
      // 心跳包结构：32字节头部 + 空载荷
      const heartbeatFrame = this.createHeartbeatFrame();
      await this.ws.send(heartbeatFrame);
      console.info('已发送心跳消息（V1.1 二进制协议）');
    } catch (error) {
      console.error('发送心跳失败:', JSON.stringify(error));
    }
  }

  /**
   * 创建心跳帧（Type 0x0 HEARTBEAT）
   * 使用与 BinaryProtocolManager.pack 相同的格式
   */
  private createHeartbeatFrame(): ArrayBuffer {
    const HEADER_SIZE = 33;
    const PROTOCOL_MAGIC = 0x4E50; // 'NP'
    const PROTOCOL_VERSION = 0x1;

    const buffer = new ArrayBuffer(HEADER_SIZE);
    const view = new DataView(buffer);

    // Magic
    view.setUint16(0, PROTOCOL_MAGIC, false);
    // Version (高4位) | Type (低4位) - HEARTBEAT = 0x0
    const verType = (PROTOCOL_VERSION << 4) | MessageType.HEARTBEAT;
    view.setUint8(2, verType);
    // Flags
    view.setUint8(3, MessageFlags.NONE);
    // Reserved
    view.setUint8(4, 0);
    // MsgID
    view.setUint32(5, this.getNextMessageId(), false);
    // Sequence
    view.setUint32(9, 0, false);
    // Sender UUID (16 bytes) - 使用随机值填充
    // 注意：理想情况下应该使用与 BinaryProtocolManager 相同的设备 UUID
    // 但由于它是私有的，这里使用随机值（心跳包的发送者校验不重要）
    const bytes = new Uint8Array(buffer);
    for (let i = 13; i < 29; i++) {
      bytes[i] = Math.floor(Math.random() * 256);
    }
    // Payload Length
    view.setUint32(29, 0, false);

    return buffer;
  }

  /**
   * 启动重连
   */
  private startReconnect(): void {
    this.stopReconnect();

    this.reconnectTimer = setTimeout(() => {
      console.info('尝试重新连接...');
      this.connect(this.serverUrl);
    }, this.reconnectInterval);
  }

  /**
   * 停止重连
   */
  private stopReconnect(): void {
    if (this.reconnectTimer !== -1) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = -1;
    }
  }

  /**
   * 获取连接状态
   * @returns 是否已连接
   */
  public getConnectionStatus(): boolean {
    return this.isConnected;
  }
}
