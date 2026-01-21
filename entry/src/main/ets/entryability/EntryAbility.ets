import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { DeviceMode } from '../models/AppConfig';
import { BackgroundTaskManager } from '../services/BackgroundTaskManager';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  backgroundTaskManager: BackgroundTaskManager = new BackgroundTaskManager();

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }

    this.backgroundTaskManager.init(this.context);

    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    try {
      windowStage.on('windowStageEvent', (data) => {
        if (data === window.WindowStageEventType.SHOWN) {
          hilog.info(0x0000, 'testTag', '%{public}s', 'window stage is shown');
          // 关闭后台任务
          this.backgroundTaskManager.stopBackgroundTask().then((stopped: boolean) => {
            if (stopped) {
              console.log('后台任务已停止');
            } else {
              console.log('停止后台任务失败')
            }
          });
        } else if (data === window.WindowStageEventType.HIDDEN) {
          hilog.info(0x0000, 'testTag', '%{public}s', 'window stage is hidden');
          // 启动后台任务
          this.backgroundTaskManager.startBackgroundTask().then((started: boolean) => {
            if (started) {
              console.log('后台任务已启动');
            } else {
              console.log('启动后台任务失败')
            }
          });
        }
      });
    } catch (err) {
      hilog.error(0x0000, 'testTag', '%{public}s', 'Failed to enable the listener for ' +
        'window stage event changes. Cause:' + JSON.stringify(err));
    }

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }

      // 初始化持久化存储
      PersistentStorage.persistProp('serverAddress', '');
      PersistentStorage.persistProp('deviceMode', DeviceMode.BIDIRECTIONAL);

      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}