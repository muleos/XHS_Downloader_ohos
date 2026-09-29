import { router } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { AppContainer } from '../data/AppContainer';
import { MediaSaver } from '../data/MediaSaver';
import { QueueItem, TaskState } from '../data/DownloadQueue';
import { Theme, TitleBar, toast } from '../view/Common';
import { ResolvedNote, ResolvedNoteItem, NamingFormatDefaults } from '../core/models';
import { NamingFormat } from '../core/NamingFormat';

interface DetailParams {
  bundle: Record<string, Object>;
}
@Entry
@Component
struct NoteDetail {
  @StorageLink('bottomAvoid') bottomAvoid: number = 0;
  @State note: ResolvedNote = new ResolvedNote();
  @State selected: boolean[] = [];
  @State downloaded: QueueItem[] = [];
  @State saving: boolean = false;

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, Object> | undefined;
    if (params !== undefined) {
      this.note = ResolvedNote.fromBundle(params);
    }
    this.selected = this.note.items.map((item: ResolvedNoteItem): boolean => {
      return !(item.image !== null && item.image.commentId.length > 0);
    });
    const app = AppContainer.get();
    app.queue.onChange(() => {
      this.downloaded = app.queue.items.filter((item: QueueItem): boolean =>
        item.state === TaskState.DONE || item.state === TaskState.RUNNING || item.state === TaskState.PENDING);
    });
  }

  private selectedCount(): number {
    let count = 0;
    for (const on of this.selected) {
      if (on) {
        count++;
      }
    }
    return count;
  }

  private displayNameFor(item: ResolvedNoteItem, index: number): string {
    const template = AppContainer.get().settings.get().useCustomNamingFormat
      ? AppContainer.get().settings.get().customNamingTemplate
      : NamingFormatDefaults.DEFAULT_TEMPLATE;
    let base = NamingFormat.render(template, this.note, index, this.note.items.length, item.kind);
    base = NamingFormat.sanitize(base);
    if (item.kind === 'video') {
      return base + '.mp4';
    }
    if (item.kind === 'live') {
      return base + (index + 1).toString() + '.jpg';
    }
    return base + '.jpg';
  }

  /** Download selected media into temp files; the save step runs separately. */
  private async downloadSelected(): Promise<void> {
    if (this.selectedCount() === 0) {
      toast($r('app.string.error_no_selection'));
      return;
    }
    const app = AppContainer.get();
    let added = 0;
    for (let i = 0; i < this.note.items.length; i++) {
      if (!this.selected[i]) {
        continue;
      }
      const item = this.note.items[i];
      if (item.kind === 'image' && item.image !== null) {
        if (app.queue.add(item.image.originalUrl, false, this.displayNameFor(item, i), this.note.noteId)) {
          added++;
        }
      } else if (item.kind === 'video' && item.video !== null) {
        if (app.queue.add(item.video.originalUrl, true, this.displayNameFor(item, i), this.note.noteId)) {
          added++;
        }
      } else if (item.kind === 'live' && item.live !== null) {
        // v1 saves live photos as separate image + video (same as SEPARATE mode).
        if (app.queue.add(item.live.image.originalUrl, false, this.displayNameFor(item, i), this.note.noteId)) {
          added++;
        }
        if (app.queue.add(item.live.video.originalUrl, true, this.displayNameFor(item, i) + '_video', this.note.noteId)) {
          added++;
        }
      }
    }
    const settings = app.settings.get();
    app.queue.start(settings.downloadOptions.useWebSession, settings.downloadOptions.timeoutSeconds);
    if (added > 0) {
      toast($r('app.string.detail_download_started'));
    }
  }

  /** SaveButton callback: copy pre-downloaded temp files into the gallery. */
  private async saveDownloadedToGallery(): Promise<void> {
    const app = AppContainer.get();
    const done = this.downloaded.filter((item: QueueItem): boolean => item.state === TaskState.DONE);
    if (done.length === 0) {
      toast($r('app.string.error_no_selection'));
      return;
    }
    this.saving = true;
    const saved = await MediaSaver.saveToGallery(getContext(this), done);
    this.saving = false;
    for (const item of done) {
      app.records.updateState(item.taskId, item.mediaId, saved > 0 ? 'saved' : 'downloaded');
    }
    if (saved > 0) {
      toast(getContext(this).resourceManager.getStringSync($r('app.string.common_saved')) + ' ×' + saved);
    } else {
      toast($r('app.string.error_network'));
    }
  }

  private saveDoneFiles(): void {
    const done = this.downloaded.filter((item: QueueItem): boolean => item.state === TaskState.DONE);
    if (done.length === 0) {
      toast($r('app.string.error_no_selection'));
      return;
    }
    MediaSaver.saveToFiles(getContext(this), done).then((count: number) => {
      if (count > 0) {
        toast(getContext(this).resourceManager.getStringSync($r('app.string.common_saved')) + ' ×' + count);
      }
    });
  }

  private copyText(): void {
    const text = this.note.body;
    if (text.length === 0) {
      return;
    }
    const data = pasteboard.createData(pasteboard.MimeType.PLAIN_TEXT, text);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      toast($r('app.string.common_copied'));
    });
  }

  private infoDocument(markdown: boolean): string {
    const lines: string[] = [];
    const head = markdown ? '# ' : '';
    lines.push(head + this.note.title);
    lines.push('');
    lines.push(this.note.body);
    lines.push('');
    lines.push('---');
    lines.push((markdown ? '- ' : '') + 'author: ' + this.note.authorName + ' (@' + this.note.authorId + ')');
    lines.push((markdown ? '- ' : '') + 'time: ' + this.note.publishTime);
    lines.push((markdown ? '- ' : '') + 'url: ' + this.note.canonicalUrl);
    for (const tag of this.note.tags) {
      lines.push((markdown ? '- ' : '') + 'tag: ' + tag);
    }
    return lines.join('\n');
  }

  private async saveInfo(markdown: boolean): Promise<void> {
    const name = NamingFormat.sanitize(this.note.title.length > 0 ? this.note.title : this.note.noteId) +
      (markdown ? '.md' : '.txt');
    const ok = await MediaSaver.saveTextFile(getContext(this), name, this.infoDocument(markdown));
    toast(ok ? $r('app.string.common_saved') : $r('app.string.error_network'));
  }

  build() {
    Column() {
      TitleBar({ title: this.note.title.length > 0 ? this.note.title : $r('app.string.index_title'), showBack: true })

      if (this.note.items.length === 0) {
        Column({ space: 12 }) {
          Text($r('app.string.detail_no_media')).fontSize(15).fontColor(Theme.textSecondary)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Grid() {
          ForEach(this.note.items, (item: ResolvedNoteItem, index: number) => {
            GridItem() {
              Column() {
                Stack({ alignContent: Alignment.TopEnd }) {
                  if (item.kind === 'video' && item.video !== null) {
                    RemoteThumb({ url: item.video.previewUrl, label: $r('app.string.detail_video_tag') })
                  } else if (item.kind === 'live' && item.live !== null) {
                    RemoteThumb({ url: item.live.previewUrl, label: $r('app.string.detail_live_photo_tag') })
                  } else if (item.image !== null) {
                    RemoteThumb({ url: item.image.previewUrl, label: '' })
                  }

                  Checkbox()
                    .select(this.selected[index])
                    .selectedColor(Theme.red)
                    .width(22)
                    .height(22)
                    .margin(6)
                    .onChange((on: boolean) => {
                      this.selected[index] = on;
                    })
                }
                .width('100%')
              }
              .onClick(() => {
                this.selected[index] = !this.selected[index];
              })
            }
          }, (item: ResolvedNoteItem, index: number) => item.kind + '_' + index)
        }
        .columnsTemplate('1fr 1fr')
        .columnsGap(8)
        .rowsGap(8)
        .padding({ left: 12, right: 12 })
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }

      // Bottom action bar.
      Column({ space: 8 }) {
        Text($r('app.string.detail_selected_count', this.selectedCount(), this.downloaded.length))
          .fontSize(12)
          .fontColor(Theme.textSecondary)

        Row({ space: 8 }) {
          Button($r('app.string.common_copy'))
            .buttonStyle(ButtonStyleMode.NORMAL)
            .onClick(() => {
              this.copyText();
            })
          Button($r('app.string.detail_save_info_txt'))
            .buttonStyle(ButtonStyleMode.NORMAL)
            .onClick(() => {
              this.saveInfo(false);
            })
          Button($r('app.string.detail_save_info_md'))
            .buttonStyle(ButtonStyleMode.NORMAL)
            .onClick(() => {
              this.saveInfo(true);
            })
          Button($r('app.string.detail_download_selected'))
            .buttonStyle(ButtonStyleMode.EMPHASIZED)
            .backgroundColor(Theme.red)
            .layoutWeight(1)
            .onClick(() => {
              this.downloadSelected();
            })
        }
        .width('100%')

        Row({ space: 8 }) {
          Button($r('app.string.detail_save_to_files'))
            .buttonStyle(ButtonStyleMode.NORMAL)
            .layoutWeight(1)
            .onClick(() => {
              this.saveDoneFiles();
            })
          // Security component: grants temp media-library write authorization on click.
          SaveButton({ icon: SaveIconStyle.FULL_FILLED, text: SaveDescription.SAVE, buttonType: ButtonType.Capsule })
            .onClick(async (event: ClickEvent, result: SaveButtonOnClickResult) => {
              if (result === SaveButtonOnClickResult.SUCCESS) {
                await this.saveDownloadedToGallery();
              }
            })
            .layoutWeight(1)
        }
        .width('100%')
      }
      .padding({ left: 12, right: 12, bottom: this.bottomAvoid + 12, top: 8 })
      .backgroundColor(Theme.pageBg)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.pageBg)
  }
}

@Component
struct RemoteThumb {
  url: string;
  label: Resource | string = '';

  build() {
    Stack({ alignContent: Alignment.BottomStart }) {
      if (this.url.length > 0) {
        Image(this.url)
          .objectFit(ImageFit.Cover)
          .width('100%')
          .aspectRatio(0.8)
          .borderRadius(12)
          .autoResize(true)
      } else {
        Column()
          .width('100%')
          .aspectRatio(0.8)
          .borderRadius(12)
          .backgroundColor('#22000000')
      }
      if (typeof this.label === 'string' ? this.label.length > 0 : true) {
        Text(this.label)
          .fontSize(10)
          .fontColor('#FFFFFF')
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(6)
          .backgroundColor('#99000000')
          .margin(6)
      }
    }
  }
}
