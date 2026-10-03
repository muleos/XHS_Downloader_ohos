/**
 * 网络与会话（v1.20.0）：安卓版 DownloadSettingsRoute section 2 对应页。
 * 超时 / 重试 / 代理 / 代理下载 / 网页会话 / 登录小红书 / 清除会话。
 */
import { router } from '@kit.ArkUI';
import { AppContainer } from '../data/AppContainer';
import { AppSettings } from '../core/models';
import { FrostScaffold } from '../view/FrostScaffold';
import { Theme, ToggleRow, SelectorRow, ValueRow, toast } from '../view/Common';

@Entry
@Component
struct NetworkSettings {
  @StorageLink('topAvoid') topAvoid: number = 0;
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

  build() {
    Stack() {
      FrostScaffold({ title: '网络与会话', scroller: this.scroller, bgColor: Theme.pageBg }) {
      Scroll(this.scroller) {
        Column({ space: 12 }) {
          Column() {
            ValueRow({
              label: '请求超时（秒）',
              value: String(this.settings.downloadOptions.timeoutSeconds),
              onChange: (v: string): void => {
                this.set((s: AppSettings) => {
                  s.downloadOptions.timeoutSeconds = Math.max(5, Math.min(180, Number(v) || 45));
                });
              }
            })
            ValueRow({
              label: '最大重试次数',
              value: String(this.settings.downloadOptions.maxRetries),
              onChange: (v: string): void => {
                this.set((s: AppSettings) => {
                  s.downloadOptions.maxRetries = Math.max(0, Math.min(10, Number(v) || 3));
                });
              }
            })
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
          .borderRadius(16)
          .backgroundColor(Theme.cardBg)

          Column() {
            ValueRow({
              label: '代理地址',
              value: this.settings.downloadOptions.proxy,
              onChange: (v: string): void => {
                this.set((s: AppSettings) => {
                  s.downloadOptions.proxy = v.trim();
                });
              }
            })
            Text('格式 host:port（如 127.0.0.1:7890）。X / Instagram / TikTok 在国内网络受限，解析与下载需经代理。')
              .fontSize(12)
              .fontColor(Theme.textSecondary)
              .width('100%')
            ToggleRow({
              label: '代理下载',
              desc: '开启后海外平台媒体下载也走代理。',
              on: this.settings.downloadOptions.proxyDownload,
              onChange: (v: boolean): void => {
                this.set((s: AppSettings) => {
                  s.downloadOptions.proxyDownload = v;
                });
              }
            })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .borderRadius(16)
          .backgroundColor(Theme.cardBg)

          Column() {
            ToggleRow({
              label: '使用网页会话',
              desc: '解析请求携带已登录会话 Cookie。',
              on: this.settings.downloadOptions.useWebSession,
              onChange: (v: boolean): void => {
                this.set((s: AppSettings) => {
                  s.downloadOptions.useWebSession = v;
                });
              }
            })
            Divider().color(Theme.pageBg)
            SelectorRow({
              label: '登录小红书',
              value: '',
              onTap: (): void => {
                router.pushUrl({ url: 'pages/WebSession' });
              }
            })
            Divider().color(Theme.pageBg)
            Row() {
              Text('清除会话').fontSize(15).fontColor(Theme.red).layoutWeight(1)
            }
            .width('100%')
            .height(48)
            .onClick(() => {
              AppContainer.get().client.clearSession();
              toast('已清除会话');
            })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 6, bottom: 6 })
          .borderRadius(16)
          .backgroundColor(Theme.cardBg)

          Text('超时范围 5–180 秒；重试范围 0–10 次。')
            .fontSize(12)
            .fontColor(Theme.textSecondary)
            .width('100%')
            .padding({ left: 8, bottom: (AppStorage.get<number>('bottomAvoid') ?? 0) + 24 })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: this.topAvoid + 88 })
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
