/**
 * 归档与记录（v1.20.0）：安卓版 DownloadSettingsRoute section 1 对应页。
 * 跳过已存在 / 按作者归档 / 按作品归档 / 记录发布时间 + 记录导出与清空。
 */
import { AppContainer } from '../data/AppContainer';
import { MediaSaver, StoredOutput } from '../data/MediaSaver';
import { AppSettings } from '../core/models';
import { FrostScaffold } from '../view/FrostScaffold';
import { Theme, ToggleRow, toast } from '../view/Common';

@Entry
@Component
struct ArchiveSettings {
  @State settings: AppSettings = new AppSettings();
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    const app = AppContainer.get();
    this.settings = app.settings.get();
    app.settings.onChange((s: AppSettings) => {
      this.settings = s;
    });
  }

  private async set(mutate: (s: AppSettings) => void): Promise<void> {
    this.settings = await AppContainer.get().settings.update(mutate);
  }

  private exportRecords(json: boolean): void {
    const app = AppContainer.get();
    const text = app.records.exportText(json);
    const stamp = new Date().toISOString().replace(/[-:T]/g, '').substring(0, 14);
    const name = 'xhsdn_records_' + stamp + (json ? '.json' : '.csv');
    MediaSaver.storeText(getContext(this), [], name, text).then((out: StoredOutput) => {
      toast(out.skipped ? '导出失败' : '已导出记录');
    });
  }

  build() {
    Stack() {
      FrostScaffold({ title: '归档与记录', scroller: this.scroller, bgColor: Theme.pageBg }) {
      Scroll(this.scroller) {
        Column({ space: 12 }) {
          Column() {
            ToggleRow({
              label: '跳过已存在的文件',
              desc: '同名文件已保存过时不再重复下载。',
              on: this.settings.downloadOptions.skipExisting,
              onChange: (v: boolean): void => {
                this.set((s: AppSettings) => {
                  s.downloadOptions.skipExisting = v;
                });
              }
            })
            Divider().color(Theme.pageBg)
            ToggleRow({
              label: '按作者归档',
              on: this.settings.downloadOptions.authorArchive,
              onChange: (v: boolean): void => {
                this.set((s: AppSettings) => {
                  s.downloadOptions.authorArchive = v;
                });
              }
            })
            Divider().color(Theme.pageBg)
            ToggleRow({
              label: '按作品归档',
              on: this.settings.downloadOptions.noteArchive,
              onChange: (v: boolean): void => {
                this.set((s: AppSettings) => {
                  s.downloadOptions.noteArchive = v;
                });
              }
            })
            Divider().color(Theme.pageBg)
            ToggleRow({
              label: '记录文件发布时间',
              desc: '导出的信息文件里附带作品发布时间。',
              on: this.settings.downloadOptions.writePublishTime,
              onChange: (v: boolean): void => {
                this.set((s: AppSettings) => {
                  s.downloadOptions.writePublishTime = v;
                });
              }
            })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 6, bottom: 6 })
          .borderRadius(16)
          .backgroundColor(Theme.cardBg)

          Column() {
            Row({ space: 8 }) {
              Button('导出 JSON', { buttonStyle: ButtonStyleMode.NORMAL })
                .layoutWeight(1)
                .fontSize(13)
                .onClick(() => {
                  this.exportRecords(true);
                })
              Button('导出 CSV', { buttonStyle: ButtonStyleMode.NORMAL })
                .layoutWeight(1)
                .fontSize(13)
                .onClick(() => {
                  this.exportRecords(false);
                })
            }
            .width('100%')
            Button('清空全部下载记录', { buttonStyle: ButtonStyleMode.TEXTUAL })
              .fontColor(Theme.red)
              .onClick(() => {
                AppContainer.get().records.clear();
                toast('已清空全部记录');
              })
          }
          .alignItems(HorizontalAlign.Center)
          .width('100%')
          .padding(16)
          .borderRadius(16)
          .backgroundColor(Theme.cardBg)

          Text('下载记录可在「我的 → 下载历史」中查看与管理。')
            .fontSize(12)
            .fontColor(Theme.textSecondary)
            .width('100%')
            .padding({ left: 8, bottom: (AppStorage.get<number>('bottomAvoid') ?? 0) + 24 })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8 })
      }
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
      .width('100%')
      .height('100%')
      }
    }
    .width('100%')
    .height('100%')
  }
}
