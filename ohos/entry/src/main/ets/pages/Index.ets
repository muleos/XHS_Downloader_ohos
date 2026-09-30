/**
 * 主入口：首页(媒体库瀑布流) / 解析 / 我的 三 Tab，
 * 底部悬浮胶囊导航 + 顶部标题栏（参照 VHome UI）。
 */
import { AppContainer } from '../data/AppContainer';
import { Theme, toast } from '../view/Common';
import { HomePage } from './Home';
import { ParsePage } from './Parse';
import { MinePage } from './Mine';

@Entry
@Component
struct Index {
  @StorageLink('topAvoid') topAvoid: number = 0;
  @StorageLink('bottomAvoid') bottomAvoid: number = 0;
  @StorageLink('leftAvoid') leftAvoid: number = 0;
  @StorageLink('rightAvoid') rightAvoid: number = 0;
  @State currentTab: number = 0;

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 内容层：三个 Tab 页保持挂载，仅切换可见性
      Stack() {
        Column() {
          HomePage()
        }
        .width('100%')
        .height('100%')
        .visibility(this.currentTab === 0 ? Visibility.Visible : Visibility.None)

        Column() {
          ParsePage()
        }
        .width('100%')
        .height('100%')
        .visibility(this.currentTab === 1 ? Visibility.Visible : Visibility.None)

        Column() {
          MinePage()
        }
        .width('100%')
        .height('100%')
        .visibility(this.currentTab === 2 ? Visibility.Visible : Visibility.None)
      }
      .width('100%')
      .height('100%')

      // 底部悬浮胶囊导航（VHome 复刻：白色胶囊 + 阴影，
      // 选中项蓝色图标+蓝色文字，未选中黑色图标，规范热区 ≥48）
      Row() {
        NavItem({
          commands: NavIcons.HOME,
          label: '首页',
          active: this.currentTab === 0,
          onTap: (): void => {
            this.currentTab = 0;
          }
        })
        NavItem({
          commands: NavIcons.PARSE,
          label: '解析',
          active: this.currentTab === 1,
          onTap: (): void => {
            this.currentTab = 1;
          }
        })
        NavItem({
          commands: NavIcons.MINE,
          label: '我的',
          active: this.currentTab === 2,
          onTap: (): void => {
            this.currentTab = 2;
          }
        })
      }
      .width('70%')
      .height(60)
      .borderRadius(30)
      .backgroundColor('#FFFFFF')
      .shadow({ radius: 24, color: 'rgba(15,23,42,0.14)', offsetY: 6 })
      .justifyContent(FlexAlign.SpaceAround)
      .margin({ bottom: 28 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.pageBg)
  }
}

/**
 * 底部页签矢量图标：24×24 描边网格，符合鸿蒙规范
 * （图标 24、字号 10fp、触控热区 ≥48）。
 */
export class NavIcons {
  static readonly HOME: string =
    'M4 10.5 L12 3.8 L20 10.5 V20 H4 Z M9.5 20 V14 H14.5 V20';
  static readonly PARSE: string =
    'M9.5 17.5 H7 A4.5 4.5 0 0 1 7 8.5 H9.5 M14.5 8.5 H17 A4.5 4.5 0 0 1 17 17.5 H14.5 M8.5 13 H15.5';
  static readonly MINE: string =
    'M12 3 A4 4 0 1 0 12 11 A4 4 0 1 0 12 3 Z M4.5 21 V20 A5 5 0 0 1 9.5 15 H14.5 A5 5 0 0 1 19.5 20 V21';
}

@Component
struct NavItem {
  commands: string = '';
  label: string = '';
  active: boolean = false;
  onTap: () => void = (): void => {};

  build() {
    Column({ space: 3 }) {
      Path()
        .commands(this.commands)
        .width(24)
        .height(24)
        .fill(Color.Transparent)
        .stroke(this.active ? Theme.blue : '#262626')
        .strokeWidth(this.active ? 2.2 : 1.9)
        .strokeLineCap(LineCapStyle.Round)
        .strokeLineJoin(LineJoinStyle.Round)
      Text(this.label)
        .fontSize(10)
        .fontWeight(this.active ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.active ? Theme.blue : '#262626')
    }
    .width(64)
    .height(52)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.onTap();
    })
  }
}
