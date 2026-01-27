import { util } from '@kit.ArkTS';
import { deviceInfo } from '@kit.BasicServicesKit';

// ==========================================
// 常量与枚举定义
// ==========================================

const PROTOCOL_MAGIC = 0x4E50; // ASCII 'NP'
const PROTOCOL_VERSION = 0x1;
// 头部大小（33字节）：Magic(2) + VerType(1) + Flags(1) + Reserved(1) + MsgID(4) + Seq(4) + SenderID(16) + PayloadLen(4) = 33
const HEADER_SIZE = 33;

/**
 * 消息类型定义（低4位）
 */
export enum MessageType {
  HEARTBEAT = 0x0,
  HANDSHAKE = 0x1,
  TEXT = 0x2,
  IMAGE = 0x3,
  FILE = 0x4
}

/**
 * 标志位定义（按位操作 Flags）
 */
export enum MessageFlags {
  NONE = 0x00,
  MF = 0x01,       // 有后续分片
  HAS_META = 0x02  // 包含元数据
}

/**
 * 协议错误码
 */
export enum BinaryErrorCode {
  INVALID_MAGIC = 2001,      // Magic 校验失败
  INVALID_VERSION = 2002,    // 不支持的版本号
  PACKET_TOO_SHORT = 2003,   // 数据包不足头部长度
  LOOPBACK_DETECTED = 2004,  // 回环检测
  META_PARSE_FAILED = 2005,  // 元数据解析失败
  INVALID_INPUT = 2006       // 输入参数无效
}

export class BinaryProtocolError extends Error {
  public code: BinaryErrorCode;
  constructor(code: BinaryErrorCode, message: string) {
    super(message);
    this.name = 'BinaryProtocolError';
    this.code = code;
  }
}

// ==========================================
// 数据结构接口
// ==========================================

/**
 * 解析后的消息结构对象
 */
export interface BinaryMessage {
  type: MessageType;
  flags: number;
  msgId: number;
  seq: number;
  senderIdBytes: Uint8Array;
  payload: Uint8Array;

  /**
   * 如果 Flags 包含 HAS_META，这里存储解析后的元数据对象
   */
  meta?: Record<string, Object>;

  /**
   * 如果 Flags 包含 HAS_META，这里存储剥离元数据后的纯二进制数据
   */
  binaryData?: Uint8Array;
}

/**
 * 握手数据结构
 */
export interface HandshakeMeta {
  name: string;
  os: string;
  ver: number;
}

/**
 * 文件/图片传输的元数据结构
 */
export interface TransferMeta {
  name?: string;
  mime?: string;
  size?: number; // 总大小
  hash?: string;
  width?: number;
  height?: number;
}

// ==========================================
// 核心管理类
// ==========================================

export class BinaryProtocolManager {
  // 缓存设备 UUID（16字节），避免每次生成
  private static readonly DEVICE_UUID_BYTES: Uint8Array = BinaryProtocolManager.initDeviceUuid();
  private static readonly TEXT_ENCODER = new util.TextEncoder();
  private static readonly TEXT_DECODER = new util.TextDecoder();

  /**
   * 生成设备UUID的字节数组（随机模拟UUID）
   */
  private static initDeviceUuid(): Uint8Array {
    // 获取随机UUID字符串（无短横线）
    const uuidStr = util.generateRandomUUID(true).replace(/-/g, '');
    const bytes = new Uint8Array(16);
    for (let i = 0; i < 16; i++) {
      const byteVal = parseInt(uuidStr.substring(i * 2, i * 2 + 2), 16);
      bytes[i] = byteVal;
    }
    return bytes;
  }

  // ==========================
  // 封包方法（Packing）
  // ==========================

  /**
   * 创建握手包（Type 0x1）
   */
  public static createHandshake(): ArrayBuffer {
    const meta: HandshakeMeta = {
      name: deviceInfo.marketName || 'HarmonyOS Device',
      os: 'HarmonyOS ' + deviceInfo.osFullName,
      ver: 11 // 协议版本 v1.1
    };
    const jsonStr = JSON.stringify(meta);
    const payload = BinaryProtocolManager.TEXT_ENCODER.encodeInto(jsonStr);
    const msgId = Math.floor(Math.random() * 0xFFFFFFFF); // 生成随机MsgID

    return BinaryProtocolManager.pack(
      MessageType.HANDSHAKE,
      MessageFlags.NONE,
      msgId,
      0,
      payload
    );
  }

  /**
   * 创建文本消息包
   */
  public static createText(text: string): ArrayBuffer {
    if (!text) throw new BinaryProtocolError(BinaryErrorCode.INVALID_INPUT, 'Text为空');
    const payload = BinaryProtocolManager.TEXT_ENCODER.encodeInto(text);
    const msgId = Math.floor(Math.random() * 0xFFFFFFFF);

    return BinaryProtocolManager.pack(
      MessageType.TEXT,
      MessageFlags.NONE,
      msgId,
      0,
      payload
    );
  }

