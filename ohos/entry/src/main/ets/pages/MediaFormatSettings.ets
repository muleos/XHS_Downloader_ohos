/**
 * 媒体与格式（v1.20.0）：一比一复刻安卓版 DownloadSettingsRoute section 0。
 * 设置仅用于新任务；已暂停的任务保留提交时的设置。
 * 下载图片/视频开关由 AppContainer 同步给 MultiDownloader（多平台下载通道生效）。
 */
import { AppContainer } from '../data/AppContainer';
import { AppSettings, VideoPreference, ImageFormat, LivePhotoMode, LivePhotoFormat } from '../core/models';
import { FrostScaffold } from '../view/FrostScaffold';
import { Theme, ToggleRow, SelectorRow, SheetState, OptionSheetOverlay } from '../view/Common';

@Entry
@Component
struct MediaFormatSettings {
  @State settings: AppSettings = new AppSettings();
  /** 选项选择浮层（安卓 Spinner 同款交互） */
  @State sheet: SheetState = new SheetState();
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

  /** 打开选项浮层 */
  private pick(title: string, labels: string[], selected: number,
    onSel: (idx: number) => void): void {
    this.sheet.title = title;
    this.sheet.labels = labels;
    this.sheet.selectedIndex = selected;
    this.sheet.onSelect = onSel;
    this.sheet.open = true;
  }

  private imageFormatLabels(): string[] {
    return ['自动（原始格式）', 'JPEG', 'PNG', 'WEBP'];
  }

  private videoPrefLabels(): string[] {
    return ['分辨率', '码率', '体积', '兼容性'];
  }

  private liveModeLabels(): string[] {
    return ['合成为动态照片', '分开保存', '仅保存静态图'];
  }

  private liveFormatLabels(): string[] {
    return ['自动（当前设备）', '标准', '小米', 'OPPO（一加）', '三星', 'vivo', 'vivo 旧版', '华为'];
  }

  private bottomAvoid(): number {
    const v = AppStorage.get<number>('bottomAvoid');
    return v === undefined ? 0 : v;
  }

  build() {
    Stack() {
      FrostScaffold({ title: '媒体与格式', scroller: this.scroller, bgColor: Theme.pageBg }) {
        Scroll(this.scroller) {
          Column({ space: 12 }) {
            Text('设置仅用于新任务；已暂停的任务保留提交时的设置。')
              .fontSize(13)
              .fontColor(Theme.textSecondary)
              .width('100%')

            Column() {
              ToggleRow({
                label: '下载图片',
                on: this.settings.downloadOptions.imageDownload,
                onChange: (v: boolean): void => {
                  this.set((s: AppSettings) => {
                    s.downloadOptions.imageDownload = v;
                  });
                }
              })
              Divider().color(Theme.pageBg)
              ToggleRow({
                label: '下载视频',
                on: this.settings.downloadOptions.videoDownload,
                onChange: (v: boolean): void => {
                  this.set((s: AppSettings) => {
                    s.downloadOptions.videoDownload = v;
                  });
                }
              })
              Divider().color(Theme.pageBg)
              ToggleRow({
                label: '保存视频封面',
                on: this.settings.downloadOptions.videoCoverDownload,
                onChange: (v: boolean): void => {
                  this.set((s: AppSettings) => {
                    s.downloadOptions.videoCoverDownload = v;
                  });
                }
              })
              Divider().color(Theme.pageBg)
              ToggleRow({
                label: '下载评论区图片',
                desc: '包含已加载评论和回复中的图片，不自动获取尚未加载的评论。',
                on: this.settings.downloadOptions.commentImageDownload,
                onChange: (v: boolean): void => {
                  this.set((s: AppSettings) => {
                    s.downloadOptions.commentImageDownload = v;
                  });
                }
              })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 6, bottom: 6 })
            .borderRadius(16)
            .backgroundColor(Theme.cardBg)

            Column() {
              SelectorRow({
                label: '图片格式',
                value: this.imageFormatLabels()[this.settings.downloadOptions.imageFormat as number],
                showArrow: false,
                onTap: (): void => {
                  this.pick('图片格式', this.imageFormatLabels(),
                    this.settings.downloadOptions.imageFormat as number, (idx: number): void => {
                      this.set((s: AppSettings) => {
                        s.downloadOptions.imageFormat = idx as ImageFormat;
                      });
                    });
                }
              })
              Divider().color(Theme.pageBg)
              SelectorRow({
                label: '视频优先级',
                value: this.videoPrefLabels()[this.settings.downloadOptions.videoPreference as number],
                showArrow: false,
                onTap: (): void => {
                  this.pick('视频优先级', this.videoPrefLabels(),
                    this.settings.downloadOptions.videoPreference as number, (idx: number): void => {
                      this.set((s: AppSettings) => {
                        s.downloadOptions.videoPreference = idx as VideoPreference;
                      });
                    });
                }
              })
              Divider().color(Theme.pageBg)
              SelectorRow({
                label: '实况照片保存方式',
                value: this.liveModeLabels()[this.settings.downloadOptions.livePhotoMode as number],
                showArrow: false,
                onTap: (): void => {
                  this.pick('实况照片保存方式', this.liveModeLabels(),
                    this.settings.downloadOptions.livePhotoMode as number, (idx: number): void => {
                      this.set((s: AppSettings) => {
                        s.downloadOptions.livePhotoMode = idx as LivePhotoMode;
                      });
                    });
                }
              })
              Divider().color(Theme.pageBg)
              SelectorRow({
                label: '实况合成格式',
                value: this.liveFormatLabels()[this.settings.downloadOptions.livePhotoFormat as number],
                showArrow: false,
                onTap: (): void => {
                  this.pick('实况合成格式', this.liveFormatLabels(),
                    this.settings.downloadOptions.livePhotoFormat as number, (idx: number): void => {
                      this.set((s: AppSettings) => {
                        s.downloadOptions.livePhotoFormat = idx as LivePhotoFormat;
                      });
                    });
                }
              })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 6, bottom: 6 })
            .borderRadius(16)
            .backgroundColor(Theme.cardBg)

            // 安卓版同款页脚说明
            Column({ space: 6 }) {
              Text('请求格式不可用时按实际返回格式保存。')
              Text('兼容性优先尝试 H.264；其他模式先尝试原始视频，再按优先级尝试其他规格与备用地址。')
              Text('合成失败时保留独立图片和视频，并在任务中提示。')
              Text('用于合成动态照片。自动模式按设备品牌选择合成格式，其他模式用于跨设备分享或特殊需求。')
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding({ left: 8, right: 8, bottom: this.bottomAvoid() + 24 })
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 8 })
        }
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
        .width('100%')
        .height('100%')
      }

      OptionSheetOverlay({ sheet: this.sheet })
    }
    .width('100%')
    .height('100%')
  }
}
