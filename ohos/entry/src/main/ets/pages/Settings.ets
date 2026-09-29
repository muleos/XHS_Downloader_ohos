import { router } from '@kit.ArkUI';
import { AppContainer } from '../data/AppContainer';
import { MediaSaver } from '../data/MediaSaver';
import { AppSettings, VideoPreference, ImageFormat, LivePhotoMode } from '../core/models';
import { Theme, TitleBar, SectionCard, toast } from '../view/Common';

@Entry
@Component
struct Settings {
  @StorageLink('topAvoid') topAvoid: number = 0;
  @StorageLink('bottomAvoid') bottomAvoid: number = 0;
  @StorageLink('leftAvoid') leftAvoid: number = 0;
  @StorageLink('rightAvoid') rightAvoid: number = 0;
  @State settings: AppSettings = new AppSettings();

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

  @Builder
  selectorRow(label: string, value: string, onTap: () => void) {
    Row() {
      Text(label).fontSize(15).fontColor(Theme.textPrimary).layoutWeight(1)
      Text(value).fontSize(14).fontColor(Theme.red)
      Text('›').fontSize(18).fontColor(Theme.textSecondary).margin({ left: 6 })
    }
    .width('100%')
    .height(44)
    .onClick(() => onTap())
  }

  @Builder
  toggleRow(label: string, on: boolean, onChange: (v: boolean) => void) {
    Row() {
      Text(label).fontSize(15).fontColor(Theme.textPrimary).layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: on })
        .selectedColor(Theme.red)
        .onChange((v: boolean) => onChange(v))
    }
    .width('100%')
    .height(44)
  }

  @Builder
  valueRow(label: string, value: string, onChange: (v: string) => void) {
    Row({ space: 8 }) {
      Text(label).fontSize(15).fontColor(Theme.textPrimary).width(120)
      TextInput({ text: value })
        .fontSize(14)
        .layoutWeight(1)
        .onChange((v: string) => onChange(v))
    }
    .width('100%')
    .height(48)
  }

  build() {
    Column() {
      TitleBar({ title: $r('app.string.settings_title'), showBack: true })

      Scroll() {
        Column({ space: 12 }) {
          SectionCard() {
            Text($r('app.string.settings_media_format'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.textPrimary)
            this.selectorRow($r('app.string.settings_video_preference'), this.vpLabel(), () => {
              this.cycleVideoPreference();
            })
            this.selectorRow($r('app.string.settings_image_format'), this.ifLabel(), () => {
              this.cycleImageFormat();
            })
            this.toggleRow($r('app.string.settings_video_cover'), this.settings.downloadOptions.videoCoverDownload,
              (v: boolean) => {
                this.set((s: AppSettings) => {
                  s.downloadOptions.videoCoverDownload = v;
                });
              })
            this.toggleRow($r('app.string.settings_comment_images'), this.settings.downloadOptions.commentImageDownload,
              (v: boolean) => {
                this.set((s: AppSettings) => {
                  s.downloadOptions.commentImageDownload = v;
                });
              })
            this.selectorRow($r('app.string.settings_live_photo_mode'), this.lpLabel(), () => {
              this.cycleLiveMode();
            })
          }

          SectionCard() {
            Text($r('app.string.settings_task_group'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.textPrimary)
            this.valueRow($r('app.string.settings_timeout_seconds'), String(this.settings.downloadOptions.timeoutSeconds),
              (v: string) => {
                this.set((s: AppSettings) => {
                  s.downloadOptions.timeoutSeconds = Math.max(5, Math.min(300, Number(v) || 45));
                });
              })
            this.valueRow($r('app.string.settings_max_retries'), String(this.settings.downloadOptions.maxRetries),
              (v: string) => {
                this.set((s: AppSettings) => {
                  s.downloadOptions.maxRetries = Math.max(0, Math.min(10, Number(v) || 3));
                });
              })
          }

          SectionCard() {
            Text($r('app.string.settings_network_group'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.textPrimary)
            this.toggleRow($r('app.string.settings_use_web_session'), this.settings.downloadOptions.useWebSession,
              (v: boolean) => {
                this.set((s: AppSettings) => {
                  s.downloadOptions.useWebSession = v;
                });
              })
            this.valueRow($r('app.string.settings_proxy'), this.settings.downloadOptions.proxy, (v: string) => {
              this.set((s: AppSettings) => {
                s.downloadOptions.proxy = v.trim();
              });
            })
            this.toggleRow($r('app.string.settings_proxy_download'), this.settings.downloadOptions.proxyDownload,
              (v: boolean) => {
                this.set((s: AppSettings) => {
                  s.downloadOptions.proxyDownload = v;
                });
              })
          }

          SectionCard() {
            Text($r('app.string.settings_naming_group'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.textPrimary)
            this.toggleRow($r('app.string.settings_use_custom_naming'), this.settings.useCustomNamingFormat,
              (v: boolean) => {
                this.set((s: AppSettings) => {
                  s.useCustomNamingFormat = v;
                });
              })
            Text(getContext(this).resourceManager.getStringSync($r('app.string.settings_naming_template')) + ': ' + this.settings.customNamingTemplate)
              .fontSize(12)
              .fontColor(Theme.textSecondary)
            Text($r('app.string.settings_naming_tokens'))
              .fontSize(12)
              .fontColor(Theme.textSecondary)
          }

          SectionCard() {
            Text($r('app.string.settings_session_group'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.textPrimary)
            this.selectorRow($r('app.string.settings_open_web_session'), '', () => {
              router.pushUrl({ url: 'pages/WebSession' });
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
        .padding({ left: 12, right: 12, bottom: this.bottomAvoid + 24 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .padding({ left: this.leftAvoid, right: this.rightAvoid, top: this.topAvoid })
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.pageBg)
  }

  private vpLabel(): string {
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

  private ifLabel(): string {
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

  private lpLabel(): string {
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
    MediaSaver.saveTextFile(getContext(this), name, text).then((ok: boolean) => {
      toast(ok ? $r('app.string.common_saved') : $r('app.string.error_network'));
    });
  }
}
