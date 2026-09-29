import { router } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { AppContainer } from '../data/AppContainer';
import { QueueItem, QueueSnapshot, TaskState } from '../data/DownloadQueue';
import { Theme, TitleBar, toast } from '../view/Common';
import { ResolvedNote, NamingFormatDefaults } from '../core/models';
import { XhsUrlParser } from '../core/XhsUrlParser';
import { XhsResolveException, ResolveFailure } from '../core/XhsContentRepository';

@Entry
@Component
struct Index {
  @StorageLink('topAvoid') topAvoid: number = 0;
  @StorageLink('bottomAvoid') bottomAvoid: number = 0;
  @State input: string = '';
  @State batchMode: boolean = false;
  @State resolving: boolean = false;
  @State queueSnap: QueueSnapshot = new QueueSnapshot();

  aboutToAppear(): void {
    const app = AppContainer.get();
    app.queue.onChange((snap: QueueSnapshot) => {
      this.queueSnap = snap;
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
        case ResolveFailure.PARSE_FAILED:
          return $r('app.string.error_parse_failed');
        default:
          return $r('app.string.error_network');
      }
    }
    return $r('app.string.error_network');
  }

  private async parseOne(raw: string): Promise<void> {
    const app = AppContainer.get();
    const settings = app.settings.get();
    this.resolving = true;
    try {
      const note: ResolvedNote =
        await app.repo.resolve(raw, settings.downloadOptions.useWebSession, settings.downloadOptions.timeoutSeconds);
      router.pushUrl({
        url: 'pages/NoteDetail',
        params: note.toBundle()
      });
    } catch (e) {
      toast(this.failureMessage(e instanceof Error ? e : new Error(String(e))));
    } finally {
      this.resolving = false;
    }
  }

  private async parseBatch(raw: string): Promise<void> {
    const links = XhsUrlParser.extractLinks(raw);
    if (links.length === 0) {
      toast($r('app.string.index_input_invalid'));
      return;
    }
    const app = AppContainer.get();
    const settings = app.settings.get();
    for (const link of links) {
      try {
        const note =
          await app.repo.resolve(link, settings.downloadOptions.useWebSession, settings.downloadOptions.timeoutSeconds);
        const template = settings.useCustomNamingFormat ? settings.customNamingTemplate : NamingFormatDefaults.DEFAULT_TEMPLATE;
        const added = app.queue.enqueueNote(note, template, settings.downloadOptions.commentImageDownload);
        if (added > 0) {
          app.records.add(note.noteId, note.authorName, note.title, added, 'queued');
        }
      } catch (e) {
        // Keep resolving the rest of the batch.
      }
    }
    toast($r('app.string.index_resolve_ok'));
    app.queue.start(settings.downloadOptions.useWebSession, settings.downloadOptions.timeoutSeconds);
  }

  private readClipboardAndPrefill(): void {
    try {
      const data = pasteboard.getSystemPasteboard().getDataSync();
      const text = data.getPrimaryText();
      if (text !== null && text !== undefined && XhsUrlParser.extractLinks(text).length > 0 && this.input.length === 0) {
        this.input = text;
      }
    } catch (e) {
      // Clipboard may be locked by another app; ignore.
    }
  }

  build() {
    Column() {
      Column() {
        TitleBar({ title: $r('app.string.index_title') })
        Row({ space: 8 }) {
          Text($r('app.string.index_history'))
            .fontSize(15)
            .fontColor(Theme.textSecondary)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(14)
            .backgroundColor(Theme.cardBg)
            .onClick(() => {
              router.pushUrl({ url: 'pages/History' });
            })
          Text($r('app.string.index_settings'))
            .fontSize(15)
            .fontColor(Theme.textSecondary)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(14)
            .backgroundColor(Theme.cardBg)
            .onClick(() => {
              router.pushUrl({ url: 'pages/Settings' });
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
        .justifyContent(FlexAlign.End)
      }
      .padding({ top: this.topAvoid })

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
          Text(this.batchMode ? $r('app.string.index_parse_batch') : $r('app.string.index_parse'))
            .fontSize(16)
            .fontColor(Color.White)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .height(44)
            .borderRadius(22)
            .backgroundColor(this.resolving ? '#80FF2442' : Theme.red)
            .onClick(() => {
              if (this.resolving || this.input.trim().length === 0) {
                return;
              }
              if (this.batchMode) {
                this.parseBatch(this.input);
              } else {
                this.parseOne(this.input);
              }
            })
          Text(this.batchMode ? '1' : '∞')
            .fontSize(16)
            .fontColor(Theme.textPrimary)
            .width(44)
            .height(44)
            .textAlign(TextAlign.Center)
            .borderRadius(22)
            .backgroundColor(Theme.cardBg)
            .onClick(() => {
              this.batchMode = !this.batchMode;
            })
        }
        .width('100%')

        if (this.queueSnap.items.length > 0) {
          Column({ space: 8 }) {
            ForEach(this.queueSnap.items.slice(0, 20), (item: QueueItem) => {
              TaskRow({ item: item })
            }, (item: QueueItem) => item.id.toString() + '_' + item.state.toString())
          }
          .width('100%')
        }
        }
      }
      .layoutWeight(1)
      .padding({ left: 16, right: 16, bottom: this.bottomAvoid + 16, top: 4 })
      .align(Alignment.Top)
      .onAppear(() => {
        this.readClipboardAndPrefill();
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.pageBg)
  }
}

@Component
struct TaskRow {
  item: QueueItem;

  build() {
    Row({ space: 10 }) {
      Column({ space: 3 }) {
        Text(this.item.displayName)
          .fontSize(13)
          .fontColor(Theme.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.item.state === TaskState.RUNNING && this.item.totalBytes > 0) {
          Text(formatBytes(this.item.receivedBytes) + ' / ' + formatBytes(this.item.totalBytes) +
            '  ' + formatBytes(this.item.speedBps) + '/s')
            .fontSize(11)
            .fontColor(Theme.textSecondary)
        } else if (this.item.error.length > 0) {
          Text(this.item.error)
            .fontSize(11)
            .fontColor(Theme.red)
            .maxLines(1)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text(stateLabel(this.item.state))
        .fontSize(12)
        .fontColor(this.item.state === TaskState.DONE ? '#4CAF50' : Theme.textSecondary)
    }
    .width('100%')
    .padding(12)
    .borderRadius(12)
    .backgroundColor(Theme.cardBg)
  }
}

function formatBytes(n: number): string {
  if (n < 1024) {
    return n + 'B';
  }
  if (n < 1048576) {
    return (n / 1024).toFixed(1) + 'KB';
  }
  return (n / 1048576).toFixed(1) + 'MB';
}

function stateLabel(state: TaskState): string {
  switch (state) {
    case TaskState.PENDING:
      return '…';
    case TaskState.RUNNING:
      return '↓';
    case TaskState.DONE:
      return '✓';
    case TaskState.FAILED:
      return '✗';
    default:
      return '–';
  }
}
