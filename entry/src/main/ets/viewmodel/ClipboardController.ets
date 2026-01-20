import { common } from '@kit.AbilityKit';
import { ClipboardViewModel } from './ClipboardViewModel';
import { ClipboardMonitor, ClipboardData, ClipboardDataType } from '../services/ClipboardMonitor';
import { WebSocketManager } from '../services/WebSocketManager';
import { BackgroundTaskManager } from '../services/BackgroundTaskManager';
import { DeviceMode, ConnectionStatus, LogLevel } from '../models/AppConfig';
import { SyncMessage, SyncAction, DataType, ClipboardPayload } from '../protocol/ClipboardProtocol';

/**
 * 剪切板同步控制器
 * 负责协调各个服务模块
 */
export class ClipboardController {
  private viewModel: ClipboardViewModel;
  private clipboardMonitor: ClipboardMonitor;
  private webSocketManager: WebSocketManager;
  private backgroundTaskManager: BackgroundTaskManager;
  private context: common.UIAbilityContext | null = null;
  
  constructor(viewModel: ClipboardViewModel) {
    this.viewModel = viewModel;
    this.clipboardMonitor = new ClipboardMonitor();
    this.webSocketManager = new WebSocketManager();
    this.backgroundTaskManager = new BackgroundTaskManager();
    
    this.setupWebSocketCallbacks();
  }
  
  /**
   * 初始化
   * @param context UIAbility 上下文
   */
  public init(context: common.UIAbilityContext): void {
    this.context = context;
    this.backgroundTaskManager.init(context);
    this.viewModel.addLog(LogLevel.INFO, '应用启动');
  }
  
  /**
   * 设置 WebSocket 回调
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
    
    // 消息接收回调
    this.webSocketManager.setMessageReceivedCallback((message: SyncMessage) => {
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
    
    // 启动后台任务
    this.viewModel.addLog(LogLevel.INFO, '正在启动后台任务...');
    const taskStarted = await this.backgroundTaskManager.startBackgroundTask();
    if (!taskStarted) {
      this.viewModel.addLog(LogLevel.ERROR, '启动后台任务失败');
      return false;
    }
    this.viewModel.addLog(LogLevel.SUCCESS, '后台任务已启动');
    
    // 连接 WebSocket
    this.viewModel.connectionStatus = ConnectionStatus.CONNECTING;
    this.viewModel.addLog(LogLevel.INFO, '正在连接服务器...');
    
    const connected = await this.webSocketManager.connect(this.viewModel.serverAddress);
    if (!connected) {
      this.viewModel.addLog(LogLevel.ERROR, '连接服务器失败');
      await this.backgroundTaskManager.stopBackgroundTask();
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
    
    // 停止后台任务
    await this.backgroundTaskManager.stopBackgroundTask();
    this.viewModel.addLog(LogLevel.INFO, '后台任务已停止');
    
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
      const sent = await this.webSocketManager.sendText(data.text);
      if (sent) {
        this.viewModel.addLog(LogLevel.SUCCESS, `已发送文本数据 (${data.text.length} 字符)`);
      } else {
        this.viewModel.addLog(LogLevel.ERROR, '发送文本数据失败');
      }
    } else if (data.type === ClipboardDataType.IMAGE && data.imageBase64) {
      const sent = await this.webSocketManager.sendImage(data.imageBase64);
      if (sent) {
        this.viewModel.addLog(LogLevel.SUCCESS, '已发送图片数据');
      } else {
        this.viewModel.addLog(LogLevel.ERROR, '发送图片数据失败');
      }
    }
  }

  /**
   * 处理接收到的消息
   * @param message 同步消息
   */
  private async handleReceivedMessage(message: SyncMessage): Promise<void> {
    // 如果是仅发送模式，忽略接收的消息
    if (this.viewModel.deviceMode === DeviceMode.SEND_ONLY) {
      return;
    }

    if (message.action === SyncAction.CLIPBOARD_SYNC && message.data) {
      const payload = message.data as ClipboardPayload;

      if (payload.type === DataType.TEXT) {
        this.viewModel.addLog(LogLevel.INFO, '接收到文本数据');
        const clipboardData: ClipboardData = {
          type: ClipboardDataType.TEXT,
          text: payload.content
        };
        const success = await this.clipboardMonitor.setClipboardData(clipboardData);
        if (success) {
          this.viewModel.addLog(LogLevel.SUCCESS, `已更新剪切板 (${payload.content.length} 字符)`);
        } else {
          this.viewModel.addLog(LogLevel.ERROR, '更新剪切板失败');
        }
      } else if (payload.type === DataType.IMAGE) {
        this.viewModel.addLog(LogLevel.INFO, '接收到图片数据');
        const clipboardData: ClipboardData = {
          type: ClipboardDataType.IMAGE,
          imageBase64: payload.content
        };
        const success = await this.clipboardMonitor.setClipboardData(clipboardData);
        if (success) {
          this.viewModel.addLog(LogLevel.SUCCESS, '已更新剪切板图片');
        } else {
          this.viewModel.addLog(LogLevel.ERROR, '更新剪切板失败');
        }
      }
    } else if (message.action === SyncAction.HANDSHAKE) {
      this.viewModel.addLog(LogLevel.INFO, '收到握手响应');
    }
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

