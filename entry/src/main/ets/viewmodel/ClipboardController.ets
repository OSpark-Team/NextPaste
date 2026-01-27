import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { ClipboardViewModel } from './ClipboardViewModel';
import { ClipboardMonitor, ClipboardData, ClipboardDataType } from '../services/ClipboardMonitor';
import { WebSocketManager } from '../services/WebSocketManager';
import { DeviceMode, ConnectionStatus, LogLevel } from '../models/AppConfig';
import { BinaryMessage, MessageType, TransferMeta } from '../protocol/BinaryProtocol';

/**
 * 剪切板同步控制器（V1.1 二进制协议版本）
 * 负责协调各个服务模块
 */
export class ClipboardController {
  private viewModel: ClipboardViewModel;
  private clipboardMonitor: ClipboardMonitor;
  private webSocketManager: WebSocketManager;
  private context: common.UIAbilityContext | null = null;
  // 文本解码器，用于解析二进制消息中的文本
  private textDecoder: util.TextDecoder = new util.TextDecoder();

  constructor(viewModel: ClipboardViewModel) {
    this.viewModel = viewModel;
    this.clipboardMonitor = new ClipboardMonitor();
    this.webSocketManager = new WebSocketManager();

    this.setupWebSocketCallbacks();
  }

  /**
   * 初始化
   * @param context UIAbility 上下文
   */
  public init(context: common.UIAbilityContext): void {
    this.context = context;
  }

  /**
   * 设置 WebSocket 回调（V1.1 二进制协议）
   */
  private setupWebSocketCallbacks(): void {
    // 连接状态回调
    this.webSocketManager.setConnectionStatusCallback((connected: boolean) => {
      if (connected) {
        this.viewModel.connectionStatus = ConnectionStatus.CONNECTED;
        this.viewModel.addLog(LogLevel.SUCCESS, '已连接到服务器');
      } else {
        this.viewModel.connectionStatus = ConnectionStatus.DISCONNECTED;
        this.viewModel.addLog(LogLevel.WARNING, '已断开连接');
      }
    });

    // 消息接收回调（V1.1 二进制协议）
    this.webSocketManager.setMessageReceivedCallback((message: BinaryMessage) => {
      this.handleReceivedMessage(message);
    });

    // 错误回调
    this.webSocketManager.setErrorCallback((error: string) => {
      this.viewModel.addLog(LogLevel.ERROR, error);
    });
  }

  /**
   * 开始同步
   */
  public async start(): Promise<boolean> {
    // 验证服务器地址
    if (!this.viewModel.validateServerAddress(this.viewModel.serverAddress)) {
      this.viewModel.addLog(LogLevel.ERROR, '服务器地址格式不正确');
      return false;
    }

    // 连接 WebSocket
    this.viewModel.connectionStatus = ConnectionStatus.CONNECTING;
    this.viewModel.addLog(LogLevel.INFO, '正在连接服务器...');

    const connected = await this.webSocketManager.connect(this.viewModel.serverAddress);
    if (!connected) {
      this.viewModel.addLog(LogLevel.ERROR, '连接服务器失败');
      this.viewModel.connectionStatus = ConnectionStatus.DISCONNECTED;
      return false;
    }

    // 根据模式启动剪切板监听
    if (this.viewModel.deviceMode === DeviceMode.SEND_ONLY ||
        this.viewModel.deviceMode === DeviceMode.BIDIRECTIONAL) {
      this.startClipboardMonitoring();
    }

    this.viewModel.isRunning = true;
    return true;
  }

  /**
   * 停止同步
   */
  public async stop(): Promise<void> {
    // 停止剪切板监听
    this.clipboardMonitor.stopMonitoring();

    // 断开 WebSocket
    await this.webSocketManager.disconnect();

    this.viewModel.isRunning = false;
    this.viewModel.connectionStatus = ConnectionStatus.DISCONNECTED;
  }

  /**
   * 启动剪切板监听
   */
  private startClipboardMonitoring(): void {
    this.clipboardMonitor.startMonitoring((data: ClipboardData) => {
      this.handleClipboardChange(data);
    });
    this.viewModel.addLog(LogLevel.INFO, '已启动剪切板监听');
  }

