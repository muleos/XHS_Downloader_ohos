/**
 * VHome FrostScaffold 一比一移植（weibopura 官方四件套配方）。
 *
 * 根因（VHome P27 记录）：官方沉浸光感材质只在 Navigation/NavDestination
 * 标题栏与底部 TabBar 两个白名单槽位渲染；自绘 Column 的
 * backgroundColor + backgroundBlurStyle 叠加会出现「背景重叠 / 灰色遮罩」，
 * 且永远拿不到官方材质。
 *
 * 四件套：
 *  1. scrollEffectOpts   —— IMMERSIVE_GRADIENT_BLUR 滚动渐变模糊；
 *  2. originalStyle      —— 未滚动时全透明；
 *  3. scrollEffectStyle  —— 滚动后过渡到页面底色；
 *  4. systemMaterialEffect —— IMMERSIVE/ADAPTIVE 官方材质。
 * 配合 bindToScrollable 绑定页面滚动源。
 */
import { hdsMaterial, HdsNavigation, HdsNavigationTitleMode, ScrollEffectType,
  TitleBarStyleOptions, HdsTitleBarContentStyle } from '@kit.UIDesignKit';
import { Theme } from './Common';

/** VHome frostTitleBarStyle 同款：官方材质 + 文字/返回键染色 */
export function frostTitleBarStyle(bgColor: ResourceColor, mainColor: ResourceColor, subColor: ResourceColor): TitleBarStyleOptions {
  const contentStyle: HdsTitleBarContentStyle = {
    titleStyle: { mainTitleColor: mainColor, subTitleColor: subColor },
    backIconStyle: { iconColor: mainColor },
    subIconStyle: { iconColor: mainColor },
    menuStyle: { iconColor: mainColor }
  };
  const style: TitleBarStyleOptions = {
    originalStyle: {
      backgroundStyle: { backgroundColor: Color.Transparent },
      contentStyle: contentStyle
    },
    scrollEffectStyle: {
      backgroundStyle: { backgroundColor: bgColor },
      contentStyle: contentStyle
    },
    scrollEffectOpts: {
      enableScrollEffect: true,
      scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR
    },
    systemMaterialEffect: {
      materialType: hdsMaterial.MaterialType.IMMERSIVE,
      materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
    }
  };
  return style;
}

@Component
export struct FrostScaffold {
  @Prop title: string = '';
  /** 页面主滚动容器控制器（官方滚动源绑定） */
  scroller: Scroller = new Scroller();
  bgColor: ResourceColor = Theme.pageBg;

  @BuilderParam
  content: () => void = this.emptyContent;

  @Builder
  emptyContent() {
  }

  build() {
    HdsNavigation() {
      Stack() {
        this.content()
      }
      .width('100%')
      .height('100%')
      .alignContent(Alignment.Top)
    }
    .titleBar({
      avoidLayoutSafeArea: true,
      content: {
        title: { mainTitle: this.title }
      },
      style: frostTitleBarStyle(this.bgColor, Theme.textPrimary, Theme.textSecondary)
    })
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(false)
    .bindToScrollable([this.scroller])
    .width('100%')
    .height('100%')
    .backgroundColor(this.bgColor)
    // bgColor 延伸到状态栏/小白条后面（VHome MainTab 同款 TOP+BOTTOM）
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
