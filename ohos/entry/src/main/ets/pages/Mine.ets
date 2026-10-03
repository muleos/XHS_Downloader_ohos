/**
 * 我的：VHome 风格 —— 大标题 + 圆形设置按钮 + 圆角卡片功能列表。
 * 检查更新：移植安卓 GitHubUpdateRepository（GitHub Releases latest 比对版本号）。
 */
import { router, SymbolGlyphModifier } from '@kit.ArkUI';
import { HdsNavigation, HdsNavigationTitleMode, HdsNavigationMenuContentOptions,
  HdsNavigationMenuItemOptions } from '@kit.UIDesignKit';
import { bundleManager, common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { AppContainer } from '../data/AppContainer';
import { WebAccount } from '../data/WebAccount';
import { NetProxy } from '../service/PlatformServices';
import { frostTitleBarStyle } from '../view/FrostScaffold';
import { Theme, toast } from '../view/Common';

const RELEASES_URL: string = 'https://github.com/muleos/XHS_Downloader_ohos/releases/latest';
const RELEASES_API: string = 'https://api.github.com/repos/muleos/XHS_Downloader_ohos/releases/latest';
const REPO_URL: string = 'https://github.com/muleos/XHS_Downloader_ohos';

@Component
export struct MinePage {
  @StorageLink('topAvoid') topAvoid: number = 0;
  @StorageLink('bottomAvoid') bottomAvoid: number = 0;
  @StorageLink('leftAvoid') leftAvoid: number = 0;
  @StorageLink('rightAvoid') rightAvoid: number = 0;
  @State savedCount: number = 0;
  @State updateDesc: string = '检查 GitHub Releases 新版本';
  @StorageLink('savedVersion') @Watch('onSavedChanged') savedVersion: number = 0;
  /** 小红书账号登录状态（网页会话注入；安卓 WebAccountCard 同款展示） */
  @State account: WebAccount | null = null;
  /** 主滚动容器控制器（HdsNavigation bindToScrollable 官方滚动源绑定） */
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.savedCount = AppContainer.get().saved.getAll().length;
    this.account = AppContainer.get().webAccount.get();
    AppContainer.get().webAccount.onChange((a: WebAccount | null): void => {
      this.account = a;
    });
  }

  onSavedChanged(): void {
    this.savedCount = AppContainer.get().saved.getAll().length;
  }

  private currentVersion(): string {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      return info.versionName;
    } catch (e) {
      return '';
    }
  }

  /** 走设置里配置的代理拉取 latest release 版本号；拿不到返回空串 */
  private async fetchLatestVersion(): Promise<string> {
    let req: http.HttpRequest | null = null;
    try {
      req = http.createHttp();
      const header: Record<string, string> = {
        'User-Agent': 'collection-app/1.0',
        'Accept': 'application/vnd.github+json'
      };
      const opt: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: header,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 10000,
        readTimeout: 15000
      };
      if (NetProxy.host.length > 0 && NetProxy.port > 0) {
        opt.usingProxy = { host: NetProxy.host, port: NetProxy.port, exclusionList: [] } as http.HttpProxy;
      }
      const resp = await req.request(RELEASES_API, opt);
      req.destroy();
      if (resp.responseCode !== 200) {
        return '';
      }
      const tag = (JSON.parse(resp.result as string) as Record<string, Object>)['tag_name'];
      const v = typeof tag === 'string' ? tag.replace(/^v/i, '').trim() : '';
      return v;
    } catch (e) {
      if (req !== null) {
        req.destroy();
      }
      return '';
    }
  }

  private isNewer(remote: string, local: string): boolean {
    const a = remote.split('.').map((x: string): number => Number(x) || 0);
    const b = local.split('.').map((x: string): number => Number(x) || 0);
    for (let i = 0; i < 3; i++) {
      const av = a[i] !== undefined ? a[i] : 0;
      const bv = b[i] !== undefined ? b[i] : 0;
      if (av !== bv) {
        return av > bv;
      }
    }
    return false;
  }

  private async checkUpdate(): Promise<void> {
    const local = this.currentVersion();
    this.updateDesc = '检查中…';
    const latest = await this.fetchLatestVersion();
    if (latest.length === 0) {
      this.updateDesc = '暂时无法获取（GitHub 需代理）';
      toast('获取更新信息失败：可在设置 → 网络配置代理后重试');
      return;
    }
    if (this.isNewer(latest, local)) {
      this.updateDesc = `发现新版本 v${latest}`;
      toast(`发现新版本 v${latest}（当前 v${local}），正在打开发布页…`);
      this.openRelease();
    } else {
      this.updateDesc = `已是最新版本 v${local}`;
      toast(`已是最新版本 v${local}`);
    }
  }

  private openRelease(): void {
    this.openUrl(RELEASES_URL);
  }

  /** 系统浏览器打开链接（GitHub 仓库直达 / 发布页共用） */
  private openUrl(url: string): void {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      ctx.openLink(url, { appLinkingOnly: false });
    } catch (e) {
      toast('请用浏览器打开：' + url);
    }
  }

  /** 顶栏 menu：设置入口（与收藏页官方 menu 槽位同款沉浸光感） */
  private menuOptions(): HdsNavigationMenuContentOptions {
    const gearIcon: SymbolGlyphModifier = new SymbolGlyphModifier($r('sys.symbol.gearshape'));
    gearIcon.fontColor([Theme.textPrimary]);
    const items: HdsNavigationMenuItemOptions[] = [
      {
        content: {
          icon: gearIcon,
          action: (): void => {
            router.pushUrl({ url: 'pages/Settings' });
          }
        }
      }
    ];
    return { value: items };
  }

  build() {
    // 与收藏/解析页同款官方顶栏：HdsNavigation MINI + frost 四件套，
    // 三个一级页面顶栏高度与水平对齐统一；设置按钮进官方 menu 槽位。
    HdsNavigation() {
      Scroll(this.scroller) {
        Column({ space: 12 }) {
          // 小红书账号登录状态卡（安卓 WebAccountCard 一比一）：
          // 圆形头像（远程头像优先）+ 昵称 / 未登录 + 点击进入网页登录
          Row({ space: 14 }) {
            Stack() {
              if (this.account !== null && this.account.avatar.length > 0) {
                Image(this.account.avatar)
                  .width(48)
                  .height(48)
                  .borderRadius(24)
                  .objectFit(ImageFit.Cover)
              } else {
                SymbolGlyph($r('sys.symbol.person_crop_circle_fill_1'))
                  .fontSize(26)
                  .fontColor(['#FFFFFF'])
              }
            }
            .width(48)
            .height(48)
            .borderRadius(24)
            .backgroundColor(Theme.accent)
            .clip(true)

            Column({ space: 3 }) {
              Text(this.account !== null && this.account.nickname.length > 0 ?
                this.account.nickname : '小红书账号')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.textPrimary)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.account !== null ? '已登录 · 点击管理会话' : '未登录 · 点击登录提升解析成功率')
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
          .padding(16)
          .borderRadius(18)
          .backgroundColor(Theme.cardBg)
          .onClick(() => {
            router.pushUrl({ url: 'pages/WebSession' });
          })

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
            Divider().color(Theme.pageBg).margin({ left: 66 })
            MineRow({
              symbol: $r('sys.symbol.link'),
              title: 'GitHub 仓库',
              desc: 'muleos/XHS_Downloader_ohos',
              onTap: (): void => {
                this.openUrl(REPO_URL);
              }
            })
            Divider().color(Theme.pageBg).margin({ left: 66 })
            MineRow({
              symbol: $r('sys.symbol.arrow_down_circle'),
              title: '检查更新',
              desc: this.updateDesc,
              onTap: (): void => {
                this.checkUpdate();
              }
            })
          }
          .width('100%')
          .borderRadius(18)
          .backgroundColor(Theme.cardBg)
          .clip(true)

          // 应用内版本号（bundleManager 实读，随安装包版本变化）
          Text(`收藏 v${this.currentVersion()} · HarmonyOS`)
            .fontSize(11)
            .fontColor(Theme.textSecondary)
            .margin({ top: 8 })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 96, top: this.topAvoid + 88 })
      }
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .align(Alignment.Top)
      .layoutWeight(1)
      .width('100%')
      .height('100%')
    }
    .titleBar({
      avoidLayoutSafeArea: true,
      content: {
        title: { mainTitle: '我的', subTitle: `${this.savedCount} 个已保存作品` },
        menu: this.menuOptions()
      },
      style: frostTitleBarStyle(Theme.pageBg, Theme.textPrimary, Theme.textSecondary)
    })
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(true)
    .bindToScrollable([this.scroller])
    .padding({ left: this.leftAvoid, right: this.rightAvoid })
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
  }
}

@Component
struct MineRow {
  symbol: Resource = $r('sys.symbol.gearshape');
  /** 数据字段 @Prop：父组件状态变化时实时同步（普通成员只在创建时赋值一次） */
  @Prop title: string = '';
  @Prop desc: string = '';
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
