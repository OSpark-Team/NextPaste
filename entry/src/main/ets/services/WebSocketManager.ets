import { webSocket } from '@kit.NetworkKit';
import { ClipboardProtocolManager, SyncMessage, SyncAction, DataType } from '../protocol/ClipboardProtocol';
import { deviceInfo } from '@kit.BasicServicesKit';

/**
 * WebSocket 连接状态回调
 */
export type ConnectionStatusCallback = (connected: boolean) => void;

/**
 * 消息接收回调
 */
export type MessageReceivedCallback = (message: SyncMessage) => void;

/**
 * 错误回调
 */
export type ErrorCallback = (error: string) => void;

/**
 * WebSocket 连接管理器
 * 负责 WebSocket 连接、心跳、消息发送和接收
 */
export class WebSocketManager {
  private ws: webSocket.WebSocket | null = null;
  private serverUrl: string = '';
  private isConnected: boolean = false;
  private heartbeatTimer: number = -1;
  private heartbeatInterval: number = 5000; // 心跳间隔 5 秒
  private reconnectTimer: number = -1;
  private reconnectInterval: number = 5000; // 重连间隔 5 秒
  private shouldReconnect: boolean = false;
  
  private connectionStatusCallback: ConnectionStatusCallback | null = null;
  private messageReceivedCallback: MessageReceivedCallback | null = null;
  private errorCallback: ErrorCallback | null = null;
  
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
   * 发送文本消息
   * @param text 文本内容
   */
  public async sendText(text: string): Promise<boolean> {
    if (!this.isConnected || !this.ws) {
      return false;
    }
    
    try {
      const message = ClipboardProtocolManager.createTextMessage(text);
      await this.ws.send(message);
      return true;
    } catch (error) {
      console.error('发送文本消息失败:', JSON.stringify(error));
      return false;
    }
  }
  
  /**
   * 发送图片消息
   * @param base64 Base64 编码的图片
   */
  public async sendImage(base64: string): Promise<boolean> {
    if (!this.isConnected || !this.ws) {
      return false;
    }

    try {
      const message = ClipboardProtocolManager.createImageMessage(base64);
      await this.ws.send(message);
      return true;
    } catch (error) {
      console.error('发送图片消息失败:', JSON.stringify(error));
      return false;
    }
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

    // 发送握手消息
    this.sendHandshake();

    // 启动心跳
    this.startHeartbeat();
  }

  /**
   * 消息接收事件处理
   * @param err 错误信息
   * @param value 消息内容
   */
  private onMessage(err: Error, value: string | ArrayBuffer): void {
    if (err) {
      console.error('接收消息错误:', JSON.stringify(err));
      return;
    }

    try {
      let messageStr: string;
      if (typeof value === 'string') {
        messageStr = value;
      } else {
        // ArrayBuffer 转字符串
        const uint8Array = new Uint8Array(value);
        messageStr = String.fromCharCode(...uint8Array);
      }

      // 解析消息
      const message = ClipboardProtocolManager.parseMessage(messageStr);

      // 触发回调
      if (this.messageReceivedCallback) {
        this.messageReceivedCallback(message);
      }
    } catch (error) {
      console.error('处理接收消息失败:', JSON.stringify(error));
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
   * 发送握手消息
   */
  private async sendHandshake(): Promise<void> {
    if (!this.ws || !this.isConnected) {
      return;
    }

    try {
      const deviceName = deviceInfo.productModel || 'HarmonyOS Device';
      const handshakeMessage = ClipboardProtocolManager.createHandshake(deviceName);
      await this.ws.send(handshakeMessage);
      console.info('已发送握手消息');
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
   * 发送心跳消息
   */
  private async sendHeartbeat(): Promise<void> {
    if (!this.ws || !this.isConnected) {
      return;
    }

    try {
      const heartbeatMessage = JSON.stringify({
        action: SyncAction.HEARTBEAT,
        id: ClipboardProtocolManager.getDeviceId(),
        timestamp: Date.now(),
        senderId: ClipboardProtocolManager.getDeviceId(),
        data: null
      });
      await this.ws.send(heartbeatMessage);
      console.info('已发送心跳消息');
    } catch (error) {
      console.error('发送心跳失败:', JSON.stringify(error));
    }
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