  /**
   * 处理剪切板变化
   * @param data 剪切板数据
   */
  private async handleClipboardChange(data: ClipboardData): Promise<void> {
    this.viewModel.addLog(LogLevel.INFO, '检测到剪切板变化');

    if (data.type === ClipboardDataType.TEXT && data.text) {
      // 文本消息使用 V1.1 二进制协议发送
      const sent = await this.webSocketManager.sendText(data.text);
      if (sent) {
        this.viewModel.addLog(LogLevel.SUCCESS, `已发送文本数据 (${data.text.length} 字符)`);
      } else {
        this.viewModel.addLog(LogLevel.ERROR, '发送文本数据失败');
      }
    } else if (data.type === ClipboardDataType.IMAGE && data.imageBase64) {
      // 注意：ClipboardMonitor 目前仍然输出 Base64 格式
      // 需要将 Base64 转换回 ArrayBuffer 以使用 V1.1 二进制协议
      try {
        const base64Helper = new util.Base64Helper();
        const uint8Array = base64Helper.decodeSync(data.imageBase64);
        const arrayBuffer = uint8Array.buffer as ArrayBuffer;

        const sent = await this.webSocketManager.sendImage(arrayBuffer);
        if (sent) {
          this.viewModel.addLog(LogLevel.SUCCESS, '已发送图片数据（二进制协议）');
        } else {
          this.viewModel.addLog(LogLevel.ERROR, '发送图片数据失败');
        }
      } catch (error) {
        this.viewModel.addLog(LogLevel.ERROR, `图片数据转换失败: ${JSON.stringify(error)}`);
      }
    }
  }

  /**
   * 处理接收到的消息（V1.1 二进制协议）
   * @param message 二进制消息
   */
  private async handleReceivedMessage(message: BinaryMessage): Promise<void> {
    // 如果是仅发送模式，忽略接收的消息
    if (this.viewModel.deviceMode === DeviceMode.SEND_ONLY) {
      return;
    }

    switch (message.type) {
      case MessageType.TEXT:
        await this.handleTextMessage(message);
        break;

      case MessageType.IMAGE:
        await this.handleImageMessage(message);
        break;

      case MessageType.HANDSHAKE:
        this.viewModel.addLog(LogLevel.INFO, '收到握手响应');
        break;

      case MessageType.HEARTBEAT:
        // 心跳消息，静默处理
        break;

      default:
        this.viewModel.addLog(LogLevel.WARNING, `收到未知消息类型: ${message.type}`);
    }
  }

  /**
   * 处理文本消息（V1.1）
   * @param message 二进制消息
   */
  private async handleTextMessage(message: BinaryMessage): Promise<void> {
    try {
      // 将载荷解码为 UTF-8 文本
      const text = this.textDecoder.decodeToString(message.payload);

      this.viewModel.addLog(LogLevel.INFO, '接收到文本数据');

      const clipboardData: ClipboardData = {
        type: ClipboardDataType.TEXT,
        text: text
      };

      const success = await this.clipboardMonitor.setClipboardData(clipboardData);
      if (success) {
        this.viewModel.addLog(LogLevel.SUCCESS, `已更新剪切板 (${text.length} 字符)`);
      } else {
        this.viewModel.addLog(LogLevel.ERROR, '更新剪切板失败');
      }
    } catch (error) {
      this.viewModel.addLog(LogLevel.ERROR, `处理文本消息失败: ${JSON.stringify(error)}`);
    }
  }

  /**
   * 处理图片消息（V1.1）
   * @param message 二进制消息
   */
  private async handleImageMessage(message: BinaryMessage): Promise<void> {
    try {
      this.viewModel.addLog(LogLevel.INFO, '接收到图片数据');

      // 获取图片二进制数据
      // 如果消息包含元数据（HAS_META 标志），则使用 binaryData
      // 否则使用完整的 payload
      const imageData = message.binaryData || message.payload;

      // 解析元数据（如果存在）
      if (message.meta) {
        const meta = message.meta as TransferMeta;
        if (meta.mime) {
          this.viewModel.addLog(LogLevel.INFO, `图片格式: ${meta.mime}`);
        }
        if (meta.size) {
          const sizeMB = (meta.size / 1024 / 1024).toFixed(2);
          this.viewModel.addLog(LogLevel.INFO, `图片大小: ${sizeMB} MB`);
        }
      }

      // 将二进制数据转换为 Base64（ClipboardMonitor 目前仍需要 Base64 格式）
      const base64Helper = new util.Base64Helper();
      const base64 = base64Helper.encodeToStringSync(imageData);

      const clipboardData: ClipboardData = {
        type: ClipboardDataType.IMAGE,
        imageBase64: base64
      };

      const success = await this.clipboardMonitor.setClipboardData(clipboardData);
      if (success) {
        this.viewModel.addLog(LogLevel.SUCCESS, '已更新剪切板图片');
      } else {
        this.viewModel.addLog(LogLevel.ERROR, '更新剪切板失败');
      }
    } catch (error) {
      this.viewModel.addLog(LogLevel.ERROR, `处理图片消息失败: ${JSON.stringify(error)}`);
    }
  }

  /**
   * 获取 WebSocketManager 实例（用于主动发送图片等操作）
   */
  public getWebSocketManager(): WebSocketManager {
    return this.webSocketManager;
  }

  /**
   * 清理资源
   */
  public async cleanup(): Promise<void> {
    if (this.viewModel.isRunning) {
      await this.stop();
    }
  }
}
