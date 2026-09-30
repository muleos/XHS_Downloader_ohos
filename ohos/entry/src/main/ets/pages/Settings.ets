import { router } from '@kit.ArkUI';
import { AppContainer } from '../data/AppContainer';
import { MediaSaver, StoredOutput } from '../data/MediaSaver';
import { AppSettings, VideoPreference, ImageFormat, LivePhotoMode } from '../core/models';
import { Theme, SectionCard, toast } from '../view/Common';
import { FrostScaffold } from '../view/FrostScaffold';

@Entry
@Component
struct Settings {
  @StorageLink('topAvoid') topAvoid: number = 0;
  @StorageLink('bottomAvoid') bottomAvoid: number = 0;
  @StorageLink('leftAvoid') leftAvoid: number = 0;
  @StorageLink('rightAvoid') rightAvoid: number = 0;
  @State settings: AppSettings = new AppSettings();
  /** 页面主滚动源（官方标题栏滚动渐变模糊绑定） */
  private topScroller: Scroller = new Scroller();

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

  build() {
    Column() {
      // VHome 同款官方磨砂标题栏（FrostScaffold：官方材质 + 滚动渐变模糊）
      FrostScaffold({ title: '设置', scroller: this.topScroller, bgColor: Theme.pageBg }) {
      Scroll(this.topScroller) {
        Column({ space: 12 }) {
          SectionCard() {
            Text($r('app.string.settings_media_format'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.textPrimary)
            SelectorRow({
              label: $r('app.string.settings_video_preference'),
              value: this.vpLabel(),
              onTap: (): void => {
                this.cycleVideoPreference();
              }
            })
            SelectorRow({
              label: $r('app.string.settings_image_format'),
              value: this.ifLabel(),
              onTap: (): void => {
                this.cycleImageFormat();
              }
            })
            ToggleRow({
              label: $r('app.string.settings_video_cover'),
              on: this.settings.downloadOptions.videoCoverDownload,
              onChange: (v: boolean): void => {
                this.set((s: AppSettings) => {
                  s.downloadOptions.videoCoverDownload = v;
                });
              }
            })
            ToggleRow({
              label: $r('app.string.settings_comment_images'),
              on: this.settings.downloadOptions.commentImageDownload,
              onChange: (v: boolean): void => {
                this.set((s: AppSettings) => {
                  s.downloadOptions.commentImageDownload = v;
                });
              }
            })
            SelectorRow({
              label: $r('app.string.settings_live_photo_mode'),
              value: this.lpLabel(),
              onTap: (): void => {
                this.cycleLiveMode();
              }
            })
          }

          SectionCard() {
            Text($r('app.string.settings_task_group'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.textPrimary)
            ValueRow({
              label: $r('app.string.settings_timeout_seconds'),
              value: String(this.settings.downloadOptions.timeoutSeconds),
              onChange: (v: string): void => {
                this.set((s: AppSettings) => {
                  s.downloadOptions.timeoutSeconds = Math.max(5, Math.min(300, Number(v) || 45));
                });
              }
            })
            ValueRow({
              label: $r('app.string.settings_max_retries'),
              value: String(this.settings.downloadOptions.maxRetries),
              onChange: (v: string): void => {
                this.set((s: AppSettings) => {
                  s.downloadOptions.maxRetries = Math.max(0, Math.min(10, Number(v) || 3));
                });
              }
            })
          }

          SectionCard() {
            Text($r('app.string.settings_network_group'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.textPrimary)
            ToggleRow({
              label: $r('app.string.settings_use_web_session'),
              on: this.settings.downloadOptions.useWebSession,
              onChange: (v: boolean): void => {
                this.set((s: AppSettings) => {
                  s.downloadOptions.useWebSession = v;
                });
              }
            })
            ValueRow({
              label: $r('app.string.settings_proxy'),
              value: this.settings.downloadOptions.proxy,
              onChange: (v: string): void => {
                this.set((s: AppSettings) => {
                  s.downloadOptions.proxy = v.trim();
                });
              }
            })
            ToggleRow({
              label: $r('app.string.settings_proxy_download'),
              on: this.settings.downloadOptions.proxyDownload,
              onChange: (v: boolean): void => {
                this.set((s: AppSettings) => {
                  s.downloadOptions.proxyDownload = v;
                });
              }
            })
          }

          SectionCard() {
            Text($r('app.string.settings_naming_group'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.textPrimary)
            ToggleRow({
              label: $r('app.string.settings_use_custom_naming'),
              on: this.settings.useCustomNamingFormat,
              onChange: (v: boolean): void => {
                this.set((s: AppSettings) => {
                  s.useCustomNamingFormat = v;
                });
              }
            })
            ValueRow({
              label: $r('app.string.settings_naming_template'),
              value: this.settings.customNamingTemplate,
              onChange: (v: string): void => {
                this.set((s: AppSettings) => {
                  s.customNamingTemplate = v;
                });
              }
            })
            Text($r('app.string.settings_naming_tokens'))
              .fontSize(12)
              .fontColor(Theme.textSecondary)
          }

          SectionCard() {
            Text($r('app.string.settings_session_group'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.textPrimary)
            SelectorRow({
              label: $r('app.string.settings_open_web_session'),
              value: '',
              onTap: (): void => {
                router.pushUrl({ url: 'pages/WebSession' });
              }
            })
            Button($r('app.string.settings_clear_session'), { buttonStyle: ButtonStyleMode.NORMAL })
              .onClick(() => {
                AppContainer.get().client.clearSession();
                toast($r('app.string.settings_saved'));
              })
          }

          SectionCard() {
            Text($r('app.string.settings_record_group'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.textPrimary)
            Row({ space: 8 }) {
              Button($r('app.string.settings_export_json'), { buttonStyle: ButtonStyleMode.NORMAL })
                .layoutWeight(1)
                .onClick(() => {
                  this.exportRecords(true);
                })
              Button($r('app.string.settings_export_csv'), { buttonStyle: ButtonStyleMode.NORMAL })
                .layoutWeight(1)
                .onClick(() => {
                  this.exportRecords(false);
                })
            }
            .width('100%')
            Button($r('app.string.settings_clear_records'), { buttonStyle: ButtonStyleMode.TEXTUAL })
              .fontColor(Theme.red)
              .onClick(() => {
                AppContainer.get().records.clear();
                toast($r('app.string.settings_saved'));
              })
          }

          SectionCard() {
            Text($r('app.string.settings_about_group'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.textPrimary)
            Text($r('app.string.settings_about_source')).fontSize(12).fontColor(Theme.textSecondary)
            Text($r('app.string.settings_about_upstream')).fontSize(12).fontColor(Theme.textSecondary)
          }
        }
        .padding({
          left: this.leftAvoid > 0 ? this.leftAvoid : 12,
          right: this.rightAvoid > 0 ? this.rightAvoid : 12,
          top: this.topAvoid + 60,
          bottom: this.bottomAvoid + 24
        })
      }
      .scrollBar(BarState.Off)
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      }
    }
    .width('100%')
    .height('100%')
  }

  private vpLabel(): ResourceStr {
    switch (this.settings.downloadOptions.videoPreference) {
      case VideoPreference.BITRATE:
        return $r('app.string.settings_video_pref_bitrate');
      case VideoPreference.SIZE:
        return $r('app.string.settings_video_pref_size');
      case VideoPreference.COMPATIBILITY:
        return $r('app.string.settings_video_pref_compatibility');
      default:
        return $r('app.string.settings_video_pref_resolution');
    }
  }

  private ifLabel(): ResourceStr {
    switch (this.settings.downloadOptions.imageFormat) {
      case ImageFormat.JPEG:
        return 'JPEG';
      case ImageFormat.PNG:
        return 'PNG';
      case ImageFormat.WEBP:
        return 'WEBP';
      default:
        return $r('app.string.settings_image_format_auto');
    }
  }

  private lpLabel(): ResourceStr {
    switch (this.settings.downloadOptions.livePhotoMode) {
      case LivePhotoMode.SEPARATE:
        return $r('app.string.settings_live_mode_separate');
      case LivePhotoMode.STILL:
        return $r('app.string.settings_live_mode_still');
      default:
        return $r('app.string.settings_live_mode_merged');
    }
  }

  private cycleVideoPreference(): void {
    this.set((s: AppSettings) => {
      const next = ((s.downloadOptions.videoPreference as number) + 1) % 4;
      s.downloadOptions.videoPreference = next as VideoPreference;
    });
  }

  private cycleImageFormat(): void {
    this.set((s: AppSettings) => {
      const next = ((s.downloadOptions.imageFormat as number) + 1) % 4;
      s.downloadOptions.imageFormat = next as ImageFormat;
    });
  }

  private cycleLiveMode(): void {
    this.set((s: AppSettings) => {
      const next = ((s.downloadOptions.livePhotoMode as number) + 1) % 3;
      s.downloadOptions.livePhotoMode = next as LivePhotoMode;
    });
  }

  private exportRecords(json: boolean): void {
    const app = AppContainer.get();
    const text = app.records.exportText(json);
    const stamp = new Date().toISOString().replace(/[-:T]/g, '').substring(0, 14);
    const name = 'xhsdn_records_' + stamp + (json ? '.json' : '.csv');
    MediaSaver.storeText(getContext(this), [], name, text).then((out: StoredOutput) => {
      toast(out.skipped ? $r('app.string.error_network') : $r('app.string.common_saved'));
    });
  }
}

/**
 * 设置行组件（替代原 @Builder 按值传参）：
 * 自定义组件在父组件状态变化时会同步更新入参，实现实时刷新。
 */
@Component
struct SelectorRow {
  label: ResourceStr = '';
  value: ResourceStr = '';
  onTap: () => void = (): void => {};

  build() {
    Row() {
      Text(this.label).fontSize(15).fontColor(Theme.textPrimary).layoutWeight(1)
      Text(this.value).fontSize(14).fontColor(Theme.accent)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(15)
        .fontColor([Theme.textSecondary])
        .margin({ left: 6 })
    }
    .width('100%')
    .height(48)
    .onClick(() => {
      this.onTap();
    })
  }
}

/** 整行可点（48 高度热区），开关本身只做展示，避免与行点击重复触发。 */
@Component
struct ToggleRow {
  label: ResourceStr = '';
  on: boolean = false;
  onChange: (v: boolean) => void = (): void => {};

  build() {
    Row() {
      Text(this.label).fontSize(15).fontColor(Theme.textPrimary).layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.on })
        .selectedColor(Theme.accent)
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height(48)
    .onClick(() => {
      this.onChange(!this.on);
      toast($r('app.string.settings_saved'));
    })
  }
}

@Component
struct ValueRow {
  label: ResourceStr = '';
  value: string = '';
  onChange: (v: string) => void = (): void => {};

  build() {
    Row({ space: 8 }) {
      Text(this.label).fontSize(15).fontColor(Theme.textPrimary).width(120)
      TextInput({ text: this.value })
        .fontSize(14)
        .layoutWeight(1)
        .backgroundColor(Theme.pageBg)
        .onChange((v: string) => this.onChange(v))
    }
    .width('100%')
    .height(48)
  }
}
