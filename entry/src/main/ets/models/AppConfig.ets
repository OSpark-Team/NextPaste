/**
 * 设备模式枚举
 */
export enum DeviceMode {
  /**
   * 仅发送模式：只发送本地剪切板变化到服务器
   */
  SEND_ONLY = 'SEND_ONLY',
  
  /**
   * 仅接收模式：只接收服务器的剪切板数据
   */
  RECEIVE_ONLY = 'RECEIVE_ONLY',
  
  /**
   * 双向同步模式：同时发送和接收剪切板数据
   */
  BIDIRECTIONAL = 'BIDIRECTIONAL'
}

/**
 * 连接状态枚举
 */
export enum ConnectionStatus {
  /**
   * 未连接
   */
  DISCONNECTED = 'DISCONNECTED',
  
  /**
   * 连接中
   */
  CONNECTING = 'CONNECTING',
  
  /**
   * 已连接
   */
  CONNECTED = 'CONNECTED'
}

/**
 * 日志级别枚举
 */
export enum LogLevel {
  /**
   * 信息级别
   */
  INFO = 'INFO',
  
  /**
   * 警告级别
   */
  WARNING = 'WARNING',
  
  /**
   * 错误级别
   */
  ERROR = 'ERROR',
  
  /**
   * 成功级别
   */
  SUCCESS = 'SUCCESS'
}

/**
 * 日志条目接口
 */
export interface LogEntry {
  /**
   * 日志唯一标识
   */
  id: string;
  
  /**
   * 日志级别
   */
  level: LogLevel;
  
  /**
   * 日志消息
   */
  message: string;
  
  /**
   * 时间戳
   */
  timestamp: number;
}

/**
 * 应用配置接口
 */
export interface AppConfig {
  /**
   * WebSocket 服务器地址
   */
  serverAddress: string;
  
  /**
   * 设备模式
   */
  deviceMode: DeviceMode;
  
  /**
   * 是否正在运行
   */
  isRunning: boolean;
}

