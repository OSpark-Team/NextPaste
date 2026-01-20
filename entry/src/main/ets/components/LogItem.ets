import { LogEntry, LogLevel } from '../models/AppConfig';

/**
 * 日志项组件
 */
@Component
export struct LogItem {
  /**
   * 日志条目
   */
  @Prop log: LogEntry = {
    id: '',
    level: LogLevel.INFO,
    message: '',
    timestamp: 0
  };
  
  /**
   * 获取日志级别颜色
   */
  private getLevelColor(): ResourceColor {
    switch (this.log.level) {
      case LogLevel.INFO:
        return $r('app.color.info_color');
      case LogLevel.WARNING:
        return $r('app.color.warning_color');
      case LogLevel.ERROR:
        return $r('app.color.error_color');
      case LogLevel.SUCCESS:
        return $r('app.color.success_color');
      default:
        return $r('app.color.info_color');
    }
  }
  
  /**
   * 获取日志级别背景色
   */
  private getLevelBackgroundColor(): ResourceColor {
    switch (this.log.level) {
      case LogLevel.INFO:
        return $r('app.color.info_background');
      case LogLevel.WARNING:
        return $r('app.color.warning_background');
      case LogLevel.ERROR:
        return $r('app.color.error_background');
      case LogLevel.SUCCESS:
        return $r('app.color.success_background');
      default:
        return $r('app.color.info_background');
    }
  }
  
  /**
   * 获取日志级别文本
   */
  private getLevelText(): ResourceStr {
    switch (this.log.level) {
      case LogLevel.INFO:
        return $r('app.string.log_level_info');
      case LogLevel.WARNING:
        return $r('app.string.log_level_warning');
      case LogLevel.ERROR:
        return $r('app.string.log_level_error');
      case LogLevel.SUCCESS:
        return $r('app.string.log_level_success');
      default:
        return $r('app.string.log_level_info');
    }
  }
  
  /**
   * 格式化时间戳
   */
  private formatTimestamp(): string {
    const date = new Date(this.log.timestamp);
    const hours = String(date.getHours()).padStart(2, '0');
    const minutes = String(date.getMinutes()).padStart(2, '0');
    const seconds = String(date.getSeconds()).padStart(2, '0');
    return `${hours}:${minutes}:${seconds}`;
  }
  
  build() {
    Row({ space: 12 }) {
      // 日志级别标签
      Text(this.getLevelText())
        .fontSize(12)
        .fontColor(this.getLevelColor())
        .fontWeight(FontWeight.Medium)
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .backgroundColor(this.getLevelBackgroundColor())
        .borderRadius(4)
        .flexShrink(0)

      // 日志内容
      Column({ space: 4 }) {
        Text(this.log.message)
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .wordBreak(WordBreak.BREAK_ALL)

        Text(this.formatTimestamp())
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .flexShrink(0)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .constraintSize({ minWidth: 0, maxWidth: '100%' })
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.background_card'))
    .borderRadius(8)
    .alignItems(VerticalAlign.Top)
    .constraintSize({ maxWidth: '100%' })
  }
}

