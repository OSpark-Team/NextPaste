import { ConnectionStatus } from '../models/AppConfig';

/**
 * 状态指示器组件
 */
@Component
export struct StatusIndicator {
  /**
   * 连接状态
   */
  @Prop status: ConnectionStatus = ConnectionStatus.DISCONNECTED;
  
  /**
   * 获取状态文本
   */
  private getStatusText(): ResourceStr {
    switch (this.status) {
      case ConnectionStatus.CONNECTED:
        return $r('app.string.status_connected');
      case ConnectionStatus.CONNECTING:
        return $r('app.string.status_connecting');
      case ConnectionStatus.DISCONNECTED:
        return $r('app.string.status_disconnected');
      default:
        return $r('app.string.status_disconnected');
    }
  }
  
  /**
   * 获取状态颜色
   */
  private getStatusColor(): ResourceColor {
    switch (this.status) {
      case ConnectionStatus.CONNECTED:
        return $r('app.color.status_connected');
      case ConnectionStatus.CONNECTING:
        return $r('app.color.status_connecting');
      case ConnectionStatus.DISCONNECTED:
        return $r('app.color.status_disconnected');
      default:
        return $r('app.color.status_disconnected');
    }
  }
  
  build() {
    Row({ space: 12 }) {
      // 状态指示点
      Circle({ width: 12, height: 12 })
        .fill(this.getStatusColor())
        .animation({
          duration: 1000,
          curve: Curve.EaseInOut,
          iterations: this.status === ConnectionStatus.CONNECTING ? -1 : 1,
          playMode: PlayMode.Alternate
        })
        .opacity(this.status === ConnectionStatus.CONNECTING ? 0.5 : 1)
      
      // 状态文本
      Text(this.getStatusText())
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .fontWeight(FontWeight.Medium)
    }
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor($r('app.color.background_card'))
    .borderRadius(16)
    .border({
      width: 1,
      color: this.getStatusColor()
    })
  }
}

