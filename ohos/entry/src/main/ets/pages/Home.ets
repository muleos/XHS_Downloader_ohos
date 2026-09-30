/**
 * 首页：已保存媒体的瀑布流信息流（参照小红书双列瀑布流）。
 *
 * v1.5.0 重做（根因修复）：
 *   - 瀑布流重叠根因：旧版卡片先以兜底高度渲染、图片加载完成后再异步改高度，
 *     WaterFlow 已按初始高度完成布局 → 内容溢出相互重叠。
 *     改为进入页面先用 image.getImageInfo 预测量全部封面宽高比，
 *     渲染时直接给定最终高度（aspectRatio），布局一次到位不再二次测量。
 *   - 卡片样式对齐小红书：圆角封面 + 两行标题 + 平台红标 + 作者行。
 *   - 查看器一比一移植 VHome ImageViewer（P53 WeiboPura 配方）：
 *     图片节点常驻、缩放/平移只改属性；手势挂独立透明层；
 *     未放大态不挂 Pan（水平滑动完全让给 Swiper 翻页）；
 *     放大态 disableSwipe + Pan 拖动，钳制边界 = 视口×(s-1)/2。
 */
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { router, window, promptAction, SymbolGlyphModifier } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { HdsNavigation, HdsNavigationTitleMode, HdsNavigationMenuContentOptions,
  HdsNavigationMenuItemOptions } from '@kit.UIDesignKit';
import { AppContainer } from '../data/AppContainer';
import { SavedItem, WorkType, Platform, platformName } from '../model/SaveModels';
import { MediaParser } from '../service/PlatformServices';
import { MediaSaver, FolderSaveRequest } from '../data/MediaSaver';
import { frostTitleBarStyle } from '../view/FrostScaffold';
import { Theme, toast } from '../view/Common';

/** 低于该倍率视为「未放大」，收拢回 1x 并恢复 Swiper 滑动（VHome 同款阈值） */
const ZOOMED_THRESHOLD: number = 1.05;
const MAX_SCALE: number = 4;

@Builder
export function HomePageBuilder() {
  HomePage()
}

@Component
export struct HomePage {
  @StorageLink('topAvoid') topAvoid: number = 0;
  @StorageLink('bottomAvoid') bottomAvoid: number = 0;
  @StorageLink('leftAvoid') leftAvoid: number = 0;
  @StorageLink('rightAvoid') rightAvoid: number = 0;
  @State items: SavedItem[] = [];
  /** 封面高宽比（item.id → h/w），渲染前预测量 */
  @State ratios: Record<string, number> = {};
  /** 双列瀑布：短列优先分配后的左右两列（确定性布局，替代 WaterFlow 自动布局） */
  @State leftItems: SavedItem[] = [];
  @State rightItems: SavedItem[] = [];
  // 写入 AppStorage：Index 据此在查看器打开时隐藏底部导航
  @StorageLink('viewerIndex') viewerIndex: number = -1;
  @State confirmDelete: boolean = false;
  @State saving: boolean = false;
  @StorageLink('savedVersion') @Watch('onSavedChanged') savedVersion: number = 0;

