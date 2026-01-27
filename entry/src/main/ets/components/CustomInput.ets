/**
 * 自定义输入框组件
 */
@Component
export struct CustomInput {
  /**
   * 标签文本
   */
  @Prop label: ResourceStr = '';

  /**
   * 占位符文本
   */
  @Prop placeholder: ResourceStr = '';

  /**
   * 输入值
   */
  @Prop @Watch('onValueChange') value: string = '';

  /**
   * 是否禁用
   */
  @Prop disabled: boolean = false;

  /**
   * 输入类型
   */
  @Prop inputType: InputType = InputType.Normal;

  /**
   * 值变化回调
   */
  onValueChanged?: (value: string) => void;

  /**
   * 右侧操作按钮构建器
   */
  @BuilderParam actionButton?: () => void;

  /**
   * 内部状态
   */
  @State private innerValue: string = '';

  /**
   * 值变化监听
   */
  onValueChange(): void {
    this.innerValue = this.value;
  }

  /**
   * 组件即将显示
   */
  aboutToAppear(): void {
    this.innerValue = this.value;
  }
  
  build() {
    Column({ space: 8 }) {
      // 标签
      if (this.label) {
        Text(this.label)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      }
      
      Row({ space: 8 }) {
        // 输入框
        TextInput({
          text: this.innerValue,
          placeholder: this.placeholder
        })
          .layoutWeight(1)
          .type(this.inputType)
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.input_background'))
          .borderRadius(8)
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .border({
            width: 1,
            color: $r('app.color.input_border')
          })
          .enabled(!this.disabled)
          .opacity(this.disabled ? 0.5 : 1)
          .onChange((value: string) => {
            this.innerValue = value;
            if (this.onValueChanged) {
              this.onValueChanged(value);
            }
          })

        // 右侧操作按钮
        if (this.actionButton) {
          this.actionButton()
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

