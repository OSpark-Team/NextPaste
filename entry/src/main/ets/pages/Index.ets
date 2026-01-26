import { ClipboardViewModel } from '../viewmodel/ClipboardViewModel';
import { ClipboardController } from '../viewmodel/ClipboardController';
import { CustomInput } from '../components/CustomInput';
import { CustomButton } from '../components/CustomButton';
import { StatusIndicator } from '../components/StatusIndicator';
import { DeviceModeSelector } from '../components/DeviceModeSelector';
import { LogItem } from '../components/LogItem';
import { DeviceMode, LogLevel, LogEntry } from '../models/AppConfig';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import Want from '@ohos.app.ability.Want';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';

/**
 * 主页面
 */
@Entry
@Component
  struct Index {
  /**
   * ViewModel 实例
   */
  @State viewModel: ClipboardViewModel = new ClipboardViewModel();
  /**
   * 控制器实例
   */
  private controller: ClipboardController = new ClipboardController(this.viewModel);
  /**
   * 服务器地址（持久化）
   */
  @StorageLink('serverAddress') serverAddress: string = '';
  /**
   * 设备模式（持久化）
   */
  @StorageLink('deviceMode') deviceMode: DeviceMode = DeviceMode.BIDIRECTIONAL;
  /**
   * 设置栏是否展开
   */
  @State isSettingsExpanded: boolean = true;
  /**
   * 日志过滤级别
   */
  @State logFilter: LogLevel | 'ALL' = 'ALL';
  /**
   * 是否正在操作
   */
  @State isOperating: boolean = false;

  /**
   * 屏幕宽度
   */
  @State screenWidth: number = 0;

  /**
   * 是否显示关于页面
   */
  @State showAboutSheet: boolean = false;

  /**
   * 是否使用水平布局（平板/2in1）
   */
  @State isHorizontalLayout: boolean = false;

  /**
   * 响应式布局阈值（dp）
   */
  private readonly LAYOUT_BREAKPOINT: number = 600;

  /**
   * 页面即将显示
   */
  aboutToAppear(): void {
    // 从持久化存储加载配置
    this.viewModel.serverAddress = this.serverAddress;
    this.viewModel.deviceMode = this.deviceMode;

    // 初始化控制器
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.controller.init(context);
  }

  /**
   * 处理屏幕尺寸变化
   */
  private handleAreaChange(_oldValue: Area, newValue: Area): void {
    this.screenWidth = Number(newValue.width);
    this.isHorizontalLayout = this.screenWidth >= this.LAYOUT_BREAKPOINT;
  }

  /**
   * 页面即将销毁
   */
  aboutToDisappear(): void {
    this.controller.cleanup();
  }

  /**
   * 开始/停止同步
   */
  private async toggleSync(): Promise<void> {
    this.isOperating = true;

    try {
      if (this.viewModel.isRunning) {
        await this.controller.stop();
      } else {
        // 保存配置到持久化存储
        this.serverAddress = this.viewModel.serverAddress;
        this.deviceMode = this.viewModel.deviceMode;

        // 弹出权限授权许可
        const permissions: Array<Permissions> = ['ohos.permission.READ_PASTEBOARD'];
        const atManager = abilityAccessCtrl.createAtManager();

        atManager.requestPermissionsFromUser(this.getUIContext().getHostContext(), permissions).then((data) => {
          let grantStatus: number[] = data.authResults;
          let length: number = grantStatus.length;
          for (let i = 0; i < length; i++) {
            if (grantStatus[i] === 0) {
              // 用户授权
              console.info(`${permissions[i]} 已经被授权`);
            } else {
              // 用户拒绝授权
              return;
            }
          }
          // 授权成功。
        }).catch((err: Error) => {
          console.error(`权限授权错误：${err.message}`);
        })

        const success = await this.controller.start();
        if (!success) {
          const promptAction = this.getUIContext()?.getPromptAction();
          promptAction?.showToast({
            message: '启动失败，请检查配置',
            duration: 2000
          });
        }
      }
    } catch (err) {
      try {
        const promptAction = this.getUIContext()?.getPromptAction();
        promptAction?.showToast({
          message: `操作失败: ${err}`,
          duration: 2000
        });
      } catch (e) {
        // 忽略 Toast 显示错误
      }
    }

    this.isOperating = false;
  }

  /**
   * 清空日志
   */
  private clearLogs(): void {
    try {
      this.viewModel.clearLogs();
      const promptAction = this.getUIContext()?.getPromptAction();
      promptAction?.showToast({
        message: '日志已清空',
        duration: 1500
      });
    } catch (err) {
      // 忽略错误
    }
  }

  /**
   * 选择并发送图片
   */
  private async selectAndSendImage(): Promise<void> {
    try {
      // 选择图片
      const photoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      photoSelectOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      photoSelectOptions.maxSelectNumber = 1;

      const photoViewPicker = new photoAccessHelper.PhotoViewPicker();
      const photoSelectResult = await photoViewPicker.select(photoSelectOptions);

      if (photoSelectResult.photoUris.length === 0) {
        return;
      }

      const uri = photoSelectResult.photoUris[0];

      // 读取图片文件
      const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(file.fd);
      const fileSize = stat.size;

      const fileSizeKB = fileSize / 1024;
      const fileSizeMB = fileSizeKB / 1024;

      // 检查文件大小限制（3.5MB）
      const SIZE_LIMIT = 3.5 * 1024 * 1024; // 3.5MB
      if (fileSize > SIZE_LIMIT) {
        fileIo.closeSync(file);
        this.viewModel.addLog(LogLevel.ERROR, `图片过大 (${fileSizeMB.toFixed(2)} MB)，当前版本不支持超过 3.5MB 的图片`);
        this.getUIContext()?.getPromptAction().showToast({
          message: `图片过大 (${fileSizeMB.toFixed(2)} MB)\n当前版本不支持超过 3.5MB 的图片`,
          duration: 3000
        });
        return;
      }

      // 创建 ImageSource 并转换为 PixelMap
      const imageSourceApi = image.createImageSource(file.fd);
      const pixelMap = await imageSourceApi.createPixelMap();
      fileIo.closeSync(file);

      // 转换为 Base64（PNG 格式，quality 100）
      this.viewModel.addLog(LogLevel.INFO, '正在编码图片...');
      const base64 = await this.encodeImageToBase64(pixelMap);

      // 发送图片
      const sent = await this.controller.getWebSocketManager().sendImage(base64);
      if (sent) {
        this.viewModel.addLog(LogLevel.SUCCESS, '图片发送成功');
        this.getUIContext()?.getPromptAction().showToast({
          message: '图片发送成功',
          duration: 1500
        });
      } else {
        this.viewModel.addLog(LogLevel.ERROR, '图片发送失败');
        this.getUIContext()?.getPromptAction().showToast({
          message: '图片发送失败，请检查连接状态',
          duration: 2000
        });
      }

    } catch (err) {
      const error = err as BusinessError;
      this.viewModel.addLog(LogLevel.ERROR, `选择图片失败: ${error.message}`);
      this.getUIContext()?.getPromptAction().showToast({
        message: '选择图片失败',
        duration: 1500
      });
    }
  }

  /**
   * 编码图片为 Base64
   * @param pixelMap PixelMap 对象
   * @returns Base64 字符串
   */
  private async encodeImageToBase64(pixelMap: image.PixelMap): Promise<string> {
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
  }

  /**
   * 获取过滤后的日志
   */
  private getFilteredLogs(): LogEntry[] {
    if (this.logFilter === 'ALL') {
      return this.viewModel.logs;
    }
    return this.viewModel.logs.filter(log => log.level === this.logFilter);
  }

  build() {
    Column() {
      // 顶部标题栏
      this.buildTitleBar()

      // 根据屏幕宽度选择布局方式
      if (this.isHorizontalLayout) {
        // 水平布局（平板/2in1）
        Row({ space: 8 }) {
          // 左侧：设置区域
          Scroll() {
            Column({ space: 8 }) {
              this.buildSettingsSection()
              this.buildImageSendSection()
            }
            .width('100%')
              .alignItems(HorizontalAlign.Start)
          }
          .width('40%')
            .height('100%')
            .scrollBar(BarState.Auto)
            .align(Alignment.Top)

          // 右侧：日志区域
          Column() {
            this.buildLogsSection()
          }
          .width('60%')
            .height('100%')
        }
        .width('100%')
          .layoutWeight(1)
          .alignItems(VerticalAlign.Top)
      } else {
        // 垂直布局（手机）
        Scroll() {
          Column() {
            // 可折叠设置区域
            this.buildSettingsSection()

            // 图片发送区域
            this.buildImageSendSection()

            // 日志区域
            this.buildLogsSection()
          }
          .width('100%')
        }
        .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
      .height('100%')
      .padding(16)
      .backgroundColor($r('app.color.background_primary'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .onAreaChange((oldValue: Area, newValue: Area) => {
        this.handleAreaChange(oldValue, newValue);
      })
      .bindSheet($$this.showAboutSheet, this.buildAboutSheet(), {
        height: SheetSize.FIT_CONTENT,
        showClose: true,
        preferType: SheetType.CENTER,
      })
  }

  /**
   * 构建标题栏
   */
  @Builder
  buildTitleBar() {
    Row() {
      Text($r('app.string.app_title'))
        .fontSize(24)
        .fontColor($r('app.color.text_primary'))
        .fontWeight(FontWeight.Bold)

      Blank()

      // 关于按钮
      SymbolGlyph($r('sys.symbol.info_circle'))
        .fontSize(24)
        .fontColor([$r('app.color.text_secondary')])
        .onClick(() => {
          this.showAboutSheet = true;
        })
        .margin({ right: 12 })

      StatusIndicator({ status: this.viewModel.connectionStatus })
    }
    .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 16 })
      .backgroundColor($r('app.color.background_secondary'))
      .borderRadius(12)
      .margin({ bottom: 16 })
  }

  /**
   * 构建设置区域
   */
  @Builder
  buildSettingsSection() {
    Column() {
      // 折叠/展开按钮（仅在垂直布局时显示）
      if (!this.isHorizontalLayout) {
        Row() {
          Text($r('app.string.settings_section_title'))
            .fontSize(18)
            .fontColor($r('app.color.text_primary'))
            .fontWeight(FontWeight.Medium)

          Blank()

          SymbolGlyph(this.isSettingsExpanded ?
            $r('sys.symbol.chevron_up') :
            $r('sys.symbol.chevron_down'))
            .fontSize(20)
            .fontColor([$r('app.color.text_secondary')])
        }
        .width('100%')
          .padding(16)
          .onClick(() => {
            this.getUIContext()?.animateTo({
              duration: 300,
              curve: Curve.EaseInOut
            }, () => {
              this.isSettingsExpanded = !this.isSettingsExpanded;
            });
          })
      } else {
        // 水平布局时显示固定标题
        Text($r('app.string.settings_section_title'))
          .fontSize(18)
          .fontColor($r('app.color.text_primary'))
          .fontWeight(FontWeight.Medium)
          .width('100%')
          .padding(16)
      }

      // 设置内容
      if (this.isSettingsExpanded || this.isHorizontalLayout) {
        Column({ space: 16 }) {
          // 服务器地址输入
          CustomInput({
            label: $r('app.string.server_address_label'),
            placeholder: $r('app.string.server_address_placeholder'),
            value: this.viewModel.serverAddress,
            disabled: this.viewModel.isRunning,
            onValueChanged: (value: string) => {
              this.viewModel.serverAddress = value;
            }
          })

          // 设备模式选择
          DeviceModeSelector({
            selectedMode: this.viewModel.deviceMode,
            disabled: this.viewModel.isRunning,
            onModeChange: (mode: DeviceMode) => {
              this.viewModel.deviceMode = mode;
            }
          })

          // 开始/停止按钮
          CustomButton({
            text: this.viewModel.isRunning ?
              $r('app.string.button_stop') :
              $r('app.string.button_start'),
            loading: this.isOperating,
            onButtonClick: () => {
              this.toggleSync();
            }
          })
        }
        .width('100%')
          .padding({ left: 16, right: 16, bottom: 16 })
          .transition(TransitionEffect.OPACITY.animation({ duration: 300 }))
      }
    }
    .width('100%')
      .backgroundColor($r('app.color.background_secondary'))
      .borderRadius(12)
      .margin(this.isHorizontalLayout ? { right: 8 } : { top: 16 })
  }

  /**
   * 构建图片发送区域
   */
  @Builder
  buildImageSendSection() {
    Column() {
      Row({ space: 12 }) {
        // 图标
        SymbolGlyph($r('sys.symbol.camera'))
          .fontSize(24)
          .fontColor([$r('app.color.primary_color')])

        // 文本
        Column({ space: 4 }) {
          Text($r('app.string.image_send_title'))
            .fontSize(16)
            .fontColor($r('app.color.text_primary'))
            .fontWeight(FontWeight.Medium)

          Text(this.viewModel.isRunning ?
            $r('app.string.image_send_desc_ready') :
            $r('app.string.image_send_desc_not_ready'))
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        // 箭头图标
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(18)
          .fontColor([$r('app.color.text_tertiary')])
      }
      .width('100%')
      .padding(16)
      .onClick(() => {
        if (this.viewModel.isRunning) {
          this.selectAndSendImage();
        } else {
          this.getUIContext()?.getPromptAction().showToast({
            message: $r('app.string.toast_please_start_sync_first'),
            duration: 1500
          });
        }
      })
    }
    .width('100%')
    .backgroundColor($r('app.color.background_secondary'))
    .borderRadius(12)
    .margin({ top: 8 })
    .opacity(this.viewModel.isRunning ? 1 : 0.6)
  }

  /**
   * 构建日志区域
   */
  @Builder
  buildLogsSection() {
    Column({ space: 12 }) {
      // 日志标题和操作栏
      Row() {
        Text($r('app.string.log_title'))
          .fontSize(18)
          .fontColor($r('app.color.text_primary'))
          .fontWeight(FontWeight.Medium)

        Blank()

        // 清空日志按钮
        Button($r('app.string.log_clear'))
          .fontSize(14)
          .fontColor($r('app.color.primary_color'))
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.clearLogs();
          })
      }
      .width('100%')
        .padding({ left: 16, right: 16, top: 16 })

      // 日志过滤器
      Row({ space: 8 }) {
        this.buildFilterButton('ALL', $r('app.string.log_filter_all'))
        this.buildFilterButton(LogLevel.INFO, $r('app.string.log_filter_info'))
        this.buildFilterButton(LogLevel.SUCCESS, $r('app.string.log_filter_success'))
        this.buildFilterButton(LogLevel.WARNING, $r('app.string.log_filter_warning'))
        this.buildFilterButton(LogLevel.ERROR, $r('app.string.log_filter_error'))
      }
      .width('100%')
        .padding({ left: 16, right: 16 })

      // 日志列表
      List({ space: 8 }) {
        ForEach(this.getFilteredLogs(), (log: LogEntry) => {
          ListItem() {
            LogItem({ log: log })
          }
          .width('100%')
          .transition(TransitionEffect.OPACITY
            .animation({ duration: 400, curve: Curve.Friction })
            .combine(TransitionEffect.translate({ y: -30 }))
            .combine(TransitionEffect.scale({ x: 0.9, y: 0.9 })))
        }, (log: LogEntry) => log.id)
      }
      .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16, bottom: 16 })
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background_secondary'))
      .borderRadius(12)
      .margin(this.isHorizontalLayout ? { left: 8 } : { top: 16 })
  }

  /**
   * 构建过滤按钮
   */
  @Builder
  buildFilterButton(filter: LogLevel | 'ALL', text: ResourceStr) {
    Text(text)
      .fontSize(12)
      .fontColor(this.logFilter === filter ?
        $r('app.color.button_text') :
        $r('app.color.text_secondary'))
      .fontWeight(this.logFilter === filter ? FontWeight.Medium : FontWeight.Normal)
      .padding({
        left: 12,
        right: 12,
        top: 6,
        bottom: 6
      })
      .backgroundColor(this.logFilter === filter ?
        $r('app.color.primary_color') :
        $r('app.color.background_card'))
      .borderRadius(12)
      .onClick(() => {
        this.logFilter = filter;
      })
      .animation({
        duration: 200,
        curve: Curve.EaseInOut
      })
  }

  /**
   * 启动浏览器
   */
  startBrowser(context: common.UIAbilityContext, url: string): void {
    let want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: url,
      parameters: {
        'ohos.ability.params.showDefaultPicker': true
      }
    };

    context.startAbility(want)
      .then(() => {
        console.info('Browser started successfully');
      })
      .catch((err: Error) => {
        console.error(`Failed to start browser: ${err.message}`);
      });
  }

  @Builder
  buildAboutLinkItem(title: ResourceStr, content: ResourceStr, symbol: string, url?: string) {
    Row({ space: 12 }) {
      SymbolGlyph($r(symbol))
        .fontSize(20)
        .fontColor([$r('app.color.primary_color')])

      Column({ space: 2 }) {
        Text(title).fontSize(13)
          .fontColor($r('app.color.text_secondary'))
        Text(content).fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
    }
      .width('100%')
      .padding(12)
      .onClick(() => {
        if (url) {
          const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
          this.startBrowser(context, url);
        }
      })
  }

  /**
   * 构建关于页面
   */
  @Builder
  buildAboutSheet() {
    Column() {
      // 头部装饰条
      Rect().width(40).height(4).radius(2).fill($r('app.color.divider')).margin({ top: 8, bottom: 20 })

      // 应用图标区域
      Column({ space: 12 }) {
        Image($r('app.media.startIcon'))
          .width(80)
          .height(80)
          .borderRadius(20)
          .shadow({ radius: 10, color: '#15000000', offsetX: 0, offsetY: 5 })

        Text($r('app.string.about_app_name'))
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))

        Text($r('app.string.about_version'))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
      }
      .margin({ bottom: 30 })

      // 信息卡片列表
      Column({ space: 12 }) {
        this.buildAboutLinkItem($r('app.string.about_team_title'), $r('app.string.about_team_name'), 'sys.symbol.person_2', 'https://ospark.tech/')
        this.buildAboutLinkItem($r('app.string.about_repo_title'), $r('app.string.about_repo_url'), 'sys.symbol.link', 'https://github.com/OSpark-Team/NextPaste')
        this.buildAboutLinkItem($r('app.string.about_feedback_title'), $r('app.string.about_feedback_desc'), 'sys.symbol.questionmark_circle')
      }
      .padding(16)
        .backgroundColor($r('app.color.background_secondary'))
        .borderRadius(20)
        .margin({ left: 20, right: 20, bottom: 24 })

      // 操作按钮
      Button($r('app.string.about_download_button'))
        .width('80%')
        .height(50)
        .fontWeight(FontWeight.Medium)
        .backgroundColor($r('app.color.primary_color'))
        .borderRadius(25)
        .onClick(() => {
          const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
          // 前往Release页面
          this.startBrowser(context, 'https://github.com/OSpark-Team/NextPaste/releases');
        })

      Text($r('app.string.about_copyright'))
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .margin({ top: 20 })
    }
    .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background_primary'))
  }
}
