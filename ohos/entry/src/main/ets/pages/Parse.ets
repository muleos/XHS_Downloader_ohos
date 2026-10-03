/**
 * 解析页：粘贴分享链接 → 识别平台 → 小红书走原解析/选择流程，
 * 抖音/Instagram/TikTok/X 走多平台解析并直接下载进媒体库。
 */
import { promptAction, router, SymbolGlyphModifier } from '@kit.ArkUI';
import { HdsNavigation, HdsNavigationTitleMode, HdsNavigationMenuContentOptions,
  HdsNavigationMenuItemOptions } from '@kit.UIDesignKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { AppContainer } from '../data/AppContainer';
import { QueueListenerState } from '../data/DownloadQueue';
import { DownloadTask, TaskStatus, ResourceState } from '../data/TaskStore';
import { frostTitleBarStyle } from '../view/FrostScaffold';
import { Theme, toast } from '../view/Common';
import { XhsResolveException, ResolveFailure } from '../core/XhsContentRepository';
import { MediaParser } from '../service/PlatformServices';
import { Platform } from '../model/SaveModels';

@Component
export struct ParsePage {
  @StorageLink('topAvoid') topAvoid: number = 0;
  @StorageLink('bottomAvoid') bottomAvoid: number = 0;
  @StorageLink('leftAvoid') leftAvoid: number = 0;
  @StorageLink('rightAvoid') rightAvoid: number = 0;
  @State input: string = '';
  @State batchMode: boolean = false;
  @State resolving: boolean = false;
  @State progressText: string = '';
  @State queueState: QueueListenerState = new QueueListenerState();
  /** 主滚动容器控制器（HdsNavigation bindToScrollable 官方滚动源绑定） */
  private scroller: Scroller = new Scroller();
  /** 首页解析圆钮的跨页请求：非空 = 待解析的分享文本 */
  @StorageLink('parseRequest') @Watch('onParseRequest') parseRequest: string = '';

  aboutToAppear(): void {
    AppContainer.get().queue.onChange((state: QueueListenerState) => {
      this.queueState = state;
    });
    // 首次挂载（懒加载 TabContent）时消费已 pending 的解析请求
    if (this.parseRequest.length > 0) {
      this.consumeParseRequest();
    }
  }

  onParseRequest(): void {
    if (this.parseRequest.length > 0) {
      this.consumeParseRequest();
    }
  }

  private consumeParseRequest(): void {
    const req = this.parseRequest;
    // 先复位再解析：同样的链接下次请求仍会触发 @Watch
    AppStorage.setOrCreate<string>('parseRequest', '');
    this.input = req;
    this.parse();
  }

  private failureMessage(e: Error): ResourceStr {
    if (e instanceof XhsResolveException) {
      const failure = (e as XhsResolveException).failure;
      switch (failure) {
        case ResolveFailure.NOT_NOTE:
          return $r('app.string.error_not_note');
        case ResolveFailure.NO_MEDIA:
          return $r('app.string.error_no_media');
        case ResolveFailure.NETWORK:
          return $r('app.string.error_network');
        default:
          return $r('app.string.error_parse_failed');
      }
    }
    return $r('app.string.error_network');
  }

  private async parse(): Promise<void> {
    const raw = this.input.trim();
    if (raw.length === 0) {
      toast($r('app.string.index_input_invalid'));
      return;
    }
    // 批量模式：识别输入里的全部链接逐个处理（v1.20.0 批量识别）
    if (this.batchMode) {
      await this.parseBatch();
      return;
    }
    const app = AppContainer.get();
    // 通用提取：小红书 / 抖音 / Instagram / TikTok / X 都能识别
    const target = MediaParser.firstSupportedLink(raw);
    const platform = target.length > 0 ? MediaParser.detect(target) : Platform.UNKNOWN;
    if (platform === Platform.XHS) {
      await this.parseXhs(raw);
      return;
    }
    if (platform === Platform.UNKNOWN) {
      toast($r('app.string.index_input_invalid'));
      return;
    }
    // 多平台：解析 + 直接下载进媒体库
    this.resolving = true;
    this.progressText = '解析中…';
    try {
      const result = await app.multi.save(getContext(this), target, (text: string): void => {
        this.progressText = text;
      });
      if (result.ok) {
        toast(result.message);
        this.input = '';
      } else {
        toast(result.message);
        // 直连被平台风控时，引导用内置浏览器内核提取
        if (result.webFallback && result.sourceUrl.length > 0) {
          this.offerWebExtract(result.sourceUrl);
        }
      }
    } catch (e) {
      toast('下载失败：' + (e instanceof Error ? e.message : String(e)));
    } finally {
      this.resolving = false;
      this.progressText = '';
    }
  }

