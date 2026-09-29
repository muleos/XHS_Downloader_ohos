import { pasteboard } from '@kit.BasicServicesKit';
import { AppContainer } from '../data/AppContainer';
import { DownloadRecord } from '../core/models';
import { Theme, TitleBar, toast } from '../view/Common';

@Entry
@Component
struct History {
  @StorageLink('topAvoid') topAvoid: number = 0;
  @StorageLink('bottomAvoid') bottomAvoid: number = 0;
  @StorageLink('leftAvoid') leftAvoid: number = 0;
  @StorageLink('rightAvoid') rightAvoid: number = 0;
  @State records: DownloadRecord[] = [];

  aboutToAppear(): void {
    this.records = AppContainer.get().records.all();
  }

  private fmtTime(ts: number): string {
    if (ts <= 0) {
      return '';
    }
    const d = new Date(ts);
    const p = (n: number): string => (n < 10 ? '0' + n : String(n));
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`;
  }

  build() {
    Column() {
      TitleBar({ title: $r('app.string.history_title'), showBack: true })

      if (this.records.length === 0) {
        Column() {
          Text($r('app.string.history_empty')).fontSize(14).fontColor(Theme.textSecondary)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 8 }) {
          ForEach(this.records, (r: DownloadRecord) => {
            ListItem() {
              Column({ space: 4 }) {
                Text(r.title.length > 0 ? r.title : r.noteId)
                  .fontSize(15)
                  .fontColor(Theme.textPrimary)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(r.author + ' · ' + this.fmtTime(r.createdAt) + ' · ' + r.state)
                  .fontSize(12)
                  .fontColor(Theme.textSecondary)
                Row({ space: 8 }) {
                  Button($r('app.string.history_copy_link'), { buttonStyle: ButtonStyleMode.NORMAL })
                    .height(32)
                    .fontSize(12)
                    .onClick(() => {
                      const data = pasteboard.createData(pasteboard.MimeType.PLAIN_TEXT,
                        'https://www.xiaohongshu.com/explore/' + r.noteId);
                      pasteboard.getSystemPasteboard().setData(data).then(() => {
                        toast($r('app.string.common_copied'));
                      });
                    })
                  Button($r('app.string.history_delete'), { buttonStyle: ButtonStyleMode.TEXTUAL })
                    .height(32)
                    .fontSize(12)
                    .fontColor(Theme.red)
                    .onClick(() => {
                      AppContainer.get().records.remove(r.taskId).then(() => {
                        this.records = AppContainer.get().records.all();
                      });
                    })
                }
                .width('100%')
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
              .padding(12)
              .borderRadius(12)
              .backgroundColor(Theme.cardBg)
            }
          }, (r: DownloadRecord) => r.taskId + '_' + r.mediaId)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 12, right: 12, bottom: this.bottomAvoid })
        .scrollBar(BarState.Off)
      }
    }
    .padding({ left: this.leftAvoid, right: this.rightAvoid, top: this.topAvoid })
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.pageBg)
  }
}
