/**
 * 主入口：首页 / 解析 / 我的 三个一级 Tab。
 *
 * 底栏一比一移植 VHome MainTab.hdsShell：系统官方悬浮岛 HdsTabs
 * （@kit.UIDesignKit）—— 自带沉浸光感材质、实时模糊、按设备自适应调档，
 * barFloatingStyle 悬浮造型（weibopura 同款：高 56 / 底距 28 / lightColor 主题色）。
 * 页签图标官方 SymbolGlyph 两态染色（未选中黑 / 选中主题色 #4169E1）。
 * 查看器打开时底栏整体隐藏（barOpacity 0 modifier 换装）；系统返回先关查看器，不退出应用。
 */
import { SymbolGlyphModifier } from '@kit.ArkUI';
import { HdsTabs, HdsTabsController, HdsTabsModifier, hdsMaterial } from '@kit.UIDesignKit';
import { Theme } from '../view/Common';
import { HomePage, ViewerHost } from './Home';
import { ParsePage } from './Parse';
import { MinePage } from './Mine';

const TAB_COUNT: number = 3;
const BAR_HEIGHT: number = 56;
const BAR_BOTTOM_MARGIN: number = 28;

const TAB_LABEL: string[] = ['首页', '解析', '我的'];
/** 两态同资源（fill 形态），未选中黑 / 选中主题色（VHome 同款策略） */
const TAB_ICON: Resource[] = [
  $r('sys.symbol.house_fill'),
  $r('sys.symbol.link'),
  $r('sys.symbol.person_crop_circle_fill_1')
];

@Entry
@Component
struct Index {
  @StorageLink('viewerIndex') viewerIndex: number = -1;
  @StorageLink('bottomAvoid') bottomAvoid: number = 0;
  @State currentTab: number = 0;
  /** 其它页面的切页请求（首页解析圆钮 → 解析页），-1 表示无请求 */
  @StorageProp('tabRequest') @Watch('onTabRequest') tabRequest: number = -1;
  /** 三个页签的样式对象（主题色变化时整体重建） */
  @State tabBars: BottomTabBarStyle[] = [];
  private controller: HdsTabsController = new HdsTabsController();
  /** 官方悬浮岛样式 modifier（实例不可变，换样式必须整体换新实例） */
  @State hdsTabsModifier: HdsTabsModifier = new HdsTabsModifier();
  /** 查看器打开时的隐藏岛 modifier（barOpacity 0，岛整体消失不留残壳） */
  @State hdsTabsHiddenModifier: HdsTabsModifier = new HdsTabsModifier();

  aboutToAppear(): void {
    this.rebuildTabBars();
    this.configureHdsTabs();
  }

  /** 系统返回键/侧滑：查看器打开时先关闭查看器。 */
  onBackPress(): boolean {
    if (this.viewerIndex >= 0) {
      this.viewerIndex = -1;
      return true;
    }
    return false;
  }

  /** 收到其它页面的切页请求（VHome 同款：先复位再执行，避免 @Watch 不递归触发） */
  onTabRequest(): void {
    const target: number = this.tabRequest;
    AppStorage.setOrCreate<number>('tabRequest', -1);
    if (target < 0 || target >= TAB_COUNT) {
      return;
    }
    this.controller.changeIndex(target);
  }

  /** 生成一枚着色的符号 modifier（先建后调，避免链式返回基类过不了严格检查） */
  private tintModifier(src: Resource, color: ResourceColor): SymbolGlyphModifier {
    const modifier: SymbolGlyphModifier = new SymbolGlyphModifier(src);
    modifier.fontColor([color]);
    return modifier;
  }

  private rebuildTabBars(): void {
    const list: BottomTabBarStyle[] = [];
    for (let i = 0; i < TAB_COUNT; i++) {
      const symbol: TabBarSymbol = {
        normal: this.tintModifier(TAB_ICON[i], $r('app.color.tab_normal')),
        selected: this.tintModifier(TAB_ICON[i], Theme.accent)
      };
      list.push(BottomTabBarStyle.of(symbol, TAB_LABEL[i])
        .labelStyle({
          unselectedColor: $r('sys.color.font_primary'),
          selectedColor: Theme.accent
        })
        .padding({ bottom: 0 }));
    }
    this.tabBars = list;
  }