  private offerWebExtract(url: string): void {
    const platform = MediaParser.detect(url);
    const isDouyin = platform === Platform.DOUYIN;
    const isXhs = platform === Platform.XHS;
    const title = isDouyin ? '抖音开启了风控' : (isXhs ? '小红书直连受限' : '直连解析失败');
    const message = isDouyin ?
      '抖音已把作品数据改为异步加载并启用人机验证，直连请求拿不到内容。可以用内置浏览器内核打开该链接自动提取媒体，是否继续？' :
      isXhs ?
        '小红书直连请求未取到作品数据（视频笔记常被风控壳页拦截）。可以用内置浏览器内核打开该链接自动提取媒体，是否继续？' :
        '该平台对直连请求受限（网络受限或需登录）。可以用内置浏览器内核打开该链接自动提取媒体，是否继续？';
    promptAction.showDialog({
      title: title,
      message: message,
      buttons: [
        { text: '网页提取', color: Theme.accent },
        { text: '取消', color: Theme.textSecondary }
      ]
    }).then((data: promptAction.ShowDialogSuccessResponse) => {
      if (data.index === 0) {
        router.pushUrl({
          url: 'pages/WebExtract',
          params: { 'url': url } as Record<string, Object>
        });
      }
    }).catch(() => {
    });
  }

  private async parseXhs(raw: string): Promise<void> {
    const link = MediaParser.firstSupportedLink(raw);
    if (MediaParser.detect(link) !== Platform.XHS) {
      toast($r('app.string.index_input_invalid'));
      return;
    }
    const app = AppContainer.get();
    this.resolving = true;
    try {
      const note = await app.repo.resolve(link, app.settings.get().downloadOptions.useWebSession,
        app.settings.get().downloadOptions.timeoutSeconds);
      const taskId = app.queue.enqueueForSelection(note);
      // 选择性下载关闭：不进选择页，直接下载全部媒体（安卓版同款语义）
      if (!app.settings.get().selectiveDownload) {
        const all: number[] = [];
        for (let i = 0; i < note.items.length; i++) {
          all.push(i);
        }
        app.queue.confirmSelection(taskId, all);
        toast($r('app.string.index_resolve_ok') + '，已开始下载全部媒体');
      } else {
        router.pushUrl({
          url: 'pages/NoteDetail',
          params: { 'taskId': taskId, 'note': note.toBundle() } as Record<string, Object>
        });
      }
      this.input = '';
    } catch (e) {
      toast(this.failureMessage(e instanceof Error ? e : new Error(String(e))));
      // 直连被风控壳页拦截（视频笔记常见）：引导用内置浏览器内核提取
      this.offerWebExtract(link);
    } finally {
      this.resolving = false;
    }
  }

  /**
   * 批量识别（v1.20.0，安卓版同款）：提取输入中的全部支持链接，
   * 小红书链接批量入队，其余平台（抖音/IG/TikTok/X）逐个解析下载。
   */
  private async parseBatch(): Promise<void> {
    const raw = this.input.trim();
    const links = MediaParser.extractAnyLinks(raw).filter((l: string): boolean =>
      MediaParser.detect(l) !== Platform.UNKNOWN);
    if (links.length === 0) {
      toast($r('app.string.index_input_invalid'));
      return;
    }
    const app = AppContainer.get();
    const xhsLinks = links.filter((l: string): boolean => MediaParser.detect(l) === Platform.XHS);
    const otherLinks = links.filter((l: string): boolean => MediaParser.detect(l) !== Platform.XHS);
    this.resolving = true;
    let okCount = 0;
    let failCount = 0;
    try {
      // 小红书：批量入队（队列自动逐个解析）
      if (xhsLinks.length > 0) {
        app.queue.enqueue(xhsLinks.join('\n'), false);
        okCount += xhsLinks.length;
      }
      // 其余平台：逐个解析 + 下载
      for (let i = 0; i < otherLinks.length; i++) {
        this.progressText = `批量解析 ${i + 1}/${otherLinks.length}…`;
        try {
          const result = await app.multi.save(getContext(this), otherLinks[i], (text: string): void => {
            this.progressText = `(${i + 1}/${otherLinks.length}) ${text}`;
          });
          if (result.ok) {
            okCount++;
          } else {
            failCount++;
          }
        } catch (e) {
          failCount++;
        }
      }
      toast(`批量识别 ${links.length} 个链接：成功 ${okCount}${failCount > 0 ? '，失败 ' + failCount : ''}`);
      if (okCount > 0) {
        this.input = '';
      }
    } finally {
      this.resolving = false;
      this.progressText = '';
    }
  }