  /** 主滚动容器控制器（HdsNavigation bindToScrollable 官方滚动源绑定） */
  private feedScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.reload();
  }

  onSavedChanged(): void {
    this.reload();
  }

  reload(): void {
    const all = AppContainer.get().saved.getAll();
    // 按源链接去重（保留最新一次保存）——重复解析同一作品不再出现双卡
    const seen: Record<string, number> = {};
    const deduped: SavedItem[] = [];
    for (const it of all) {
      const key = it.sourceUrl.length > 0 ? it.sourceUrl : it.id;
      const prev = seen[key];
      if (prev === undefined) {
        seen[key] = deduped.length;
        deduped.push(it);
      } else if (it.createTime > deduped[prev].createTime) {
        deduped[prev] = it;
      }
    }
    this.items = deduped;
    this.splitColumns();
    this.measureRatios();
  }

  /** 卡片按图片实际比例展示；未测量到时走竖向 3:4 兜底（信息流竖排） */
  private clampRatio(item: SavedItem): number {
    const r = this.ratios[item.id];
    return r === undefined ? 4 / 3 : r;
  }

  /**
   * 双列瀑布分配：按「图片比例 + 文本区近似高」估卡片总高，短列优先放入。
   * 确定性布局——不依赖 WaterFlow 的自动摆放，杜绝跨列/重叠。
   */
  private splitColumns(): void {
    const left: SavedItem[] = [];
    const right: SavedItem[] = [];
    let lh = 0;
    let rh = 0;
    for (const it of this.items) {
      // 文本区（两行标题 + 作者行 + 内边距）≈ 0.45 倍列宽
      const h = this.clampRatio(it) + 0.45;
      if (lh <= rh) {
        left.push(it);
        lh += h;
      } else {
        right.push(it);
        rh += h;
      }
    }
    this.leftItems = left;
    this.rightItems = right;
  }

  private fileUri(path: string): string {
    if (path.startsWith('file://') || path.startsWith('http')) {
      return path;
    }
    return 'file://' + path;
  }

  /** 预测量全部封面宽高比：入库尺寸优先 → 图片实测 → 视频/失败走竖向 3:4 */
  private async measureRatios(): Promise<void> {
    const map: Record<string, number> = {};
    for (const item of this.items) {
      // 解析入库时记录的原始尺寸优先（最准）
      if (item.width > 0 && item.height > 0) {
        map[item.id] = item.height / item.width;
        continue;
      }
      const p: string = item.coverOrFirst();
      // 视频无封面或无法测量：竖向 3:4 兜底（信息流竖排）
      if (p.length === 0 || p.endsWith('.mp4')) {
        map[item.id] = 4 / 3;
        continue;
      }
      try {
        const src: image.ImageSource = image.createImageSource(this.fileUri(p));
        const info: image.ImageInfo = await src.getImageInfo();
        if (info && info.size.width > 0 && info.size.height > 0) {
          map[item.id] = info.size.height / info.size.width;
        } else {
          map[item.id] = 4 / 3;
        }
        src.release().catch((): void => {
        });
      } catch (e) {
        map[item.id] = 4 / 3;
      }
    }
    this.ratios = map;
    // 比例测量完成后重排双列
    this.splitColumns();
  }

  private ratioOf(item: SavedItem): number {
    const r = this.ratios[item.id];
    return r === undefined ? 0 : r;
  }

  /** 打开查看器（瀑布流卡片点击入口） */
  private openItem(item: SavedItem): void {
    if (!item.hasMedia()) {
      toast('该作品没有可查看的文件');
      return;
    }
    this.viewerIndex = this.items.indexOf(item);
    this.confirmDelete = false;
  }

  /**
   * 首页解析圆钮：自动识别剪贴板里的分享链接。
   * 有链接 → 解析页直接开始解析；无链接 → 切到解析页供手动粘贴。
   * 剪贴板读GetDataSync 在部分机型/权限态下静默失败，改为异步 getData 优先 + 同步兜底。
   */
  private quickParse(): void {
    this.readClipboardAndParse();
  }

  private async readClipboardAndParse(): Promise<void> {
    let text = '';
    try {
      const data = await pasteboard.getSystemPasteboard().getData();
      text = data.getPrimaryText() ?? '';
    } catch (e) {
      try {
        text = pasteboard.getSystemPasteboard().getDataSync().getPrimaryText() ?? '';
      } catch (err) {
        text = '';
      }
    }
    if (text.trim().length === 0) {
      toast('剪贴板为空，请先在小红书等 App 复制分享链接');
      AppStorage.setOrCreate<number>('tabRequest', 1);
      return;
    }
    if (MediaParser.firstSupportedLink(text).length > 0) {
      // 先写解析请求（解析页挂载/@Watch 消费），再请求切页
      AppStorage.setOrCreate<string>('parseRequest', text);
      toast('已识别链接，开始解析…');
    } else {
      toast('剪贴板未识别到支持的链接，可在解析页手动粘贴');
    }
    AppStorage.setOrCreate<number>('tabRequest', 1);
  }

  private async saveCurrent(): Promise<void> {
    if (this.viewerIndex < 0 || this.viewerIndex >= this.items.length) {
      return;
    }
    const item = this.items[this.viewerIndex];
    const files: FolderSaveRequest[] = [];
    for (const p of item.mediaPaths) {
      const f = new FolderSaveRequest();
      f.path = p;
      const slash = p.lastIndexOf('/');
      const dot = p.lastIndexOf('.');
      const ext = dot > slash ? p.substring(dot + 1) : 'jpg';
      f.name = item.id + '_' + files.length + '.' + ext;
      files.push(f);
    }
    this.saving = true;
    try {
      const saved = await MediaSaver.storeGalleryBatch(getContext(this), files);
      if (saved > 0) {
        toast(`已保存 ${saved} 个文件到相册`);
      } else {
        toast('已取消保存');
      }
    } catch (e) {
      toast('保存失败：' + (e instanceof Error ? e.message : String(e)));
    } finally {
      this.saving = false;
    }
  }

  private deleteCurrent(): void {
    if (this.viewerIndex < 0 || this.viewerIndex >= this.items.length) {
      return;
    }
    const item = this.items[this.viewerIndex];
    if (!this.confirmDelete) {
      this.confirmDelete = true;
      return;
    }
    for (const p of item.mediaPaths) {
      try {
        if (fileIo.accessSync(p)) {
          fileIo.unlinkSync(p);
        }
      } catch (e) {
      }
    }
    AppContainer.get().saved.remove(item.id);
    this.confirmDelete = false;
    this.viewerIndex = -1;
    this.reload();
    toast('已删除');
  }

  /** 官方 menu 槽位：解析 + 设置（symbol 须 modifier 显式染色，VHome P122 实锤） */
  private menuOptions(): HdsNavigationMenuContentOptions {
    const linkIcon: SymbolGlyphModifier = new SymbolGlyphModifier($r('sys.symbol.link'));
    linkIcon.fontColor([Theme.textPrimary]);
    const gearIcon: SymbolGlyphModifier = new SymbolGlyphModifier($r('sys.symbol.gearshape'));
    gearIcon.fontColor([Theme.textPrimary]);
    const items: HdsNavigationMenuItemOptions[] = [
      {
        content: {
          icon: linkIcon,
          action: (): void => {
            this.quickParse();
          }
        }
      },
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
    // VHome DiscoverTab 同款官方顶栏骨架：HdsNavigation MINI +
    // frostTitleBarStyle 四件套（未滚动全透明 / 滚动渐变模糊 / 官方沉浸材质），
    // 信息流从标题栏后穿透，bindToScrollable 绑定主滚动源。
    HdsNavigation() {
      Stack({ alignContent: Alignment.Top }) {
        // ── 内容层：全高滚动，顶部延伸到顶栏后面（沉浸穿透）──
        if (this.items.length === 0) {
          Column({ space: 10 }) {
            SymbolGlyph($r('sys.symbol.inbox'))
              .fontSize(52)
              .fontColor([Theme.textSecondary])
            Text('还没有保存的作品')
              .fontSize(15)
              .fontColor(Theme.textSecondary)
            Text('到「解析」页粘贴分享链接试试')
              .fontSize(13)
              .fontColor(Theme.textSecondary)
          }
          .width('100%')
          .margin({ top: this.topAvoid + 130 })
        } else {
          // 双列瀑布（Pura 系列表风格）：短列优先分配 + 确定性双列布局
          Scroll(this.feedScroller) {
            Row({ space: 8 }) {
              Column({ space: 8 }) {
                ForEach(this.leftItems, (item: SavedItem) => {
                  FeedCard({
                    item: item,
                    ratio: this.clampRatio(item),
                    onOpen: (): void => {
                      this.openItem(item);
                    }
                  })
                }, (item: SavedItem) => 'l_' + item.id)
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              Column({ space: 8 }) {
                ForEach(this.rightItems, (item: SavedItem) => {
                  FeedCard({
                    item: item,
                    ratio: this.clampRatio(item),
                    onOpen: (): void => {
                      this.openItem(item);
                    }
                  })
                }, (item: SavedItem) => 'r_' + item.id)
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
            .padding({ left: 12, right: 12, top: this.topAvoid + 88, bottom: 120 })
          }
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .align(Alignment.Top)
          .width('100%')
          .height('100%')
        }

        // 全屏查看器（打开时隐藏标题栏）
        if (this.viewerIndex >= 0 && this.viewerIndex < this.items.length) {
          MediaViewer({
            item: this.items[this.viewerIndex],
            confirmDelete: this.confirmDelete,
            onClose: (): void => {
              this.viewerIndex = -1;
              this.confirmDelete = false;
            },
            onSaveAll: (): void => {
              this.saveCurrent();
            },
            onDelete: (): void => {
              this.deleteCurrent();
            }
          })
        }
      }
      .width('100%')
      .height('100%')
      .alignContent(Alignment.Top)
    }
    .titleBar({
      avoidLayoutSafeArea: true,
      content: {
        title: { mainTitle: '收藏', subTitle: `已保存 ${this.items.length} 个作品` },
        menu: this.menuOptions()
      },
      style: frostTitleBarStyle(Theme.pageBg, Theme.textPrimary, Theme.textSecondary)
    })
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(true)
    .hideTitleBar(this.viewerIndex >= 0)
    .bindToScrollable([this.feedScroller])
    .width('100%')
    .height('100%')
    // 根背景保持透明：透出 Index 的沉浸光晕层（项目约定）
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
    .onAppear(() => {
      this.reload();
    })
  }
}

/** 平台应用图标（取自 SaveAny 官方包内素材，96px） */
function badgeRes(p: Platform): Resource {
  if (p === Platform.XHS) {
    return $r('app.media.ic_xhs');
  }
  if (p === Platform.DOUYIN) {
    return $r('app.media.ic_dy');
  }
  if (p === Platform.X) {
    return $r('app.media.ic_x');
  }
  if (p === Platform.INSTAGRAM) {
    return $r('app.media.ic_ig');
  }
  if (p === Platform.TIKTOK) {
    return $r('app.media.ic_tiktok');
  }
  return $r('app.media.ic_xhs');
}

@Component
struct FeedCard {
  item: SavedItem = new SavedItem();
  /** 预测量的封面高宽比（父组件双列分配启发式用，卡片本身按图片真实比例自适应） */
  @Prop ratio: number = 0;
  onOpen: () => void = (): void => {};

  private fileUri(path: string): string {
    if (path.startsWith('file://') || path.startsWith('http')) {
      return path;
    }
    return 'file://' + path;
  }

  build() {
    Column() {
      Stack({ alignContent: Alignment.TopEnd }) {
        if (this.item.coverOrFirst().endsWith('.mp4')) {
          // 视频无封面：竖向 3:4 占位
          Column()
            .width('100%')
            .aspectRatio(3 / 4)
            .backgroundColor('#14000000')
        } else {
          // 图片实际尺寸：只约束宽度，高度由文件真实宽高比自适应（不裁切）
          Image(this.fileUri(this.item.coverOrFirst()))
            .width('100%')
            .constraintSize({ minHeight: 120 })
            .draggable(false)
            .copyOption(CopyOptions.None)
            .objectFit(ImageFit.Contain)
        }
        if (this.item.workType === WorkType.VIDEO) {
          Text('视频')
            .fontSize(10)
            .fontColor('#FFFFFF')
            .backgroundColor('rgba(0,0,0,0.45)')
            .borderRadius(6)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .margin(8)
        }
      }
      .width('100%')

      Column({ space: 4 }) {
        Text(this.item.title.length > 0 ? this.item.title : '未命名作品')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.textPrimary)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Row({ space: 6 }) {
          // 平台应用图标（与原 App 图标一致）
          Image(badgeRes(this.item.platform))
            .width(20)
            .height(20)
            .borderRadius(6)
            .objectFit(ImageFit.Cover)
          Text(this.item.author.length > 0 ? this.item.author : platformName(this.item.platform))
            .fontSize(11)
            .fontColor(Theme.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 10, right: 10, top: 8, bottom: 10 })
    }
    .width('100%')
    .borderRadius(12)
    .backgroundColor(Theme.cardBg)
    .clip(true)
    .onClick(() => {
      this.onOpen();
    })
  }
}

@Component
struct MediaViewer {
  item: SavedItem = new SavedItem();
  confirmDelete: boolean = false;
  onClose: () => void = (): void => {};
  onSaveAll: () => void = (): void => {};
  onDelete: () => void = (): void => {};
  @State current: number = 0;
  /** 当前图的缩放与平移（VHome 同构：仅当前页生效，其余页恒 1x/0 偏移） */
  @State zoomScale: number = 1;
  @State panX: number = 0;
  @State panY: number = 0;
  /** 单击切换顶部/底部操作条显隐（VHome 同款） */
  @State showControls: boolean = true;
  @State saving: boolean = false;
  /** 捏合起点快照（倍率 + 平移 + 双指焦点） */
  private pinchBaseScale: number = 1;
  private pinchBasePanX: number = 0;
  private pinchBasePanY: number = 0;
  private pinchCenterX: number = 0;
  private pinchCenterY: number = 0;
  /** 拖动起点快照（手势累计位移差值法） */
  private panStartX: number = 0;
  private panStartY: number = 0;
  private panBaseX: number = 0;
  private panBaseY: number = 0;
  private dragReady: boolean = false;
  /** 视口尺寸（vp）：onAreaChange 实测（VHome 同款） */
  private viewportWidth: number = 0;
  private viewportHeight: number = 0;
  @StorageLink('topAvoid') topAvoid: number = 0;
  @StorageLink('bottomAvoid') bottomAvoid: number = 0;

  aboutToAppear(): void {
    this.setStatusBarContent(true);
  }

  aboutToDisappear(): void {
    this.setStatusBarContent(false);
  }

  /** 状态栏内容反色：查看器黑底用白色图标，退出恢复深色 */
  private async setStatusBarContent(light: boolean): Promise<void> {
    try {
      const win = await window.getLastWindow(getContext(this) as common.UIAbilityContext);
      await win.setWindowSystemBarProperties({
        statusBarContentColor: light ? '#FFFFFF' : '#000000'
      });
    } catch (e) {
      // 忽略：个别窗口态下设置失败不影响功能
    }
  }

  private fileUri(path: string): string {
    if (path.startsWith('file://') || path.startsWith('http')) {
      return path;
    }
    return 'file://' + path;
  }

  private extOf(path: string): string {
    const dot = path.lastIndexOf('.');
    return dot > path.lastIndexOf('/') ? path.substring(dot + 1).toLowerCase() : 'jpg';
  }

  private isVideoPage(p: string): boolean {
    return this.item.workType === WorkType.VIDEO && p.endsWith('.mp4');
  }

  private getScale(idx: number): number {
    return idx === this.current ? this.zoomScale : 1;
  }

  private getPanX(idx: number): number {
    return idx === this.current ? this.panX : 0;
  }

  private getPanY(idx: number): number {
    return idx === this.current ? this.panY : 0;
  }

  private zoomed(): boolean {
    return this.zoomScale > ZOOMED_THRESHOLD;
  }

  /** 双击缩放（2x，220ms EaseOut；缩回原位平移一并归零，VHome 同款） */
  private toggleZoom(): void {
    if (this.zoomed()) {
      this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, (): void => {
        this.zoomScale = 1;
        this.panX = 0;
        this.panY = 0;
      });
      this.dragReady = false;
    } else {
      this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, (): void => {
        this.zoomScale = 2;
        this.panX = this.clampPanX(this.panX, this.zoomScale);
        this.panY = this.clampPanY(this.panY, this.zoomScale);
      });
    }
  }

  private startPinch(event: GestureEvent): void {
    this.pinchBaseScale = this.zoomScale;
    this.pinchBasePanX = this.panX;
    this.pinchBasePanY = this.panY;
    this.pinchCenterX = Number(event.pinchCenterX);
    this.pinchCenterY = Number(event.pinchCenterY);
  }

  /** 捏合更新：以双指焦点为中心缩放（VHome WeiboPura 同款数学，指缝点跟手） */
  private updatePinch(event: GestureEvent): void {
    const rawScale: number = this.pinchBaseScale * Number(event.scale);
    const nextScale: number = Math.max(1, Math.min(MAX_SCALE, rawScale));
    const centerX: number = Number(event.pinchCenterX);
    const centerY: number = Number(event.pinchCenterY);
    const baseScale: number = Math.max(0.01, this.pinchBaseScale);
    const scaleRatio: number = nextScale / baseScale;
    const baseCenterX: number = this.viewportWidth / 2;
    const baseCenterY: number = this.viewportHeight / 2;
    const contentX: number = (this.pinchBasePanX + this.pinchCenterX - baseCenterX) / baseScale;
    const contentY: number = (this.pinchBasePanY + this.pinchCenterY - baseCenterY) / baseScale;
    const nextPanX: number = (centerX - baseCenterX) - contentX * nextScale;
    const nextPanY: number = (centerY - baseCenterY) - contentY * nextScale;
    this.zoomScale = nextScale;
    this.panX = this.clampPanX(nextPanX, nextScale);
    this.panY = this.clampPanY(nextPanY, nextScale);
  }

  private finishZoom(): void {
    if (this.zoomScale < ZOOMED_THRESHOLD) {
      this.zoomScale = 1;
    }
    if (this.zoomScale === 1) {
      this.panX = 0;
      this.panY = 0;
    } else {
      this.panX = this.clampPanX(this.panX, this.zoomScale);
      this.panY = this.clampPanY(this.panY, this.zoomScale);
    }
  }

  private startPan(event: GestureEvent): void {
    this.panStartX = event.offsetX;
    this.panStartY = event.offsetY;
    this.panBaseX = this.panX;
    this.panBaseY = this.panY;
    this.dragReady = this.zoomScale > ZOOMED_THRESHOLD;
  }

  private updatePan(event: GestureEvent): void {
    if (this.dragReady && this.zoomScale > ZOOMED_THRESHOLD) {
      this.panX = this.clampPanX(this.panBaseX + event.offsetX - this.panStartX, this.zoomScale);
      this.panY = this.clampPanY(this.panBaseY + event.offsetY - this.panStartY, this.zoomScale);
    }
  }

  private finishPan(): void {
    if (this.dragReady && this.zoomScale > ZOOMED_THRESHOLD) {
      this.panX = this.clampPanX(this.panX, this.zoomScale);
      this.panY = this.clampPanY(this.panY, this.zoomScale);
      this.dragReady = false;
    }
  }

  /** 平移钳制：放大 s 倍时边界 = 视口 × (s-1)/2（VHome 同款） */
  private clampPanX(value: number, scale: number): number {
    const limit: number = Math.max(0, (this.viewportWidth * Math.max(1, scale - 1)) / 2);
    return Math.max(-limit, Math.min(limit, value));
  }

  private clampPanY(value: number, scale: number): number {
    const limit: number = Math.max(0, (this.viewportHeight * Math.max(1, scale - 1)) / 2);
    return Math.max(-limit, Math.min(limit, value));
  }

  /** Swiper 换页复位当前页缩放 */
  private resetZoom(): void {
    this.zoomScale = 1;
    this.panX = 0;
    this.panY = 0;
    this.dragReady = false;
  }

  /** 保存当前滑动到的这一张到相册（权限直存 → 系统对话框兜底）。 */
  private async saveCurrent(): Promise<void> {
    const paths = this.item.mediaPaths;
    if (this.current < 0 || this.current >= paths.length || this.saving) {
      return;
    }
    const p = paths[this.current];
    const req = new FolderSaveRequest();
    req.path = p;
    req.name = this.item.id + '_' + this.current + '.' + this.extOf(p);
    this.saving = true;
    try {
      const saved = await MediaSaver.storeGalleryBatch(getContext(this), [req]);
      toast(saved > 0 ? '已保存到相册' : '已取消保存');
    } catch (e) {
      toast('保存失败：' + (e instanceof Error ? e.message : String(e)));
    } finally {
      this.saving = false;
    }
  }

  /** 通过系统分享面板分享当前媒体。 */
  private async shareCurrent(): Promise<void> {
    const paths = this.item.mediaPaths;
    if (this.current < 0 || this.current >= paths.length) {
      return;
    }
    try {
      const p = paths[this.current];
      const isVideo = /\.(mp4|mov)$/i.test(p);
      const data = new systemShare.SharedData({
        utd: isVideo ? uniformTypeDescriptor.UniformDataType.VIDEO : uniformTypeDescriptor.UniformDataType.IMAGE,
        uri: fileUri.getUriFromPath(p)
      });
      const controller = new systemShare.ShareController(data);
      await controller.show(getContext(this) as common.UIAbilityContext,
        { previewMode: systemShare.SharePreviewMode.DETAIL });
    } catch (e) {
      toast('分享失败：' + (e instanceof Error ? e.message : String(e)));
    }
  }

  /** 复制当前图片到系统剪贴板（本地文件解码 PixelMap，VHome v1.22.0 同姿势）。 */
  private async copyImage(): Promise<void> {
    const paths = this.item.mediaPaths;
    if (this.current < 0 || this.current >= paths.length || this.saving) {
      return;
    }
    const p = paths[this.current];
    if (this.isVideoPage(p)) {
      toast('视频不支持复制，可使用保存或分享');
      return;
    }
    this.saving = true;
    try {
      const file = fileIo.openSync(p, fileIo.OpenMode.READ_ONLY);
      const buf = new ArrayBuffer(fileIo.statSync(file.fd).size);
      fileIo.readSync(file.fd, buf);
      fileIo.closeSync(file.fd);
      const source = image.createImageSource(buf);
      const pm = await source.createPixelMap();
      await source.release();
      const data = pasteboard.createData(pasteboard.MIMETYPE_PIXELMAP, pm);
      await pasteboard.getSystemPasteboard().setPasteData(data);
      toast('图片已复制');
    } catch (e) {
      toast('复制失败：' + (e instanceof Error ? e.message : String(e)));
    } finally {
      this.saving = false;
    }
  }

  /** 长按图片弹出的操作菜单（VHome v2.0.1 同款：按钮文字颜色跟随深浅色）。 */
  private showImageActions(): void {
    const isDark: boolean = AppStorage.get<boolean>('isDarkMode') === true;
    const btnColor: string = isDark ? '#FFFFFF' : '#E5000000';
    promptAction.showActionMenu({
      title: '图片操作',
      buttons: [
        { text: '分享图片', color: btnColor },
        { text: '保存当前原图', color: btnColor },
        { text: '保存全部原图', color: btnColor },
        { text: '复制图片', color: btnColor }
      ]
    }).then((result: promptAction.ActionMenuSuccessResponse): void => {
      if (result.index === 0) {
        this.shareCurrent();
      } else if (result.index === 1) {
        this.saveCurrent();
      } else if (result.index === 2) {
        this.onSaveAll();
      } else if (result.index === 3) {
        this.copyImage();
      }
    }).catch((): void => {
      // 用户点了蒙层取消
    });
  }

  /** 未放大态手势层：双击 + 捏合 + 单击 + 长按（不挂 Pan —— 水平滑动让给 Swiper） */
  @Builder
  idleGestures(pageIdx: number) {
    Stack()
      .width('100%')
      .height('100%')
      .gesture(
        GestureGroup(GestureMode.Exclusive,
          TapGesture({ count: 2 })
            .onAction((): void => {
              if (pageIdx === this.current) {
                this.toggleZoom();
              }
            }),
          PinchGesture({ fingers: 2, distance: 5 })
            .onActionStart((event: GestureEvent): void => {
              if (pageIdx === this.current) {
                this.startPinch(event);
              }
            })
            .onActionUpdate((event: GestureEvent): void => {
              if (pageIdx === this.current) {
                this.updatePinch(event);
              }
            })
            .onActionEnd((): void => {
              if (pageIdx === this.current) {
                this.finishZoom();
              }
            }),
          TapGesture({ count: 1 })
            .onAction((): void => {
              this.showControls = !this.showControls;
            }),
          LongPressGesture({ fingers: 1, repeat: false, duration: 500 })
            .onAction((): void => {
              this.showImageActions();
            })
        )
      )
  }

  /** 放大态手势层：双击 + 捏合 + Pan 拖动 + 单击 + 长按 */
  @Builder
  zoomGestures(pageIdx: number) {
    Stack()
      .width('100%')
      .height('100%')
      .gesture(
        GestureGroup(GestureMode.Exclusive,
          TapGesture({ count: 2 })
            .onAction((): void => {
              this.toggleZoom();
            }),
          PinchGesture({ fingers: 2, distance: 5 })
            .onActionStart((event: GestureEvent): void => {
              this.startPinch(event);
            })
            .onActionUpdate((event: GestureEvent): void => {
              this.updatePinch(event);
            })
            .onActionEnd((): void => {
              this.finishZoom();
            }),
          PanGesture({ fingers: 1, direction: PanDirection.All, distance: 3 })
            .onActionStart((event: GestureEvent): void => {
              this.startPan(event);
            })
            .onActionUpdate((event: GestureEvent): void => {
              this.updatePan(event);
            })
            .onActionEnd((event: GestureEvent): void => {
              this.finishPan();
            }),
          TapGesture({ count: 1 })
            .onAction((): void => {
              this.showControls = !this.showControls;
            }),
          LongPressGesture({ fingers: 1, repeat: false, duration: 500 })
            .onAction((): void => {
              this.showImageActions();
            })
        )
      )
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      // 媒体区（全屏黑底）：图片节点常驻，缩放/平移只改属性不重建
      if (this.item.mediaPaths.length === 0) {
        Column({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.picture'))
            .fontSize(48)
            .fontColor(['#B0B0B0'])
          Text('这个作品没有可查看的文件')
            .fontSize(15)
            .fontColor('#B0B0B0')
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        Swiper() {
          ForEach(this.item.mediaPaths, (p: string, pageIdx: number) => {
            Stack() {
              if (this.isVideoPage(p)) {
                Video({ src: this.fileUri(p) })
                  .controls(true)
                  .width('100%')
                  .height('100%')
                  .objectFit(ImageFit.Contain)
              } else {
                // 图片节点常驻：手势只改属性，双击缩放不重新解码、不闪
                Image(this.fileUri(p))
                  .id(`viewer_img_${pageIdx}`)
                  .draggable(false)
                  .copyOption(CopyOptions.None)
                  .width('100%')
                  .height('100%')
                  .objectFit(ImageFit.Contain)
                  .scale({ x: this.getScale(pageIdx), y: this.getScale(pageIdx) })
                  .translate({ x: this.getPanX(pageIdx), y: this.getPanY(pageIdx) })

                // 独立透明手势层：按放大态切换手势集合，不触碰图片节点
                if (pageIdx === this.current && this.zoomed()) {
                  this.zoomGestures(pageIdx)
                } else {
                  this.idleGestures(pageIdx)
                }
              }
            }
            .width('100%')
            .height('100%')
            .onAreaChange((_oldArea: Area, newArea: Area) => {
              if (pageIdx === this.current) {
                this.viewportWidth = Math.max(1, Number(newArea.width));
                this.viewportHeight = Math.max(1, Number(newArea.height));
                this.panX = this.clampPanX(this.panX, this.zoomScale);
                this.panY = this.clampPanY(this.panY, this.zoomScale);
              }
            })
          }, (p: string, pageIdx: number) => `${pageIdx}_${p}`)
        }
        .index(this.current)
        .indicator(false)
        .loop(false)
        .vertical(false)
        .cachedCount(1)
        .disableSwipe(this.zoomed())
        .width('100%')
        .height('100%')
        .onChange((i: number) => {
          this.current = i;
          this.resetZoom();
        })
      }

      // 覆盖层：顶部（返回 / 计数 / 分享）+ 底部操作条。
      // Transparent 放行触摸给下层 Swiper（VHome v1.43.6 同款修复）。
      Column() {
        Row() {
          // 返回圆钮（沉浸光感玻璃）
          Stack() {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(22)
              .fontColor([Theme.textPrimary])
          }
          .width(40)
          .height(40)
          .borderRadius(20)
          .backgroundColor('#66FFFFFF')
          .backgroundBlurStyle(BlurStyle.Regular)
          .border({ width: 0.5, color: '#40FFFFFF' })
          .onClick(() => {
            this.onClose();
          })

          Text(`${this.current + 1} / ${Math.max(1, this.item.mediaPaths.length)}`)
            .fontSize(14)
            .fontColor('#FFFFFF')
            .layoutWeight(1)
            .textAlign(TextAlign.Center)

          // 分享圆钮（沉浸光感玻璃）
          Stack() {
            SymbolGlyph($r('sys.symbol.share'))
              .fontSize(20)
              .fontColor([Theme.textPrimary])
          }
          .width(40)
          .height(40)
          .borderRadius(20)
          .backgroundColor('#66FFFFFF')
          .backgroundBlurStyle(BlurStyle.Regular)
          .border({ width: 0.5, color: '#40FFFFFF' })
          .onClick(() => {
            this.shareCurrent();
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ left: 16, right: 16, top: this.topAvoid + 10 })

        Blank()

        // 底部：原帖文本内容（作者 + 平台图标 + 正文）
        Column({ space: 6 }) {
          Row({ space: 8 }) {
            Image(badgeRes(this.item.platform))
              .width(18)
              .height(18)
              .borderRadius(5)
              .objectFit(ImageFit.Cover)
            Text(this.item.author.length > 0 ? this.item.author : platformName(this.item.platform))
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            Text(platformName(this.item.platform))
              .fontSize(11)
              .fontColor('#99FFFFFF')
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Text(this.item.desc.length > 0 ? this.item.desc : this.item.title)
            .fontSize(14)
            .fontColor('#E6FFFFFF')
            .lineHeight(20)
            .maxLines(6)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: this.bottomAvoid + 16 })
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Transparent)
      .visibility(this.showControls ? Visibility.Visible : Visibility.None)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
    // 黑底延伸到状态栏与底部小白条区域（小白条沉浸，无白边）
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
