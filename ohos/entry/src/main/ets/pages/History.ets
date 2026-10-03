/**
 * 下载历史：持久化记录列表 + 批量管理（选择/全选/删除所选/清空）。
 * v1.19.0：历史持久化修复后，此处增加批量删除能力。
 */
import { pasteboard } from '@kit.BasicServicesKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
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
  /** 批量管理模式：true 时点击行为切换选中，底部出现批量操作条 */
  @State batchMode: boolean = false;
  /** 已选中的 taskId 集合（@State 数组驱动 UI 刷新） */
  @State selected: number[] = [];

  aboutToAppear(): void {
    this.refresh();
  }

  private refresh(): void {
    this.records = AppContainer.get().records.all();
  }

  private isSelected(taskId: number): boolean {
    return this.selected.indexOf(taskId) >= 0;
  }

  private toggleSelect(taskId: number): void {
    if (this.isSelected(taskId)) {
      this.selected = this.selected.filter((v: number): boolean => v !== taskId);
    } else {
      this.selected.push(taskId);
    }
  }

  private toggleBatch(): void {
    this.batchMode = !this.batchMode;
    this.selected = [];
  }

  private selectAll(): void {
    if (this.selected.length === this.records.length) {
      this.selected = [];
      return;
    }
    const ids: number[] = [];
    for (const r of this.records) {
      ids.push(r.taskId);
    }
    this.selected = ids;
  }

  private deleteSelected(): void {
    if (this.selected.length === 0) {
      toast('请先选择要删除的记录');
      return;
    }
    const doomed = this.selected;
    AppContainer.get().records.removeBatch(doomed);
    this.selected = [];
    this.refresh();
    toast(`已删除 ${doomed.length} 条记录`);
  }

  private clearAll(): void {
    AppContainer.get().records.clear();
    this.selected = [];
    this.batchMode = false;
    this.refresh();
    toast('已清空全部记录');
  }

  private copyLink(noteId: string): void {
    const data = pasteboard.createData(utd.UniformDataType.PLAIN_TEXT,
      'https://www.xiaohongshu.com/explore/' + noteId);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      toast($r('app.string.common_copied'));
    });
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

      // 工具条：批量管理开关 + 全选（批量态下显示）
      Row({ space: 10 }) {
        Text(this.batchMode ? '退出批量管理' : '批量管理')
          .fontSize(13)
          .fontColor(Theme.accent)
          .onClick(() => {
            this.toggleBatch();
          })
        Blank()
        if (this.batchMode && this.records.length > 0) {
          Text(this.selected.length === this.records.length ? '取消全选' : '全选')
            .fontSize(13)
            .fontColor(Theme.textPrimary)
            .onClick(() => {
              this.selectAll();
            })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 4, bottom: 8 })

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
              Row({ space: 10 }) {
                // 批量态勾选圈
                if (this.batchMode) {
                  Stack() {
                    if (this.isSelected(r.taskId)) {
                      SymbolGlyph($r('sys.symbol.checkmark'))
                        .fontSize(14)
                        .fontColor([Theme.accent])
                    }
                  }
                  .width(22)
                  .height(22)
                  .borderRadius(11)
                  .backgroundColor(this.isSelected(r.taskId) ? Theme.accent : Color.Transparent)
                  .border({ width: 1.5, color: this.isSelected(r.taskId) ? Theme.accent : Theme.textSecondary })
                  .onClick(() => {
                    this.toggleSelect(r.taskId);
                  })
                }

                Column({ space: 4 }) {
                  Text(r.title.length > 0 ? r.title : r.noteId)
                    .fontSize(15)
                    .fontColor(Theme.textPrimary)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(r.author + ' · ' + this.fmtTime(r.createdAt) + ' · ' + r.state)
                    .fontSize(12)
                    .fontColor(Theme.textSecondary)
                  if (!this.batchMode) {
                    Row({ space: 8 }) {
                      Button($r('app.string.history_copy_link'), { buttonStyle: ButtonStyleMode.NORMAL })
                        .height(32)
                        .fontSize(12)
                        .onClick(() => {
                          this.copyLink(r.noteId);
                        })
                      Button($r('app.string.history_delete'), { buttonStyle: ButtonStyleMode.TEXTUAL })
                        .height(32)
                        .fontSize(12)
                        .fontColor(Theme.red)
                        .onClick(() => {
                          AppContainer.get().records.remove(r.taskId);
                          this.refresh();
                        })
                    }
                    .width('100%')
                  }
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
              }
              .width('100%')
              .padding(12)
              .borderRadius(12)
              .backgroundColor(Theme.cardBg)
              .onClick(() => {
                if (this.batchMode) {
                  this.toggleSelect(r.taskId);
                }
              })
            }
          }, (r: DownloadRecord) => r.taskId + '_' + r.state + '_' + this.batchMode + '_' + this.isSelected(r.taskId))
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 12, right: 12, bottom: this.bottomAvoid + (this.batchMode ? 76 : 8) })
        .scrollBar(BarState.Off)
      }

      // 批量操作条（毛玻璃，悬浮于列表之上）
      if (this.batchMode && this.selected.length > 0) {
        Row({ space: 12 }) {
          Text(`已选 ${this.selected.length} 条`)
            .fontSize(13)
            .fontColor(Theme.textPrimary)
            .layoutWeight(1)
          Button($r('app.string.history_clear'), { buttonStyle: ButtonStyleMode.TEXTUAL })
            .fontSize(13)
            .fontColor(Theme.textSecondary)
            .onClick(() => {
              this.clearAll();
            })
          Button('删除所选', { buttonStyle: ButtonStyleMode.EMPHASIZED })
            .fontSize(13)
            .fontColor(Color.White)
            .backgroundColor(Theme.accent)
            .onClick(() => {
              this.deleteSelected();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: this.bottomAvoid + 10 })
        .backgroundColor(Theme.glassBg)
        .backgroundBlurStyle(BlurStyle.Regular)
        .border({ width: 0.5, color: Theme.glassBorder })
        .alignItems(VerticalAlign.Center)
      }
    }
    .padding({ left: this.leftAvoid, right: this.rightAvoid, top: this.topAvoid })
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.pageBg)
  }
}
