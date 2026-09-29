import { router } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { AppContainer } from '../data/AppContainer';
import { MediaSaver } from '../data/MediaSaver';
import { Theme, TitleBar, toast } from '../view/Common';
import { ResolvedNote, ResolvedNoteItem, DownloadOptions } from '../core/models';
import { NamingFormat } from '../core/NamingFormat';
import { NoteOutput } from '../core/NoteOutput';

@Entry
@Component
struct NoteDetail {
  @StorageLink('topAvoid') topAvoid: number = 0;
  @StorageLink('bottomAvoid') bottomAvoid: number = 0;
  @StorageLink('leftAvoid') leftAvoid: number = 0;
  @StorageLink('rightAvoid') rightAvoid: number = 0;
  @State note: ResolvedNote = new ResolvedNote();
  @State selected: boolean[] = [];
  @State taskId: number = 0;
  @State progress: number = 0;

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, Object> | undefined;
    if (params !== undefined) {
      this.taskId = Number(params['taskId'] ?? 0);
      this.note = ResolvedNote.fromBundle(params['note'] as Record<string, Object>);
    }
    this.selected = this.note.items.map((item: ResolvedNoteItem): boolean => {
      return !(item.image !== null && item.image.commentId.length > 0);
    });
  }

  private confirmSelection(): void {
    const ids: number[] = [];
    for (let i = 0; i < this.selected.length; i++) {
      if (this.selected[i]) {
        ids.push(i);
      }
    }
    if (ids.length === 0) {
      toast($r('app.string.error_no_selection'));
      return;
    }
    AppContainer.get().queue.confirmSelection(this.taskId, ids);
    toast($r('app.string.detail_download_started'));
  }

  private async saveInfo(markdown: boolean): Promise<void> {
    const app = AppContainer.get();
    const options: DownloadOptions = app.settings.get().downloadOptions;
    const folders = NoteOutput.folders(this.note, options, app.tasks.remark(this.note.authorId));
    const base = NoteOutput.fileName(this.note, app.settings.get(), 0, 'txt', Date.now());
    const ok = await MediaSaver.saveTextFile(getContext(this), base + (markdown ? '.md' : '.txt'),
      NoteOutput.text(this.note, markdown));
    toast(ok ? $r('app.string.detail_info_saved') : $r('app.string.error_network'));
  }

  private copyText(): void {
    const text = this.note.body.length > 0 ? this.note.body : this.note.description;
    const paste = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(paste).then(() => {
      toast($r('app.string.common_copied'));
    });
  }

  private async saveToGallery(): Promise<void> {
    const saved = await AppContainer.get().queue.saveCompleted(getContext(this), this.taskId);
    toast(saved > 0 ? $r('app.string.common_saved') : $r('app.string.error_no_selection'));
  }

  build() {
    Column() {
      TitleBar({ title: this.note.title.length > 0 ? this.note.title : this.note.noteId, showBack: true })

      Scroll {
        Column({ space: 10 }) {
          Text(this.note.authorName + ' · ' + this.note.publishTime)
            .fontSize(12)
            .fontColor(Theme.textSecondary)
            .width('100%')

          Grid() {
            ForEach(this.note.items, (item: ResolvedNoteItem, index: number) => {
              GridItem() {
                Column({ space: 6 }) {
                  Stack({ alignContent: Alignment.TopEnd }) {
                    RemoteThumb({ url: this.thumbUrlFor(item), label: this.tagFor(item) })
                    Checkbox()
                      .select(this.selected[index])
                      .selectedColor(Theme.red)
                      .width(20)
                      .height(20)
                      .onChange((on: boolean) => {
                        this.selected[index] = on;
                      })
                      .margin(6)
                  }
                  if (item.image !== null && item.image.width > 0) {
                    Text(item.image.width + '×' + item.image.height)
                      .fontSize(10)
                      .fontColor(Theme.textSecondary)
                  }
                }
              }
            }, (item: ResolvedNoteItem, index: number) => index + '_' + item.kind)
          }
          .columnsTemplate('1fr 1fr')
          .columnsGap(10)
          .rowsGap(10)
          .width('100%')

          Text(this.note.body)
            .fontSize(14)
            .fontColor(Theme.textPrimary)
            .width('100%')

          Row({ space: 8 }) {
            Button($r('app.string.detail_copy_text'), { buttonStyle: ButtonStyleMode.NORMAL })
              .layoutWeight(1)
              .fontSize(13)
              .onClick(() => {
                this.copyText();
              })
            Button($r('app.string.detail_save_info_txt'), { buttonStyle: ButtonStyleMode.NORMAL })
              .layoutWeight(1)
              .fontSize(13)
              .onClick(() => {
                this.saveInfo(false);
              })
            Button($r('app.string.detail_save_info_md'), { buttonStyle: ButtonStyleMode.NORMAL })
              .layoutWeight(1)
              .fontSize(13)
              .onClick(() => {
                this.saveInfo(true);
              })
          }
          .width('100%')
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 4, bottom: this.bottomAvoid + 120 })
      }
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)

      Row({ space: 10 }) {
        Button($r('app.string.detail_selected_count') + ': ' + this.countSelected(), { buttonStyle: ButtonStyleMode.NORMAL })
          .layoutWeight(1)
          .fontSize(13)
          .onClick(() => {
            for (let i = 0; i < this.selected.length; i++) {
              this.selected[i] = true;
            }
          })
        SaveButton()
          .onClick((event: ClickEvent, result: SaveButtonOnClickResult) => {
            if (result === SaveButtonOnClickResult.SUCCESS) {
              this.saveToGallery();
            }
          })
          .backgroundColor(Theme.red)
        Button($r('app.string.detail_download_selected'), { buttonStyle: ButtonStyleMode.EMPHASIZED })
          .layoutWeight(1)
          .fontSize(13)
          .backgroundColor(Theme.red)
          .onClick(() => {
            this.confirmSelection();
          })
      }
      .width('100%')
      .padding({ left: 14, right: 14, bottom: this.bottomAvoid + 12, top: 8 })
      .backgroundColor(Theme.cardBg)
    }
    .padding({ left: this.leftAvoid, right: this.rightAvoid, top: this.topAvoid })
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.pageBg)
  }

  private countSelected(): number {
    let n = 0;
    for (const on of this.selected) {
      if (on) {
        n++;
      }
    }
    return n;
  }

  private thumbUrlFor(item: ResolvedNoteItem): string {
    if (item.image !== null) {
      return item.image.previewUrl.length > 0 ? item.image.previewUrl : item.image.sourceUrl;
    }
    if (item.video !== null) {
      return item.video.previewUrl;
    }
    if (item.live !== null) {
      return item.live.image.previewUrl;
    }
    return '';
  }

  private tagFor(item: ResolvedNoteItem): ResourceStr {
    if (item.kind === 'video') {
      return $r('app.string.detail_video_tag');
    }
    if (item.kind === 'live') {
      return $r('app.string.detail_live_photo_tag');
    }
    if (item.image !== null && item.image.commentId.length > 0) {
      return $r('app.string.detail_comment_tag');
    }
    return '';
  }
}

@Component
struct RemoteThumb {
  url: string = '';
  label: ResourceStr = '';

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
      if (this.label !== '') {
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
