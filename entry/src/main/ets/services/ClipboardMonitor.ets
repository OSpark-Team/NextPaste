import { pasteboard } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';

/**
 * 剪切板数据类型
 */
export enum ClipboardDataType {
  /**
   * 文本类型
   */
  TEXT = 'TEXT',
  
  /**
   * 图片类型
   */
  IMAGE = 'IMAGE',
  
  /**
   * 不支持的类型
   */
  UNSUPPORTED = 'UNSUPPORTED'
}

/**
 * 剪切板数据接口
 */
export interface ClipboardData {
  /**
   * 数据类型
   */
  type: ClipboardDataType;
  
  /**
   * 文本内容（当类型为 TEXT 时）
   */
  text?: string;
  
  /**
   * Base64 编码的图片数据（当类型为 IMAGE 时）
   */
  imageBase64?: string;
}

/**
 * 剪切板变化回调函数类型
 */
export type ClipboardChangeCallback = (data: ClipboardData) => void;

/**
 * 剪切板监听器
 * 使用事件监听机制检测剪切板变化
 */
export class ClipboardMonitor {
  private systemPasteboard: pasteboard.SystemPasteboard;
  private changeCallback: ClipboardChangeCallback | null = null;
  private isMonitoring: boolean = false;
  private isSelfUpdate: boolean = false; // 标记是否为自己设置的剪切板数据
  private updateListener: (() => void) | null = null;

  constructor() {
    this.systemPasteboard = pasteboard.getSystemPasteboard();
  }

  /**
   * 开始监听剪切板变化
   * @param callback 剪切板变化时的回调函数
   */
  public startMonitoring(callback: ClipboardChangeCallback): void {
    if (this.isMonitoring) {
      return;
    }

    this.changeCallback = callback;
    this.isMonitoring = true;

    // 创建监听器函数
    this.updateListener = () => {
      this.handleClipboardUpdate();
    };

    // 订阅剪切板更新事件
    try {
      this.systemPasteboard.on('update', this.updateListener);
      console.info('剪切板监听已启动');
    } catch (error) {
      console.error('启动剪切板监听失败:', JSON.stringify(error));
      this.isMonitoring = false;
      this.updateListener = null;
    }
  }

  /**
   * 停止监听剪切板变化
   */
  public stopMonitoring(): void {
    if (!this.isMonitoring) {
      return;
    }

    // 取消订阅剪切板更新事件
    try {
      if (this.updateListener) {
        this.systemPasteboard.off('update', this.updateListener);
        console.info('剪切板监听已停止');
      }
    } catch (error) {
      console.error('停止剪切板监听失败:', JSON.stringify(error));
    }

    this.isMonitoring = false;
    this.updateListener = null;
    this.changeCallback = null;
  }

  /**
   * 处理剪切板更新事件
   */
  private handleClipboardUpdate(): void {
    // 如果是自己设置的数据，忽略此次更新
    if (this.isSelfUpdate) {
      this.isSelfUpdate = false;
      return;
    }

    try {
      // 检查是否有数据
      if (!this.systemPasteboard.hasDataSync()) {
        console.log('剪切板无数据');
        return;
      }

      // 读取剪切板数据并判断类型
      this.readClipboardData();
    } catch (error) {
      console.error('处理剪切板更新时发生错误:', JSON.stringify(error));
    }
  }

  /**
   * 读取剪切板数据
   */
  private async readClipboardData(): Promise<void> {
    try {
      const pasteData = await this.systemPasteboard.getData();
      const recordCount = pasteData.getRecordCount();

      if (recordCount === 0) {
        console.log('剪切板无数据');
        return;
      }

      // 获取第一个记录
      const record = pasteData.getRecord(0);

      // 根据记录的 mimeType 判断数据类型
      const mimeType = record.mimeType;

      console.log('剪切板数据类型:', mimeType);

      if (mimeType === pasteboard.MIMETYPE_TEXT_PLAIN) {
        await this.handleTextData(record);
      } else if (mimeType === pasteboard.MIMETYPE_PIXELMAP) {
        await this.handleImageData(record);
      } else {
        console.info('不支持的剪切板数据类型:', mimeType);
      }
    } catch (error) {
      console.error('读取剪切板数据时发生错误:', JSON.stringify(error));
    }
  }