  /** 官方悬浮岛样式（VHome configureHdsTabs 一比一）：IMMERSIVE 材质 + 精致档自适应。
   *  v1.14.0：查看器打开时岛不能只压 barHeight（胶囊壳仍画在内容之上，图片
   *  详情页底部露白条）——官方隐藏方式是换用 barOpacity 0 的 modifier 整体透明。 */
  private configureHdsTabs(): void {
    this.hdsTabsModifier = this.buildTabsModifier(1);
    this.hdsTabsHiddenModifier = this.buildTabsModifier(0);
  }

  private buildTabsModifier(opacity: number): HdsTabsModifier {
    const modifier: HdsTabsModifier = new HdsTabsModifier();
    modifier
      .vertical(false)
      .barPosition(BarPosition.End)
      .barFloatingStyle({
        adaptToHandedness: true,
        barBottomMargin: BAR_BOTTOM_MARGIN,
        lightColor: Theme.accent,
        barOpacity: opacity,
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: hdsMaterial.MaterialLevel.EXQUISITE
        }
      });
    return modifier;
  }

  build() {
    Stack() {
      // ── 沉浸光感背景层：主题蓝环境光晕（左主 / 右辅），透过透明 Tabs 透出 ──
      Column()
        .width(620)
        .height(480)
        .radialGradient({
          center: ['50%', '50%'],
          radius: 310,
          colors: [['rgba(65,105,225,0.10)', 0], ['rgba(65,105,225,0)', 1]]
        })
        .position({ x: '-16%', y: -170 })
        .hitTestBehavior(HitTestMode.None)

      Column()
        .width(540)
        .height(420)
        .radialGradient({
          center: ['50%', '50%'],
          radius: 270,
          colors: [['rgba(100,149,237,0.08)', 0], ['rgba(100,149,237,0)', 1]]
        })
        .position({ x: '62%', y: -150 })
        .hitTestBehavior(HitTestMode.None)

      // ── 系统官方悬浮岛底栏（HdsTabs 一比一 VHome hdsShell）──
      HdsTabs({ controller: this.controller }) {
        TabContent() {
          HomePage()
        }
        .backgroundColor(Color.Transparent)
        .tabBar(this.tabBars[0])

        TabContent() {
          ParsePage()
        }
        .backgroundColor(Color.Transparent)
        .tabBar(this.tabBars[1])

        TabContent() {
          MinePage()
        }
        .backgroundColor(Color.Transparent)
        .tabBar(this.tabBars[2])
      }
      .barPosition(BarPosition.End)
      .barOverlap(true)
      .scrollable(true)
      .animationDuration(0)
      // 查看器打开时收起底栏：岛整体透明（barOpacity 0）+ barHeight 收缩
      .barHeight(this.viewerIndex >= 0 ? 0 : BAR_HEIGHT)
      .attributeModifier(this.viewerIndex >= 0 ? this.hdsTabsHiddenModifier : this.hdsTabsModifier)
      .backgroundColor(Color.Transparent)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .onChange((index: number) => {
        this.currentTab = index;
      })

      // ── 全窗查看器（v1.19.0 重构）：挂在 Index 根 Stack、盖住 HdsTabs，
      // 彻底脱离 HdsNavigation 内容裁剪——底部小白条区域白条根治 ──
      ViewerHost()
    }
    .width('100%')
    .height('100%')
    // v1.16.0：查看器打开时根背景切黑——MediaViewer 叠在 HdsNavigation 内部，
    // expandSafeArea 会被内容裁剪拦住，底部小白条区域盖不到，漏出 pageBg 白条；
    // VHome 查看器是独立 router 页不存在此问题，这里从最底层兜底同效全黑。
    .backgroundColor(this.viewerIndex >= 0 ? '#000000' : Theme.pageBg)
  }
}
