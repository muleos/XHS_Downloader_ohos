/**
 * 首页：已保存媒体的瀑布流信息流（参照小红书双列瀑布流），
 * 点击进入全屏查看器（左右滑动、保存到相册、删除）。
 */
import { fileIo } from '@kit.CoreFileKit';
import { AppContainer } from '../data/AppContainer';
import { SavedItem, WorkType, platformName } from '../model/SaveModels';
import { MediaSaver, FolderSaveRequest } from '../data/MediaSaver';
import { Theme, toast } from '../view/Common';

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
  @State viewerIndex: number = -1;
  @State confirmDelete: boolean = false;
  @State saving: boolean = false;
  @StorageLink('savedVersion') @Watch('onSavedChanged') savedVersion: number = 0;

  aboutToAppear(): void {
    this.reload();
  }

  onSavedChanged(): void {
    this.reload();
  }

  reload(): void {
    this.items = AppContainer.get().saved.getAll();
  }

  private fileUri(path: string): string {
    if (path.startsWith('file://') || path.startsWith('http')) {
      return path;
    }
    return 'file://' + path;
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

  build() {
    Stack() {
      Column() {
        // VHome 风格顶部：大标题 + 圆形按钮
        Row() {
          Column({ space: 2 }) {
            Text('收藏')
              .fontSize(26)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.textPrimary)
            Text(`已保存 ${this.items.length} 个作品`)
              .fontSize(13)
              .fontColor(Theme.textSecondary)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Circle({ width: 40, height: 40 })
            .fill(Theme.cardBg)
            .shadow({ radius: 6, color: 'rgba(0,0,0,0.06)', offsetY: 2 })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ left: 16, right: 16, top: this.topAvoid + 10, bottom: 10 })

        if (this.items.length === 0) {
          Column({ space: 10 }) {
            Text('📭').fontSize(52)
            Text('还没有保存的作品')
              .fontSize(15)
              .fontColor(Theme.textSecondary)
            Text('到「解析」页粘贴分享链接试试')
              .fontSize(13)
              .fontColor(Theme.textSecondary)
          }
          .width('100%')
          .margin({ top: 120 })
        } else {
          WaterFlow() {
            ForEach(this.items, (item: SavedItem) => {
              FlowItem() {
                FeedCard({
                  item: item,
                  onOpen: (): void => {
                    if (!item.hasMedia()) {
                      toast('该作品没有可查看的文件');
                      return;
                    }
                    this.viewerIndex = this.items.indexOf(item);
                    this.confirmDelete = false;
                  }
                })
              }
            }, (item: SavedItem) => item.id + '_' + item.mediaPaths.length)
          }
          .columnsTemplate('1fr 1fr')
          .columnsGap(8)
          .rowsGap(8)
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 12, right: 12, bottom: 96 })
        }
      }
      .width('100%')
      .height('100%')

      // 全屏查看器
      if (this.viewerIndex >= 0 && this.viewerIndex < this.items.length) {
        MediaViewer({
          item: this.items[this.viewerIndex],
          saving: this.saving,
          confirmDelete: this.confirmDelete,
          onClose: (): void => {
            this.viewerIndex = -1;
            this.confirmDelete = false;
          },
          onSave: (): void => {
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
    .backgroundColor(Theme.pageBg)
    .onAppear(() => {
      this.reload();
    })
  }
}

@Component
struct FeedCard {
  item: SavedItem = new SavedItem();
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
        Image(this.fileUri(this.item.coverOrFirst()))
          .width('100%')
          .height(this.cardHeight())
          .objectFit(ImageFit.Cover)
          .borderRadius({ topLeft: 14, topRight: 14, bottomLeft: 0, bottomRight: 0 })
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
      Column({ space: 4 }) {
        Text(this.item.title.length > 0 ? this.item.title : '未命名作品')
          .fontSize(13)
          .fontColor(Theme.textPrimary)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(platformName(this.item.platform) + (this.item.author.length > 0 ? ' · ' + this.item.author : ''))
          .fontSize(11)
          .fontColor(Theme.textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .padding(10)
    }
    .width('100%')
    .borderRadius(14)
    .backgroundColor(Theme.cardBg)
    .clip(true)
    .onClick(() => {
      this.onOpen();
    })
  }

  private cardHeight(): number {
    if (this.item.width > 0 && this.item.height > 0) {
      const ratio = this.item.height / this.item.width;
      return Math.min(Math.max(120, 170 * ratio), 260);
    }
    return 170;
  }
}

@Component
struct MediaViewer {
  item: SavedItem = new SavedItem();
  saving: boolean = false;
  confirmDelete: boolean = false;
  onClose: () => void = (): void => {};
  onSave: () => void = (): void => {};
  onDelete: () => void = (): void => {};
  @State current: number = 0;
  @StorageLink('topAvoid') topAvoid: number = 0;
  @StorageLink('bottomAvoid') bottomAvoid: number = 0;

  private fileUri(path: string): string {
    if (path.startsWith('file://') || path.startsWith('http')) {
      return path;
    }
    return 'file://' + path;
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      // 媒体区（全屏黑底）
      if (this.item.mediaPaths.length === 0) {
        Column({ space: 10 }) {
          Text('🖼').fontSize(48)
          Text('这个作品没有可查看的文件')
            .fontSize(15)
            .fontColor('#B0B0B0')
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        Swiper() {
          ForEach(this.item.mediaPaths, (p: string) => {
            Stack({ alignContent: Alignment.Bottom }) {
              if (this.item.workType === WorkType.VIDEO && p.endsWith('.mp4')) {
                Video({ src: this.fileUri(p) })
                  .controls(true)
                  .width('100%')
                  .height('100%')
                  .objectFit(ImageFit.Contain)
              } else {
                Image(this.fileUri(p))
                  .width('100%')
                  .height('100%')
                  .objectFit(ImageFit.Contain)
              }
              if (this.item.mediaPaths.length > 1) {
                Row() {
                  ForEach(this.item.mediaPaths, (_: string, idx: number) => {
                    Circle({ width: 6, height: 6 })
                      .fill(idx === this.current ? '#FFFFFF' : '#66FFFFFF')
                  }, (idx: number) => idx.toString())
                }
                .justifyContent(FlexAlign.Center)
                .width('100%')
                .padding({ bottom: 96 })
              }
            }
            .width('100%')
            .height('100%')
          }, (p: string) => p)
        }
        .index(this.current)
        .loop(false)
        .cachedCount(1)
        .indicator(false)
        .layoutWeight(1)
        .width('100%')
        .height('100%')
        .onChange((idx: number) => {
          this.current = idx;
        })
      }

      // 覆盖层：顶部圆形返回按钮 + 计数（VHome 圆形按钮风格）、
      // 底部悬浮操作条（保存主按钮 + 删除）。
      // 容器 hitTestBehavior=None：空隙处手势穿透给 Swiper，按钮仍可点。
      Column() {
        Row() {
          Stack() {
            Circle({ width: 40, height: 40 })
              .fill('#B3FFFFFF')
            Text('‹')
              .fontSize(24)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.textPrimary)
          }
          .width(40)
          .height(40)
          .onClick(() => {
            this.onClose();
          })

          Text(`${this.current + 1} / ${Math.max(1, this.item.mediaPaths.length)}`)
            .fontSize(14)
            .fontColor('#FFFFFF')
            .layoutWeight(1)
            .textAlign(TextAlign.Center)

          Stack() {
            Circle({ width: 40, height: 40 })
              .fill('#B3FFFFFF')
            Path()
              .commands('M12 4 V14 M8 10.5 L12 14.5 L16 10.5 M5.5 19 H18.5')
              .width(24)
              .height(24)
              .fill(Color.Transparent)
              .stroke(Theme.textPrimary)
              .strokeWidth(1.9)
              .strokeLineCap(LineCapStyle.Round)
              .strokeLineJoin(LineJoinStyle.Round)
          }
          .width(40)
          .height(40)
          .onClick(() => {
            this.onSave();
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ left: 16, right: 16, top: this.topAvoid + 10 })

        Blank()

        Row({ space: 12 }) {
          Button(this.saving ? '保存中…' : '保存到相册', { buttonStyle: ButtonStyleMode.NORMAL })
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .type(ButtonType.Capsule)
            .backgroundColor(Theme.blue)
            .fontColor('#FFFFFF')
            .height(44)
            .layoutWeight(1)
            .enabled(!this.saving)
            .onClick(() => {
              this.onSave();
            })
          Button(this.confirmDelete ? '再点一次确认' : '删除', { buttonStyle: ButtonStyleMode.NORMAL })
            .fontSize(15)
            .type(ButtonType.Capsule)
            .backgroundColor('#FFFFFF')
            .fontColor('#E5484D')
            .height(44)
            .width(120)
            .onClick(() => {
              this.onDelete();
            })
        }
        .width('100%')
        .padding({ left: 20, right: 20, bottom: this.bottomAvoid + 16 })
        .alignItems(VerticalAlign.Bottom)
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#101010')
  }
}