  /** force=true（顶栏剪贴板按钮）：覆盖输入框；false（首次挂载）：仅空输入时预填 */
  private readClipboardAndPrefill(force: boolean): void {
    // 「手动输入链接」开启时不自动提取剪贴板（设置 → 剪贴板）
    if (!force && AppContainer.get().settings.get().manualInputLinks) {
      return;
    }
    try {
      const data = pasteboard.getSystemPasteboard().getDataSync();
      const text = data.getPrimaryText();
      // 任意平台链接都预填（小红书 / 抖音 / Instagram / TikTok / X）
      if (text !== null && text !== undefined && MediaParser.firstSupportedLink(text).length > 0 &&
        (force || this.input.length === 0)) {
        this.input = text;
        toast('已从剪贴板填入链接');
      } else if (force) {
        toast('剪贴板未识别到支持的链接');
      }
    } catch (e) {
      if (force) {
        toast('剪贴板读取失败：' + (e instanceof Error ? e.message : String(e)));
      }
    }
  }

  /** 顶栏 menu：剪贴板预填（与收藏页官方 menu 槽位同款） */
  private menuOptions(): HdsNavigationMenuContentOptions {
    const clipIcon: SymbolGlyphModifier = new SymbolGlyphModifier($r('sys.symbol.doc_plaintext'));
    clipIcon.fontColor([Theme.textPrimary]);
    const items: HdsNavigationMenuItemOptions[] = [
      {
        content: {
          icon: clipIcon,
          action: (): void => {
            this.readClipboardAndPrefill(true);
          }
        }
      }
    ];
    return { value: items };
  }

  /** 清空输入框（v1.20.0 修复：此前该按钮误绑成批量模式开关） */
  private clearInput(): void {
    this.input = '';
    this.progressText = '';
  }

