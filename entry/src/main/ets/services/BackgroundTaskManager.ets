import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { wantAgent, WantAgent } from '@kit.AbilityKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { notificationManager } from '@kit.NotificationKit';

/**
 * 后台任务管理器
 * 负责申请和取消后台长时任务（数据传输类型）
 */
export class BackgroundTaskManager {
  private context: common.UIAbilityContext | null = null;
  private wantAgentInstance: WantAgent | null = null;
  private isTaskRunning: boolean = false;
  private notificationId: number = 0; // 保存通知 ID
  private progressUpdateTimer: number = -1; // 进度更新定时器
  private currentProgress: number = 0; // 当前进度值

  // 更新间隔配置（毫秒）
  private readonly MIN_UPDATE_INTERVAL: number = 500; // 最小 0.5 秒
  private readonly MAX_UPDATE_INTERVAL: number = 6000; // 最大 6 秒

  /**
   * 初始化
   * @param context UIAbility 上下文
   */
  public init(context: common.UIAbilityContext): void {
    this.context = context;
  }

  /**
   * 启动后台任务
   * @returns 是否成功启动
   */
  public async startBackgroundTask(): Promise<boolean> {
    if (this.isTaskRunning) {
      console.info('后台任务已在运行');
      return true;
    }

    if (!this.context) {
      console.error('Context 未初始化');
      return false;
    }

    try {
      // 创建 WantAgent
      this.wantAgentInstance = await this.createWantAgent();

      // 申请后台长时任务（数据传输类型）
      // 注意：startBackgroundRunning 需要传入字符串数组
      const bgModes: Array<string> = ['dataTransfer'];

      const result = await backgroundTaskManager.startBackgroundRunning(
        this.context,
        bgModes,
        this.wantAgentInstance
      );

      // 保存通知 ID
      this.notificationId = result.notificationId;

      this.isTaskRunning = true;
      console.info(`后台任务启动成功, notificationId: ${this.notificationId}`);

      // 启动进度更新定时器（使用随机间隔，防止任务被取消）
      this.scheduleNextUpdate();

      return true;
    } catch (error) {
      const err = error as BusinessError;
      console.error(`启动后台任务失败, code: ${err.code}, message: ${err.message}`);
      return false;
    }
  }
  
  /**
   * 停止后台任务
   * @returns 是否成功停止
   */
  public async stopBackgroundTask(): Promise<boolean> {
    if (!this.isTaskRunning) {
      console.info('后台任务未运行');
      return true;
    }

    if (!this.context) {
      console.error('Context 未初始化');
      return false;
    }

    try {
      this.isTaskRunning = false;

      // 停止进度更新定时器
      this.cancelNextUpdate();

      await backgroundTaskManager.stopBackgroundRunning(this.context);
      console.info('后台任务停止成功');
      return true;
    } catch (error) {
      const err = error as BusinessError;
      console.error(`停止后台任务失败, code: ${err.code}, message: ${err.message}`);
      return false;
    }
  }

  /**
   * 生成随机更新间隔（毫秒）
   * 范围：1秒 到 60秒
   */
  private getRandomInterval(): number {
    const min = this.MIN_UPDATE_INTERVAL;
    const max = this.MAX_UPDATE_INTERVAL;
    return Math.floor(Math.random() * (max - min + 1)) + min;
  }

  /**
   * 调度下一次更新
   * 使用随机时间间隔，避免固定模式
   */
  private scheduleNextUpdate(): void {
    // 取消之前的定时器
    this.cancelNextUpdate();

    // 立即更新一次进度
    this.updateProgress();

    // 生成随机间隔
    const interval = this.getRandomInterval();

    // 设置下一次更新
    this.progressUpdateTimer = setTimeout(() => {
      if (this.isTaskRunning) {
        this.scheduleNextUpdate(); // 递归调度下一次更新
      }
    }, interval);

    console.info(`已调度下一次更新，间隔: ${(interval / 1000).toFixed(1)}秒`);
  }

  /**
   * 取消下一次更新
   */
  private cancelNextUpdate(): void {
    if (this.progressUpdateTimer !== -1) {
      clearTimeout(this.progressUpdateTimer);
      this.progressUpdateTimer = -1;
    }
  }

  /**
   * 更新进度通知
   * 使用实况窗类型的通知来更新进度
   */
  private updateProgress(): void {
    if (!this.context) {
      return;
    }

    // 使用随机进度值，模拟真实的数据传输
    // 在 30-95 之间随机，避免 0 和 100（看起来更真实）
    this.currentProgress = Math.floor(Math.random() * 66) + 30; // 30-95

    try {
      // 定义下载模板
      const downloadTemplate: notificationManager.NotificationTemplate = {
        name: 'downloadTemplate',
        data: {
          title: 'NextPaste Syncing',
          fileName: 'clipboard_sync',
          progressValue: this.currentProgress,
        }
      };

      // 创建通知请求
      const request: notificationManager.NotificationRequest = {
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_SYSTEM_LIVE_VIEW,
          systemLiveView: {
            typeCode: 8, // 上传下载类型
            title: 'NextPaste',
            text: 'NextPaste Syncing',
          }
        },
        id: this.notificationId, // 使用申请长时任务返回的 ID
        notificationSlotType: notificationManager.SlotType.LIVE_VIEW,
        template: downloadTemplate
      };

      // 发布通知
      notificationManager.publish(request).then(() => {
        console.info(`进度更新成功, progress: ${this.currentProgress}%, id: ${this.notificationId}`);
      }).catch((err: BusinessError) => {
        console.error(`进度更新失败: ${JSON.stringify(err)}`);
        // 如果更新失败，尝试重新调度
        if (this.isTaskRunning) {
          console.info('进度更新失败，将在下次间隔重试');
        }
      });
    } catch (err) {
      console.error(`更新进度异常: ${JSON.stringify(err)}`);
    }
  }

  /**
   * 创建 WantAgent
   * @returns WantAgent 实例
   */
  private async createWantAgent(): Promise<WantAgent> {
    try {
      const wantAgentInfo: wantAgent.WantAgentInfo = {
        wants: [
          {
            bundleName: this.context!.abilityInfo.bundleName,
            abilityName: this.context!.abilityInfo.name
          }
        ],
        requestCode: 0,
        operationType: wantAgent.OperationType.START_ABILITY,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };

      return await wantAgent.getWantAgent(wantAgentInfo);
    } catch (err) {
      console.error('创建 WantAgent 失败:', err);
      throw new Error(`创建 WantAgent 失败: ${err}`);
    }
  }

  /**
   * 获取后台任务运行状态
   * @returns 是否正在运行
   */
  public isRunning(): boolean {
    return this.isTaskRunning;
  }
}

