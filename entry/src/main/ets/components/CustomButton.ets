/**
 * 按钮类型枚举
 */
export enum CustomButtonType {
  /**
   * 主要按钮
   */
  PRIMARY = 'PRIMARY',
  
  /**
   * 次要按钮
   */
  SECONDARY = 'SECONDARY',
  
  /**
   * 危险按钮
   */
  DANGER = 'DANGER'
}

/**
 * 自定义按钮组件
 */
@Component
export struct CustomButton {
  /**
   * 按钮文本
   */
  @Prop text: ResourceStr = '';
  
  /**
   * 按钮类型
   */
  @Prop buttonType: CustomButtonType = CustomButtonType.PRIMARY;
  
  /**
   * 是否禁用
   */
  @Prop disabled: boolean = false;
  
  /**
   * 是否加载中
   */
  @Prop loading: boolean = false;
  
  /**
   * 点击事件回调
   */
  onButtonClick?: () => void;
  
  /**
   * 获取按钮背景色
   */
  private getBackgroundColor(): ResourceColor {
    if (this.disabled || this.loading) {
      return $r('app.color.primary_color_disabled');
    }
    
    switch (this.buttonType) {
      case CustomButtonType.PRIMARY:
        return $r('app.color.primary_color');
      case CustomButtonType.SECONDARY:
        return $r('app.color.background_secondary');
      case CustomButtonType.DANGER:
        return $r('app.color.error_color');
      default:
        return $r('app.color.primary_color');
    }
  }
  
  /**
   * 获取按钮文本颜色
   */
  private getTextColor(): ResourceColor {
    if (this.buttonType === CustomButtonType.SECONDARY) {
      return $r('app.color.text_primary');
    }
    return $r('app.color.button_text');
  }
  
  build() {
    Button() {
      Row({ space: 8 }) {
        if (this.loading) {
          LoadingProgress()
            .width(20)
            .height(20)
            .color(this.getTextColor())
        }
        
        Text(this.text)
          .fontSize(16)
          .fontColor(this.getTextColor())
          .fontWeight(FontWeight.Medium)
      }
      .justifyContent(FlexAlign.Center)
    }
    .type(ButtonType.Normal)
    .backgroundColor(this.getBackgroundColor())
    .borderRadius(8)
    .padding({ left: 24, right: 24, top: 12, bottom: 12 })
    .enabled(!this.disabled && !this.loading)
    .stateEffect(true)
    .onClick(() => {
      if (this.onButtonClick && !this.disabled && !this.loading) {
        this.onButtonClick();
      }
    })
    .animation({
      duration: 200,
      curve: Curve.EaseInOut
    })
  }
}