  /**
   * 创建带有元数据的首帧（例如图片/文件的起始帧）
   * 结构：元数据长度（2字节） + 元数据JSON + 二进制片段
   */
  public static createStartFrame(
    type: MessageType,
    msgId: number,
    meta: TransferMeta,
    chunkData: Uint8Array
  ): ArrayBuffer {
    const metaJson = JSON.stringify(meta);
    const metaBytes = BinaryProtocolManager.TEXT_ENCODER.encodeInto(metaJson);
    const metaLen = metaBytes.byteLength;

    if (metaLen > 65535) {
      throw new BinaryProtocolError(BinaryErrorCode.INVALID_INPUT, '元数据过大');
    }

    const payloadTotalLen = 2 + metaLen + chunkData.byteLength;
    const payloadBuffer = new Uint8Array(payloadTotalLen);
    const view = new DataView(payloadBuffer.buffer);

    // 书写元数据长度（大端）
    view.setUint16(0, metaLen, false);
    // 复制元数据内容
    payloadBuffer.set(metaBytes, 2);
    // 复制二进制内容
    payloadBuffer.set(chunkData, 2 + metaLen);

    return BinaryProtocolManager.pack(
      type,
      MessageFlags.HAS_META | MessageFlags.MF,
      msgId,
      0,
      payloadBuffer
    );
  }

  /**
   * 创建后续分片帧（用于图片/文件传输）
   */
  public static createChunkFrame(
    type: MessageType,
    msgId: number,
    seq: number,
    chunkData: Uint8Array,
    isLast: boolean
  ): ArrayBuffer {
    return BinaryProtocolManager.pack(
      type,
      isLast ? MessageFlags.NONE : MessageFlags.MF,
      msgId,
      seq,
      chunkData
    );
  }

  /**
   * 全面封包底层实现
   */
  private static pack(
    type: MessageType,
    flags: number,
    msgId: number,
    seq: number,
    payload: Uint8Array
  ): ArrayBuffer {
    const totalLen = HEADER_SIZE + payload.byteLength;
    const buffer = new ArrayBuffer(totalLen);
    const view = new DataView(buffer);
    const bytes = new Uint8Array(buffer);

    // 设定 Magic
    view.setUint16(0, PROTOCOL_MAGIC, false);
    // 设置版本和消息类型
    const verType = (PROTOCOL_VERSION << 4) | (type & 0x0F);
    view.setUint8(2, verType);
    // 设置标志位
    view.setUint8(3, flags);
    // 保留字节（未使用）
    view.setUint8(4, 0);
    // 设置消息ID
    view.setUint32(5, msgId, false);
    // 设置序列号
    view.setUint32(9, seq, false);
    // 设备UUID（16字节）
    bytes.set(BinaryProtocolManager.DEVICE_UUID_BYTES, 13);
    // 载荷长度
    view.setUint32(29, payload.byteLength, false);
    // 载荷内容
    bytes.set(payload, HEADER_SIZE);

    return buffer;
  }

  // ==========================
  // 解包方法（Parsing）
  // ==========================

  /**
   * 解析二进制消息
   */
  public static parse(buffer: ArrayBuffer): BinaryMessage {
    if (buffer.byteLength < HEADER_SIZE) {
      throw new BinaryProtocolError(BinaryErrorCode.PACKET_TOO_SHORT, '数据包不足头部长度');
    }

    const view = new DataView(buffer);
    // 校验Magic
    const magic = view.getUint16(0, false);
    if (magic !== PROTOCOL_MAGIC) {
      throw new BinaryProtocolError(BinaryErrorCode.INVALID_MAGIC, `无效Magic: ${magic.toString(16)}`);
    }

    // 提取并校验是否为回环（自发自收）
    const senderBytes = new Uint8Array(buffer, 13, 16);
    if (BinaryProtocolManager.isLoopback(senderBytes)) {
      throw new BinaryProtocolError(BinaryErrorCode.LOOPBACK_DETECTED, '检测到回环');
    }

    // 解析头部字段
    const verType = view.getUint8(2);
    const ver = (verType >> 4) & 0x0F; // TODO: 检查版本号
    const type = verType & 0x0F;

    const flags = view.getUint8(3);
    const msgId = view.getUint32(5, false);
    const seq = view.getUint32(9, false);
    const payloadLen = view.getUint32(29, false);

    // 提取载荷
    const payload = new Uint8Array(buffer, HEADER_SIZE, payloadLen);
    const message: BinaryMessage = {
      type: type as MessageType,
      flags: flags,
      msgId: msgId,
      seq: seq,
      senderIdBytes: senderBytes,
      payload: payload
    };

    // 解析有元数据标志
    if ((flags & MessageFlags.HAS_META) !== 0) {
      try {
        if (payload.byteLength < 2) throw new Error('元数据长度不足');
        const metaLen = (payload[0] << 8) | payload[1];

        if (payload.byteLength < 2 + metaLen) throw new Error('元数据长度不完整');

        const metaBytes = payload.subarray(2, 2 + metaLen);
        const metaJsonStr = BinaryProtocolManager.TEXT_DECODER.decodeToString(metaBytes);
        message.meta = JSON.parse(metaJsonStr);
        message.binaryData = payload.subarray(2 + metaLen);
      } catch (e) {
        throw new BinaryProtocolError(BinaryErrorCode.META_PARSE_FAILED, `元数据解析错误: ${e.message}`);
      }
    }

    return message;
  }

  /**
   * 判断是否为回环（自己给自己发的包）
   */
  private static isLoopback(senderBytes: Uint8Array): boolean {
    const local = BinaryProtocolManager.DEVICE_UUID_BYTES;
    for (let i = 0; i < 16; i++) {
      if (senderBytes[i] !== local[i]) {
        return false;
      }
    }
    return true;
  }
}
