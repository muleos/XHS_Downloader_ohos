/**
 * 我的：VHome 风格 —— 大标题 + 圆形设置按钮 + 圆角卡片功能列表。
 */
import { router } from '@kit.ArkUI';
import { AppContainer } from '../data/AppContainer';
import { Theme } from '../view/Common';

@Component
export struct MinePage {
  @StorageLink('topAvoid') topAvoid: number = 0;
  @StorageLink('bottomAvoid') bottomAvoid: number = 0;
  @StorageLink('leftAvoid') leftAvoid: number = 0;
  @StorageLink('rightAvoid') rightAvoid: number = 0;
  @State savedCount: number = 0;
  @StorageLink('savedVersion') @Watch('onSavedChanged') savedVersion: number = 0;

  aboutToAppear(): void {
    this.savedCount = AppContainer.get().saved.getAll().length;
  }

  onSavedChanged(): void {
    this.savedCount = AppContainer.get().saved.getAll().length;
  }

  build() {
    Column() {
      // VHome 风格顶部：大标题 + 圆形设置按钮
      Row() {
        Text('我的')
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textPrimary)
          .layoutWeight(1)
        Row() {
          SymbolGlyph($r('sys.symbol.gearshape'))
            .fontSize(22)
            .fontColor([Theme.textPrimary])
        }
        .width(44)
        .height(44)
        .borderRadius(22)
        .backgroundColor(Theme.cardBg)
        .justifyContent(FlexAlign.Center)
        .shadow({ radius: 8, color: 'rgba(0,0,0,0.08)', offsetY: 2 })
        .onClick(() => {
          router.pushUrl({ url: 'pages/Settings' });
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: 16, right: 16, top: this.topAvoid + 10, bottom: 12 })

      Scroll() {
        Column({ space: 12 }) {
          // 概览卡片
          Row({ space: 14 }) {
            SymbolGlyph($r('sys.symbol.folder'))
              .fontSize(30)
              .fontColor([Theme.accent])
            Column({ space: 3 }) {
              Text(`${this.savedCount}`)
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.textPrimary)
              Text('已保存作品 · 在首页收藏中查看')
                .fontSize(12)
                .fontColor(Theme.textSecondary)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .width('100%')
          .padding(16)
          .borderRadius(18)
          .backgroundColor(Theme.cardBg)

          // 功能列表卡片
          Column() {
            MineRow({
              symbol: $r('sys.symbol.gearshape'),
              title: '设置',
              desc: '下载、命名、会话等偏好',
              onTap: (): void => {
                router.pushUrl({ url: 'pages/Settings' });
              }
            })
            Divider().color(Theme.pageBg).margin({ left: 66 })
            MineRow({
              symbol: $r('sys.symbol.clock'),
              title: '下载历史',
              desc: '解析与下载记录',
              onTap: (): void => {
                router.pushUrl({ url: 'pages/History' });
              }
            })
            Divider().color(Theme.pageBg).margin({ left: 66 })
            MineRow({
              symbol: $r('sys.symbol.compass'),
              title: '网页登录',
              desc: '登录小红书提升解析成功率',
              onTap: (): void => {
                router.pushUrl({ url: 'pages/WebSession' });
              }
            })
          }
          .width('100%')
          .borderRadius(18)
          .backgroundColor(Theme.cardBg)
          .clip(true)

          Text('收藏 · HarmonyOS')
            .fontSize(11)
            .fontColor(Theme.textSecondary)
            .margin({ top: 8 })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 96, top: 4 })
      }
      .layoutWeight(1)
      .align(Alignment.Top)
    }
    .padding({ left: this.leftAvoid, right: this.rightAvoid })
    .width('100%')
    .height('100%')
  }
}

@Component
struct MineRow {
  symbol: Resource = $r('sys.symbol.gearshape');
  title: string = '';
  desc: string = '';
  onTap: () => void = (): void => {};

  build() {
    Row({ space: 12 }) {
      Row() {
        SymbolGlyph(this.symbol)
          .fontSize(22)
          .fontColor([Theme.textPrimary])
      }
      .width(40)
      .height(40)
      .borderRadius(12)
      .backgroundColor(Theme.pageBg)
      .justifyContent(FlexAlign.Center)
      Column({ space: 2 }) {
        Text(this.title)
          .fontSize(15)
          .fontColor(Theme.textPrimary)
        Text(this.desc)
          .fontSize(12)
          .fontColor(Theme.textSecondary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([Theme.textSecondary])
    }
    .width('100%')
    .padding(14)
    .onClick(() => {
      this.onTap();
    })
  }
}
