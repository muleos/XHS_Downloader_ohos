import { router } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { AppContainer } from '../data/AppContainer';
import { QueueListenerState, DownloadQueue } from '../data/DownloadQueue';
import { TaskStore, DownloadTask, TaskStatus } from '../data/TaskStore';
import { Theme, TitleBar, toast } from '../view/Common';
import { XhsUrlParser } from '../core/XhsUrlParser';
import { XhsResolveException, ResolveFailure } from '../core/XhsContentRepository';

@Entry
@Component
struct Index {
  @StorageLink('topAvoid') topAvoid: number = 0;
  @StorageLink('bottomAvoid') bottomAvoid: number = 0;
  @StorageLink('leftAvoid') leftAvoid: number = 0;
  @StorageLink('rightAvoid') rightAvoid: number = 0;
  @State input: string = '';
  @State batchMode: boolean = false;
  @State resolving: boolean = false;
  @State queueState: QueueListenerState = new QueueListenerState();

  aboutToAppear(): void {
    AppContainer.get().queue.onChange((state: QueueListenerState) => {
      this.queueState = state;
    });
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
    if (raw.length === 0 || XhsUrlParser.extractLinks(raw).length === 0) {
      toast($r('app.string.index_input_invalid'));
      return;
    }
    const app = AppContainer.get();
    this.resolving = true;
    try {
      const note = await app.repo.resolve(raw, app.settings.get().downloadOptions.useWebSession,
        app.settings.get().downloadOptions.timeoutSeconds);
      const taskId = app.queue.enqueueForSelection(note);
      router.pushUrl({
        url: 'pages/NoteDetail',
        params: { 'taskId': taskId, 'note': note.toBundle() } as Record<string, Object>
      });
      this.input = '';
    } catch (e) {
      toast(this.failureMessage(e instanceof Error ? e : new Error(String(e))));
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
      if (text !== null && text !== undefined && XhsUrlParser.extractLinks(text).length > 0 && this.input.length === 0) {
        this.input = text;
      }
    } catch (e) {
    }
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Text($r('app.string.index_title'))
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textPrimary)
          .layoutWeight(1)
        Text($r('app.string.index_history'))
          .fontSize(15)
          .fontColor(Theme.red)
          .onClick(() => {
            router.pushUrl({ url: 'pages/History' });
          })
        Text($r('app.string.index_settings'))
          .fontSize(15)
          .fontColor(Theme.red)
          .onClick(() => {
            router.pushUrl({ url: 'pages/Settings' });
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: this.topAvoid + 8, bottom: 10 })

      Scroll {
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
            Button(this.batchMode ? $r('app.string.index_parse_batch') : $r('app.string.index_parse'),
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
        .padding({ left: 16, right: 16, bottom: this.bottomAvoid + 16, top: 4 })
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
    .backgroundColor(Theme.pageBg)
  }
}

@Component
struct TaskRow {
  task: DownloadTask;
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

function formatSpeed(n: number): string {
  if (n <= 0) {
    return '';
  }
  if (n < 1048576) {
    return (n / 1024).toFixed(0) + 'KB/s';
  }
  return (n / 1048576).toFixed(1) + 'MB/s';
}
