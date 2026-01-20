import { util } from '@kit.ArkTS';
import { deviceInfo } from '@kit.BasicServicesKit';

// ==========================================
// 错误处理定义
// ==========================================

/**
 * 协议错误码枚举，用于区分不同类型的错误。
 */
export enum ProtocolErrorCode {
  /**
   * JSON 解析失败：接收到的数据不是合法的 JSON 字符串。
   */
  PARSE_FAILED = 1001,

  /**
   * 格式校验失败：JSON 解析成功，但缺少必要的字段（如 action, senderId）。
   */
  INVALID_FORMAT = 1002,

  /**
   * 回环检测：消息是由当前设备发送的，应当被忽略。
   */
  LOOPBACK_DETECTED = 1003,

  /**
   * 参数错误：封装消息时传入了无效的参数（如空字符串）。
   */
  INVALID_INPUT = 1004,

  /**
   * 未知动作：消息包含不支持的 Action 类型。
   */
  UNKNOWN_ACTION = 1005
}

/**
 * 自定义协议异常类。
 * 调用者可以通过捕获此异常并检查 code 属性来决定处理策略。
 */
export class ProtocolError extends Error {
  public code: ProtocolErrorCode;
  public timestamp: number;

  constructor(code: ProtocolErrorCode, message: string) {
    super(message);
    this.name = 'ProtocolError';
    this.code = code;
    this.timestamp = new Date().getTime();
  }
}

// ==========================================
// 协议常量与接口定义
// ==========================================

export enum SyncAction {
  HANDSHAKE = 'HANDSHAKE',
  CLIPBOARD_SYNC = 'CLIPBOARD_SYNC',
  HEARTBEAT = 'HEARTBEAT'
}

export enum DataType {
  TEXT = 'text',
  IMAGE = 'image',
  HTML = 'html'
}

/**
 * 消息负载的联合类型
 */
export type MessagePayload = ClipboardPayload | HandshakePayload | null;

export interface SyncMessage {
  action: SyncAction;
  id: string;
  timestamp: number;
  senderId: string;
  data: MessagePayload;
}

export interface HandshakePayload {
  deviceName: string;
  platform: string;
}

export interface ClipboardPayload {
  type: DataType;
  mimeType: string;
  content: string;
}

// ==========================================
// 核心管理类
// ==========================================

export class ClipboardProtocolManager {
  private static readonly DEVICE_ID = util.generateRandomUUID(true);
  private static readonly PLATFORM = deviceInfo.osFullName || 'HarmonyOS';

  /**
   * 封装文本消息。
   * @throws {ProtocolError} 如果文本为空。
   */
  public static createTextMessage(text: string): string {
    if (!text || text.length === 0) {
      throw new ProtocolError(ProtocolErrorCode.INVALID_INPUT, 'Text content cannot be empty');
    }
    const payload: ClipboardPayload = {
      type: DataType.TEXT,
      mimeType: 'text/plain',
      content: text
    };
    return ClipboardProtocolManager.packMessage(SyncAction.CLIPBOARD_SYNC, payload);
  }

  /**
   * 封装图片消息。
   * @throws {ProtocolError} 如果 Base64 字符串为空。
   */
  public static createImageMessage(base64Str: string): string {
    if (!base64Str || base64Str.length === 0) {
      throw new ProtocolError(ProtocolErrorCode.INVALID_INPUT, 'Image base64 content cannot be empty');
    }
    const payload: ClipboardPayload = {
      type: DataType.IMAGE,
      mimeType: 'image/png',
      content: base64Str
    };
    return ClipboardProtocolManager.packMessage(SyncAction.CLIPBOARD_SYNC, payload);
  }

  /**
   * 封装握手消息。
   */
  public static createHandshake(deviceName: string): string {
    const validName = deviceName || 'Unknown HarmonyOS Device';
    const payload: HandshakePayload = {
      deviceName: validName,
      platform: ClipboardProtocolManager.PLATFORM
    };
    return ClipboardProtocolManager.packMessage(SyncAction.HANDSHAKE, payload);
  }

  /**
   * 通用封包方法。
   */
  private static packMessage(action: SyncAction, data: MessagePayload): string {
    const msg: SyncMessage = {
      action: action,
      id: util.generateRandomUUID(true),
      timestamp: new Date().getTime(),
      senderId: ClipboardProtocolManager.DEVICE_ID,
      data: data
    };
    return JSON.stringify(msg);
  }

  /**
   * 解析消息并执行严格校验。
   * * @param jsonStr 原始 JSON 字符串
   * @returns 解析后的 SyncMessage 对象
   * @throws {ProtocolError} 抛出具体的错误类型，调用者必须 try-catch 处理。
   * - PARSE_FAILED: JSON 格式错误
   * - INVALID_FORMAT: 缺少必要字段
   * - LOOPBACK_DETECTED: 消息来自本机 (调用者应忽略此消息，但不视为系统错误)
   */
  public static parseMessage(jsonStr: string): SyncMessage {
    let msg: SyncMessage;

    try {
      msg = JSON.parse(jsonStr) as SyncMessage;
    } catch (e) {
      throw new ProtocolError(
        ProtocolErrorCode.PARSE_FAILED,
        `Failed to parse JSON: ${(e as Error).message}`
      );
    }

    if (!msg || typeof msg !== 'object') {
      throw new ProtocolError(ProtocolErrorCode.PARSE_FAILED, 'Parsed result is not an object');
    }
    if (!msg.action || !msg.senderId || !msg.id) {
      throw new ProtocolError(
        ProtocolErrorCode.INVALID_FORMAT,
        'Message missing required fields (action, senderId, or id)'
      );
    }

    if (msg.senderId === ClipboardProtocolManager.DEVICE_ID) {
      throw new ProtocolError(
        ProtocolErrorCode.LOOPBACK_DETECTED,
        'Message originated from this device'
      );
    }

    return msg;
  }

  /**
   * 获取当前设备ID
   */
  public static getDeviceId(): string {
    return ClipboardProtocolManager.DEVICE_ID;
  }
}