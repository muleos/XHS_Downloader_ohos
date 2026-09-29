/** Shared UI atoms. */
import { promptAction, router } from '@kit.ArkUI';

export class Theme {
  static readonly red: string = '#FF2442';
  static readonly textPrimary: string = '#E6000000';
  static readonly textSecondary: string = '#99000000';
  static readonly divider: string = '#1A000000';
  static readonly pageBg: string = '#F7F7F7';
  static readonly cardBg: string = '#FFFFFF';
  static readonly selectedBg: string = '#33FF2442';
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
        Text('‹')
          .fontSize(28)
          .fontColor(Theme.textPrimary)
          .width(40)
          .height(40)
          .textAlign(TextAlign.Center)
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

function emptyBuilder(): void {
}
