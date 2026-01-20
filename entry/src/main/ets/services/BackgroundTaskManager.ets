import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { wantAgent, WantAgent } from '@kit.AbilityKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

/**
 * 后台任务管理器
 * 负责申请和取消后台长时任务
 */
export class BackgroundTaskManager {
  private context: common.UIAbilityContext | null = null;
  private wantAgentInstance: WantAgent | null = null;
  private isTaskRunning: boolean = false;
  
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
      
      // 申请后台长时任务
      await backgroundTaskManager.startBackgroundRunning(
        this.context,
        backgroundTaskManager.BackgroundMode.MULTI_DEVICE_CONNECTION,
        this.wantAgentInstance
      );
      
      this.isTaskRunning = true;
      console.info('后台任务启动成功');
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
      await backgroundTaskManager.stopBackgroundRunning(this.context);
      this.isTaskRunning = false;
      console.info('后台任务停止成功');
      return true;
    } catch (error) {
      const err = error as BusinessError;
      console.error(`停止后台任务失败, code: ${err.code}, message: ${err.message}`);
      return false;
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
   * 获取后台任务运行状态`
   * @returns 是否正在运行
   */
  public isRunning(): boolean {
    return this.isTaskRunning;
  }
}