  /**
   * 处理文本数据
   * @param record 剪切板数据记录
   */
  private async handleTextData(record: pasteboard.PasteDataRecord): Promise<void> {
    try {
      const text = record.toPlainText();

      if (text && text.length > 0 && this.changeCallback) {
        const clipboardData: ClipboardData = {
          type: ClipboardDataType.TEXT,
          text: text
        };
        this.changeCallback(clipboardData);
      }
    } catch (error) {
      console.error('处理文本数据失败:', JSON.stringify(error));
    }
  }

  /**
   * 处理图片数据
   * @param record 剪切板数据记录
   */
  private async handleImageData(record: pasteboard.PasteDataRecord): Promise<void> {
    try {
      const pixelMap = record.pixelMap;

      if (pixelMap && this.changeCallback) {
        // 将 PixelMap 转换为 Base64
        const base64 = await this.pixelMapToBase64(pixelMap);
        if (base64) {
          const clipboardData: ClipboardData = {
            type: ClipboardDataType.IMAGE,
            imageBase64: base64
          };
          this.changeCallback(clipboardData);
        }
      }
    } catch (error) {
      console.error('处理图片数据失败:', JSON.stringify(error));
    }
  }

  /**
   * 将 PixelMap 转换为 Base64 字符串
   * @param pixelMap PixelMap 对象
   * @returns Base64 字符串
   */
  private async pixelMapToBase64(pixelMap: image.PixelMap): Promise<string> {
    try {
      const imagePackerApi = image.createImagePacker();
      const packOpts: image.PackingOption = {
        format: 'image/png',
        quality: 100
      };

      const arrayBuffer = await imagePackerApi.packToData(pixelMap, packOpts);
      const uint8Array = new Uint8Array(arrayBuffer);

      // 使用 util.Base64Helper 进行 Base64 编码
      const base64Helper = new util.Base64Helper();
      const base64 = base64Helper.encodeToStringSync(uint8Array);

      return base64;
    } catch (error) {
      console.error('PixelMap 转 Base64 失败:', JSON.stringify(error));
      return '';
    }
  }

  /**
   * 设置剪切板数据
   * @param data 剪切板数据
   */
  public async setClipboardData(data: ClipboardData): Promise<boolean> {
    try {
      let pasteData: pasteboard.PasteData;

      if (data.type === ClipboardDataType.TEXT && data.text) {
        pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, data.text);
      } else if (data.type === ClipboardDataType.IMAGE && data.imageBase64) {
        // 将 Base64 转换为 PixelMap
        const pixelMap = await this.base64ToPixelMap(data.imageBase64);
        if (!pixelMap) {
          return false;
        }
        pasteData = pasteboard.createData(pasteboard.MIMETYPE_PIXELMAP, pixelMap);
      } else {
        return false;
      }

      // 标记为自己设置的数据，避免触发回调
      this.isSelfUpdate = true;

      await this.systemPasteboard.setData(pasteData);

      return true;
    } catch (error) {
      console.error('设置剪切板数据失败:', JSON.stringify(error));
      // 重置标记
      this.isSelfUpdate = false;
      return false;
    }
  }

  /**
   * 将 Base64 字符串转换为 PixelMap
   * @param base64 Base64 字符串
   * @returns PixelMap 对象
   */
  private async base64ToPixelMap(base64: string): Promise<image.PixelMap | null> {
    try {
      const base64Helper = new util.Base64Helper();
      const uint8Array = base64Helper.decodeSync(base64);

      const imageSourceApi = image.createImageSource(uint8Array.buffer as ArrayBuffer);
      const pixelMap = await imageSourceApi.createPixelMap();

      return pixelMap;
    } catch (error) {
      console.error('Base64 转 PixelMap 失败:', JSON.stringify(error));
      return null;
    }
  }
}

