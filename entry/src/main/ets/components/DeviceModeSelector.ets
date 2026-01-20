import { DeviceMode } from '../models/AppConfig';

/**
 * 设备模式选择器组件
 */
@Component
export struct DeviceModeSelector {
  /**
   * 当前选中的模式
   */
  @Prop selectedMode: DeviceMode = DeviceMode.BIDIRECTIONAL;

  /**
   * 模式变化回调
   */
  onModeChange?: (mode: DeviceMode) => void;

  /**
   * 是否禁用
   */
  @Prop disabled: boolean = false;
  
  /**
   * 获取模式文本
   */
  private getModeText(mode: DeviceMode): ResourceStr {
    switch (mode) {
      case DeviceMode.SEND_ONLY:
        return $r('app.string.mode_send_only');
      case DeviceMode.RECEIVE_ONLY:
        return $r('app.string.mode_receive_only');
      case DeviceMode.BIDIRECTIONAL:
        return $r('app.string.mode_bidirectional');
      default:
        return $r('app.string.mode_bidirectional');
    }
  }
  
  /**
   * 渲染模式选项
   */
  @Builder
  private buildModeOption(mode: DeviceMode) {
    Row({ space: 8 }) {
      // 模式文本
      Text(this.getModeText(mode))
        .fontSize(14)
        .fontColor(this.selectedMode === mode ?
          $r('app.color.primary_color') :
          $r('app.color.text_primary'))
        .fontWeight(this.selectedMode === mode ?
          FontWeight.Medium :
          FontWeight.Normal)
        .textAlign(TextAlign.Start)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .backgroundColor(this.selectedMode === mode ?
      $r('app.color.info_background') :
      $r('app.color.background_card'))
    .borderRadius(8)
    .onClick(() => {
      if (!this.disabled && this.onModeChange) {
        this.onModeChange(mode);
      }
    })
    .animation({
      duration: 200,
      curve: Curve.EaseInOut
    })
  }
  
  build() {
    Column({ space: 8 }) {
      // 标签
      Text($r('app.string.device_mode_label'))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      
      // 模式选项列表
      Column({ space: 8 }) {
        this.buildModeOption(DeviceMode.BIDIRECTIONAL)
        this.buildModeOption(DeviceMode.SEND_ONLY)
        this.buildModeOption(DeviceMode.RECEIVE_ONLY)
      }
      .width('100%')
      .opacity(this.disabled ? 0.5 : 1)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

