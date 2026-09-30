/**
 * 解析页：粘贴分享链接 → 识别平台 → 小红书走原解析/选择流程，
 * 抖音/Instagram/TikTok/X 走多平台解析并直接下载进媒体库。
 */
import { promptAction, router } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { AppContainer } from '../data/AppContainer';
import { QueueListenerState } from '../data/DownloadQueue';
import { DownloadTask, TaskStatus } from '../data/TaskStore';
import { Theme, toast } from '../view/Common';
import { XhsUrlParser } from '../core/XhsUrlParser';
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
      router.pushUrl({
        url: 'pages/NoteDetail',
        params: { 'taskId': taskId, 'note': note.toBundle() } as Record<string, Object>
      });
      this.input = '';
    } catch (e) {
      toast(this.failureMessage(e instanceof Error ? e : new Error(String(e))));
      // 直连被风控壳页拦截（视频笔记常见）：引导用内置浏览器内核提取
      this.offerWebExtract(link);
    } finally {
      this.resolving = false;
    }
  }

  private async parseBatch(): Promise<void> {
    const raw = this.input.trim();
    if (XhsUrlParser.extractLinks(raw).length === 0) {
      toast($r('app.string.index_input_invalid'));
      return;
    }
    const ids = AppContainer.get().queue.enqueue(raw, false);
    toast($r('app.string.index_resolve_ok') + ' ×' + ids.length);
    this.input = '';
  }

  private readClipboardAndPrefill(): void {
    try {
      const data = pasteboard.getSystemPasteboard().getDataSync();
      const text = data.getPrimaryText();
      // 任意平台链接都预填（小红书 / 抖音 / Instagram / TikTok / X）
      if (text !== null && text !== undefined && MediaParser.firstSupportedLink(text).length > 0 &&
        this.input.length === 0) {
        this.input = text;
      }
    } catch (e) {
    }
  }

  build() {
    Column() {
      Row() {
        Column({ space: 2 }) {
          Text('解析')
            .fontSize(26)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.textPrimary)
          Text('支持小红书 / 抖音 / Instagram / TikTok / X')
            .fontSize(13)
            .fontColor(Theme.textSecondary)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: this.topAvoid + 10, bottom: 10 })

      Scroll() {
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
            Button($r('app.string.common_clear'), { buttonStyle: ButtonStyleMode.NORMAL })
              .onClick(() => {
                this.batchMode = !this.batchMode;
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
        .padding({ left: 16, right: 16, bottom: 96, top: 4 })
      }
      .layoutWeight(1)
      .align(Alignment.Top)
      .onAppear(() => {
        this.readClipboardAndPrefill();
      })
    }
    .padding({ left: this.leftAvoid, right: this.rightAvoid })
    .width('100%')
    .height('100%')
  }
}

@Component
export struct TaskRow {
  task: DownloadTask = new DownloadTask();
  speedBps: number = 0;

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
        Text(`${this.task.completedFiles}/${this.task.totalFiles}  ${formatSpeed(this.speedBps)}`)
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