  build() {
    // 与收藏页同款官方顶栏骨架：HdsNavigation MINI + frost 四件套，
    // 三个一级页面顶栏高度与水平对齐由官方组件统一。
    HdsNavigation() {
      Scroll(this.scroller) {
        Column({ space: 12 }) {
          TextArea({ text: this.input, placeholder: $r('app.string.index_input_hint') })
            .fontSize(15)
            .height(this.batchMode ? 120 : 72)
            .borderRadius(14)
            .backgroundColor(Theme.cardBg)
            .onChange((value: string) => {
              this.input = value;
            })

          Row({ space: 10 }) {
            Button(this.batchMode ? $r('app.string.index_parse_batch') :
              (this.resolving ? (this.progressText.length > 0 ? this.progressText : '处理中…') : $r('app.string.index_parse')),
              { buttonStyle: ButtonStyleMode.EMPHASIZED })
              .layoutWeight(1)
              .enabled(!this.resolving)
              .onClick(() => {
                this.parse();
              })
            // 批量识别开关（安卓版同款）
            Button(this.batchMode ? '退出批量' : '批量', { buttonStyle: ButtonStyleMode.NORMAL })
              .fontSize(13)
              .fontColor(this.batchMode ? Theme.accent : Theme.textPrimary)
              .enabled(!this.resolving)
              .onClick(() => {
                this.batchMode = !this.batchMode;
                toast(this.batchMode ? '批量模式：一次粘贴多个链接逐个识别' : '已退出批量模式');
              })
            // 清空输入（v1.20.0 修复失效）
            Button($r('app.string.common_clear'), { buttonStyle: ButtonStyleMode.NORMAL })
              .fontSize(13)
              .enabled(!this.resolving)
              .onClick(() => {
                this.clearInput();
              })
          }
          .width('100%')

          if (this.queueState.tasks.length > 0) {
            Text($r('app.string.index_tasks'))
              .fontSize(14)
              .fontColor(Theme.textSecondary)
              .width('100%')
          }
          ForEach(this.queueState.tasks, (task: DownloadTask) => {
            TaskRow({ task: task, speedBps: this.queueState.speedBps })
          }, (task: DownloadTask) => task.id.toString() + '_' + task.status)
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
      .onAppear(() => {
        this.readClipboardAndPrefill(false);
      })
    }
    .titleBar({
      avoidLayoutSafeArea: true,
      content: {
        title: { mainTitle: '解析', subTitle: '支持小红书 / 抖音 / Instagram / TikTok / X' },
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
    // 根背景保持透明：透出 Index 的沉浸光晕层（项目约定）
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
  }
}

@Component
export struct TaskRow {
  task: DownloadTask = new DownloadTask();
  speedBps: number = 0;

  /** 媒体卡片信息（设置 → 下载选项）：1 文件体积 / 2 分辨率（有数据时） */
  private mediaInfo(): string {
    const mode = AppContainer.get().settings.get().mediaCardInfo;
    if (mode === 1) {
      let bytes = 0;
      for (const res of this.task.resources) {
        bytes += res.bytes;
      }
      return bytes > 0 ? formatSize(bytes) : '';
    }
    if (mode === 2) {
      for (const res of this.task.resources) {
        if (res.state === ResourceState.COMPLETED && res.tempPath.length > 0) {
          return this.task.noteType === 'video' ? '视频' : '图片';
        }
      }
    }
    return '';
  }

  private statusLabel(): ResourceStr {
    switch (this.task.status) {
      case TaskStatus.QUEUED:
        return $r('app.string.task_state_pending');
      case TaskStatus.RESOLVING:
      case TaskStatus.DOWNLOADING:
        return $r('app.string.task_state_downloading');
      case TaskStatus.WAITING_FOR_USER:
        return $r('app.string.task_state_wait_user');
      case TaskStatus.PAUSED:
        return $r('app.string.task_state_paused');
      case TaskStatus.COMPLETED:
        return $r('app.string.task_state_completed');
      case TaskStatus.PARTIAL:
        return $r('app.string.task_state_partial');
      case TaskStatus.FAILED:
        return $r('app.string.task_state_failed');
      case TaskStatus.CANCELLED:
        return $r('app.string.task_state_canceled');
      case TaskStatus.SKIPPED:
        return $r('app.string.task_state_skipped');
      default:
        return this.task.status;
    }
  }

  build() {
    Column({ space: 6 }) {
      Row() {
        Text(this.task.noteTitle.length > 0 ? this.task.noteTitle : this.task.noteUrl)
          .fontSize(13)
          .fontColor(Theme.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(this.statusLabel())
          .fontSize(12)
          .fontColor(this.task.status === TaskStatus.COMPLETED ? '#4CAF50' : Theme.textSecondary)
      }
      .width('100%')

      Progress({ value: this.task.progress, total: 100 })
        .width('100%')
        .height(4)
        .color(Theme.red)

      Row({ space: 8 }) {
        Text(`${this.task.completedFiles}/${this.task.totalFiles}  ${formatSpeed(this.speedBps)}` +
          (this.mediaInfo().length > 0 ? '  ' + this.mediaInfo() : ''))
          .fontSize(11)
          .fontColor(Theme.textSecondary)
          .layoutWeight(1)
        if (this.task.status === TaskStatus.DOWNLOADING || this.task.status === TaskStatus.RESOLVING) {
          Text($r('app.string.task_pause'))
            .fontSize(12)
            .fontColor(Theme.red)
            .onClick(() => {
              AppContainer.get().queue.pause(this.task.id);
            })
        }
        if (this.task.status === TaskStatus.PAUSED) {
          Text($r('app.string.task_resume'))
            .fontSize(12)
            .fontColor(Theme.red)
            .onClick(() => {
              AppContainer.get().queue.resume(this.task.id);
            })
        }
        if (this.task.status !== TaskStatus.COMPLETED && this.task.status !== TaskStatus.CANCELLED) {
          Text($r('app.string.task_cancel'))
            .fontSize(12)
            .fontColor(Theme.textSecondary)
            .onClick(() => {
              AppContainer.get().queue.cancel(this.task.id);
            })
        }
        if (this.task.status === TaskStatus.FAILED || this.task.status === TaskStatus.PARTIAL) {
          Text($r('app.string.task_retry'))
            .fontSize(12)
            .fontColor(Theme.red)
            .onClick(() => {
              AppContainer.get().queue.retry(this.task.id);
            })
        }
      }
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(12)
    .borderRadius(12)
    .backgroundColor(Theme.cardBg)
  }
}

export function formatSpeed(n: number): string {
  if (n <= 0) {
    return '';
  }
  if (n < 1048576) {
    return (n / 1024).toFixed(0) + 'KB/s';
  }
  return (n / 1048576).toFixed(1) + 'MB/s';
}

export function formatSize(bytes: number): string {
  if (bytes <= 0) {
    return '';
  }
  if (bytes < 1048576) {
    return (bytes / 1024).toFixed(0) + 'KB';
  }
  return (bytes / 1048576).toFixed(1) + 'MB';
}
