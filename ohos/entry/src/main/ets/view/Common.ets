/** Shared UI atoms. */
import { promptAction, router } from '@kit.ArkUI';

export class Theme {
  static readonly red: string = '#FF2442';
  /** 主题高亮色（v1.24.1 起为皇家蓝 #4169E1）：底栏选中态 / 主操作按钮。 */
  static readonly accent: string = '#4169E1';
  static readonly accentLight: string = '#1A4169E1';
  static readonly textPrimary: string = '#E6000000';
  static readonly textSecondary: string = '#99000000';
  static readonly divider: string = '#1A000000';
  static readonly pageBg: string = '#F7F7F7';
  static readonly cardBg: string = '#FFFFFF';
  static readonly selectedBg: string = '#334169E1';
}

export function toast(message: ResourceStr): void {
  promptAction.showToast({ message: message, duration: 2200 });
}

@Component
export struct TitleBar {
  title: ResourceStr = '';
  showBack: boolean = false;

  build() {
    Row({ space: 8 }) {
      if (this.showBack) {
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(22)
            .fontColor([Theme.textPrimary])
        }
        .width(40)
        .height(40)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          router.back();
        })
      }
      Text(this.title)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.textPrimary)
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
  }
}

@Builder
export function emptyBuilder(): void {
}

@Component
export struct SectionCard {
  title: ResourceStr = '';
  @BuilderParam content: () => void = emptyBuilder;

  build() {
    Column({ space: 12 }) {
      Text(this.title)
        .fontSize(14)
        .fontColor(Theme.textSecondary)
        .width('100%')
      this.content()
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor(Theme.cardBg)
  }
}

// ---------------------------------------------------------------------------
// 设置行组件（v1.20.0 从 Settings.ets 上移：设置主页面与三个二级设置页共用）。
// 数据字段必须 @Prop —— ArkUI 普通成员变量只在组件创建时赋值一次，
// 父组件重渲染时不会同步，导致开关/取值"点了不动"；@Prop 单向同步实时刷新。
// ---------------------------------------------------------------------------

@Component
export struct SelectorRow {
  @Prop label: ResourceStr = '';
  @Prop desc: string = '';
  @Prop value: ResourceStr = '';
  /** 值区文字颜色（二级页入口行用 textSecondary，选项行用 accent） */
  valueColor: string = Theme.accent;
  /** true = 行尾画箭头（二级页入口）；false = 选项行不画 */
  showArrow: boolean = true;
  onTap: () => void = (): void => {};

  build() {
    Row() {
      Column({ space: 2 }) {
        Text(this.label).fontSize(15).fontColor(Theme.textPrimary)
        if (this.desc.length > 0) {
          Text(this.desc).fontSize(12).fontColor(Theme.textSecondary)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text(this.value).fontSize(14).fontColor(this.valueColor)
      if (this.showArrow) {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(15)
          .fontColor([Theme.textSecondary])
          .margin({ left: 6 })
      }
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .onClick(() => {
      this.onTap();
    })
  }
}

/** 带副标题的开关行（安卓 OptionSwitch title+summary 同款）。 */
@Component
export struct ToggleRow {
  @Prop label: ResourceStr = '';
  @Prop desc: string = '';
  @Prop on: boolean = false;
  onChange: (v: boolean) => void = (): void => {};

  build() {
    Row() {
      Column({ space: 2 }) {
        Text(this.label).fontSize(15).fontColor(Theme.textPrimary)
        if (this.desc.length > 0) {
          Text(this.desc).fontSize(12).fontColor(Theme.textSecondary)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.on })
        .selectedColor(Theme.accent)
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .onClick(() => {
      this.onChange(!this.on);
    })
  }
}

@Component
export struct ValueRow {
  @Prop label: ResourceStr = '';
  @Prop @Watch('onExternal') value: string = '';
  onChange: (v: string) => void = (): void => {};
  /** 本地编辑态：输入过程不被父组件重渲染打断（光标跳回） */
  @State text: string = '';

  aboutToAppear(): void {
    this.text = this.value;
  }

  /** 外部值变化（如范围收敛 45）时同步到输入框 */
  onExternal(): void {
    if (this.text !== this.value) {
      this.text = this.value;
    }
  }

  build() {
    Row({ space: 8 }) {
      Text(this.label).fontSize(15).fontColor(Theme.textPrimary).width(120)
      TextInput({ text: this.text })
        .fontSize(14)
        .layoutWeight(1)
        .backgroundColor(Theme.pageBg)
        .onChange((v: string) => {
          this.text = v;
          this.onChange(v);
        })
    }
    .width('100%')
    .height(48)
  }
}

/**
 * 多选项选择（v1.20.0，安卓 WindowSpinnerPreference 同款交互）：
 * showActionMenu 的 buttons 是最多 6 个的元组类型，装不下实况合成格式
 * 8 个选项 → 改用页面内底部浮层。
 * 用法：页面持有 @State sheet: SheetState，pick() 填参后 open=true；
 * 根布局叠加 <OptionSheetOverlay { sheet } />。
 */
@Observed
export class SheetState {
  open: boolean = false;
  title: string = '';
  labels: string[] = [];
  selectedIndex: number = 0;
  onSelect: (index: number) => void = (): void => {};
}

@Component
export struct OptionSheetOverlay {
  @ObjectLink sheet: SheetState;

  private pick(index: number): void {
    const cb = this.sheet.onSelect;
    this.sheet.open = false;
    if (index >= 0 && index < this.sheet.labels.length) {
      cb(index);
    }
  }

  build() {
    if (this.sheet.open) {
      // 蒙层
      Column() {
        Blank()
          .onClick(() => {
            this.sheet.open = false;
          })
        // 选项卡
        Column({ space: 2 }) {
          Text(this.sheet.title)
            .fontSize(14)
            .fontColor(Theme.textSecondary)
            .width('100%')
            .padding({ left: 20, top: 16, bottom: 8 })
          List() {
            ForEach(this.sheet.labels, (label: string, index: number) => {
              ListItem() {
                Row({ space: 8 }) {
                  Text(label)
                    .fontSize(15)
                    .fontColor(index === this.sheet.selectedIndex ? Theme.accent : Theme.textPrimary)
                    .layoutWeight(1)
                  if (index === this.sheet.selectedIndex) {
                    SymbolGlyph($r('sys.symbol.checkmark'))
                      .fontSize(16)
                      .fontColor([Theme.accent])
                  }
                }
                .width('100%')
                .height(46)
                .padding({ left: 20, right: 20 })
                .onClick(() => {
                  this.pick(index);
                })
              }
            }, (label: string, index: number) => index + '_' + label)
          }
          .width('100%')
          .height(Math.min(this.sheet.labels.length * 46 + 16, 380))
          .scrollBar(BarState.Off)
          Text('取消')
            .fontSize(15)
            .fontColor(Theme.textSecondary)
            .width('100%')
            .textAlign(TextAlign.Center)
            .height(48)
            .onClick(() => {
              this.sheet.open = false;
            })
        }
        .width('100%')
        .borderRadius({ topLeft: 20, topRight: 20 })
        .backgroundColor(Theme.cardBg)
        .padding({ top: 4, bottom: (AppStorage.get<number>('bottomAvoid') ?? 0) + 12 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#52000000')
      .hitTestBehavior(HitTestMode.Block)
      .alignItems(HorizontalAlign.Start)
    }
  }
}

