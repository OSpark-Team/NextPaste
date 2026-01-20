import { util } from '@kit.ArkTS';
import { DeviceMode, ConnectionStatus, LogLevel, LogEntry, AppConfig } from '../models/AppConfig';

/**
 * 剪切板同步应用的 ViewModel
 * 负责管理应用状态、日志和业务逻辑
 */
@Observed
export class ClipboardViewModel {
  /**
   * 服务器地址
   */
  @Track public serverAddress: string = '';

  /**
   * 设备模式
   */
  @Track public deviceMode: DeviceMode = DeviceMode.BIDIRECTIONAL;

  /**
   * 连接状态
   */
  @Track public connectionStatus: ConnectionStatus = ConnectionStatus.DISCONNECTED;

  /**
   * 是否正在运行
   */
  @Track public isRunning: boolean = false;

  /**
   * 日志列表
   */
  @Track public logs: LogEntry[] = [];
  
  /**
   * 当前日志过滤级别
   */
  public logFilter: LogLevel | 'ALL' = 'ALL';
  
  /**
   * 设置栏是否展开
   */
  public isSettingsExpanded: boolean = true;
  
  /**
   * 添加日志
   * @param level 日志级别
   * @param message 日志消息
   */
  public addLog(level: LogLevel, message: string): void {
    const log: LogEntry = {
      id: util.generateRandomUUID(true),
      level: level,
      message: message,
      timestamp: Date.now()
    };

    // 创建新数组以触发响应式更新
    const newLogs = [log, ...this.logs];

    // 限制日志数量，最多保留 500 条
    if (newLogs.length > 500) {
      this.logs = newLogs.slice(0, 500);
    } else {
      this.logs = newLogs;
    }
  }
  
  /**
   * 清空日志
   */
  public clearLogs(): void {
    this.logs = [];
  }
  
  /**
   * 获取过滤后的日志
   * @returns 过滤后的日志列表
   */
  public getFilteredLogs(): LogEntry[] {
    if (this.logFilter === 'ALL') {
      return this.logs;
    }
    return this.logs.filter(log => log.level === this.logFilter);
  }
  
  /**
   * 设置日志过滤级别
   * @param filter 过滤级别
   */
  public setLogFilter(filter: LogLevel | 'ALL'): void {
    this.logFilter = filter;
  }
  
  /**
   * 切换设置栏展开状态
   */
  public toggleSettings(): void {
    this.isSettingsExpanded = !this.isSettingsExpanded;
  }
  
  /**
   * 验证服务器地址格式
   * @param address 服务器地址
   * @returns 是否有效
   */
  public validateServerAddress(address: string): boolean {
    if (!address || address.trim().length === 0) {
      return false;
    }
    
    // 验证 WebSocket 地址格式
    const wsPattern = /^wss?:\/\/.+/i;
    return wsPattern.test(address.trim());
  }
  
  /**
   * 获取应用配置
   * @returns 应用配置对象
   */
  public getConfig(): AppConfig {
    return {
      serverAddress: this.serverAddress,
      deviceMode: this.deviceMode,
      isRunning: this.isRunning
    };
  }
  
  /**
   * 设置应用配置
   * @param config 应用配置对象
   */
  public setConfig(config: AppConfig): void {
    this.serverAddress = config.serverAddress;
    this.deviceMode = config.deviceMode;
    this.isRunning = config.isRunning;
  }
  
  /**
   * 重置为默认配置
   */
  public resetToDefault(): void {
    this.serverAddress = '';
    this.deviceMode = DeviceMode.BIDIRECTIONAL;
    this.connectionStatus = ConnectionStatus.DISCONNECTED;
    this.isRunning = false;
    this.logFilter = 'ALL';
    this.isSettingsExpanded = true;
  }
}

