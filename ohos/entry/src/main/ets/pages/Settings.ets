/**
 * 设置主页（v1.20.0 精简重构）：对齐安卓版 SettingsActivity 一级结构 ——
 * 下载选项（存储位置 / 媒体与格式 / 归档与记录 / 网络与会话 / 选择性下载 /
 * 媒体卡片信息 / 调试通知 / 保持屏幕常亮）、剪贴板（手动输入链接）、
 * 文件命名。具体开关下沉到三个二级页（MediaFormat / Archive / Network）。
 */
import { router, window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { bundleManager } from '@kit.AbilityKit';
import { AppContainer } from '../data/AppContainer';
import { AppSettings } from '../core/models';
import { FrostScaffold } from '../view/FrostScaffold';
import { Theme, ToggleRow, SelectorRow, ValueRow, SheetState, OptionSheetOverlay, toast } from '../view/Common';

@Entry
@Component
struct Settings {
  @State settings: AppSettings = new AppSettings();
  /** 选项选择浮层（媒体卡片信息等） */
  @State sheet: SheetState = new SheetState();
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

  private currentVersion(): string {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      return info.versionName;
    } catch (e) {
      return '';
    }
  }

  /** 保持屏幕常亮：立即应用到窗口（App 前台时防止自动锁屏） */
  private applyKeepScreenOn(on: boolean): void {
    try {
      window.getLastWindow(getContext(this) as common.UIAbilityContext).then((w: window.Window): void => {
        w.setWindowKeepScreenOn(on);
      });
    } catch (e) {
      // 个别窗口态下设置失败不影响功能
    }
  }

  private cardInfoLabels(): string[] {
    return ['不显示', '文件体积', '分辨率'];
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

  build() {
    Stack() {
      Column() {
      FrostScaffold({ title: '设置', scroller: this.topScroller, bgColor: Theme.pageBg }) {
        Scroll(this.topScroller) {
          Column({ space: 12 }) {
            // ── 下载选项 ──
            Text('下载选项')
              .fontSize(13)
              .fontColor(Theme.textSecondary)
              .width('100%')
              .margin({ left: 4 })
            Column() {
              SelectorRow({
                label: '存储位置',
                value: '当前使用默认存储位置',
                valueColor: Theme.textSecondary,
                onTap: (): void => {
                  toast('作品保存到应用媒体库，可在收藏页查看');
                }
              })
              Divider().color(Theme.pageBg)
              SelectorRow({
                label: '媒体与格式',
                value: '',
                onTap: (): void => {
                  router.pushUrl({ url: 'pages/MediaFormatSettings' });
                }
              })
              Divider().color(Theme.pageBg)
              SelectorRow({
                label: '归档与记录',
                value: '',
                onTap: (): void => {
                  router.pushUrl({ url: 'pages/ArchiveSettings' });
                }
              })
              Divider().color(Theme.pageBg)
              SelectorRow({
                label: '网络与会话',
                value: '',
                onTap: (): void => {
                  router.pushUrl({ url: 'pages/NetworkSettings' });
                }
              })
              Divider().color(Theme.pageBg)
              ToggleRow({
                label: '选择性下载',
                desc: '先预览缩略图，再下载选中的媒体。关闭后解析完成直接下载全部。',
                on: this.settings.selectiveDownload,
                onChange: (v: boolean): void => {
                  this.set((s: AppSettings) => {
                    s.selectiveDownload = v;
                  });
                }
              })
              Divider().color(Theme.pageBg)
              SelectorRow({
                label: '媒体卡片信息',
                desc: '解析任务卡片上显示的信息',
                value: this.cardInfoLabels()[this.settings.mediaCardInfo],
                showArrow: false,
                onTap: (): void => {
                  this.pick('媒体卡片信息', this.cardInfoLabels(), this.settings.mediaCardInfo,
                    (idx: number): void => {
                      this.set((s: AppSettings) => {
                        s.mediaCardInfo = idx;
                      });
                    });
                }
              })
              Divider().color(Theme.pageBg)
              ToggleRow({
                label: '调试通知',
                desc: '显示详细的下载调试信息',
                on: this.settings.debugNotify,
                onChange: (v: boolean): void => {
                  this.set((s: AppSettings) => {
                    s.debugNotify = v;
                  });
                }
              })
              Divider().color(Theme.pageBg)
              ToggleRow({
                label: '保持屏幕常亮',
                desc: 'App 在前台时防止手机自动锁屏',
                on: this.settings.keepScreenOn,
                onChange: (v: boolean): void => {
                  this.set((s: AppSettings) => {
                    s.keepScreenOn = v;
                  });
                  this.applyKeepScreenOn(v);
                }
              })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 6, bottom: 6 })
            .borderRadius(16)
            .backgroundColor(Theme.cardBg)

            // ── 剪贴板 ──
            Text('剪贴板')
              .fontSize(13)
              .fontColor(Theme.textSecondary)
              .width('100%')
              .margin({ left: 4 })
            Column() {
              ToggleRow({
                label: '手动输入链接',
                desc: '开启后不再自动提取剪切板内容',
                on: this.settings.manualInputLinks,
                onChange: (v: boolean): void => {
                  this.set((s: AppSettings) => {
                    s.manualInputLinks = v;
                  });
                }
              })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 6, bottom: 6 })
            .borderRadius(16)
            .backgroundColor(Theme.cardBg)

            // ── 文件命名 ──
            Text('文件命名')
              .fontSize(13)
              .fontColor(Theme.textSecondary)
              .width('100%')
              .margin({ left: 4 })
            Column() {
              ToggleRow({
                label: '自定义命名格式',
                on: this.settings.useCustomNamingFormat,
                onChange: (v: boolean): void => {
                  this.set((s: AppSettings) => {
                    s.useCustomNamingFormat = v;
                  });
                }
              })
              Divider().color(Theme.pageBg)
              ValueRow({
                label: '命名模板',
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
                .width('100%')
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding({ left: 16, right: 16, top: 12, bottom: 12 })
            .borderRadius(16)
            .backgroundColor(Theme.cardBg)

            // ── 关于 ──
            Column({ space: 4 }) {
              Text(`收藏 v${this.currentVersion()} · HarmonyOS`)
                .fontSize(12)
                .fontColor(Theme.textSecondary)
              Text('基于开源项目 XHS_Downloader 移植')
                .fontSize(11)
                .fontColor(Theme.textSecondary)
            }
            .alignItems(HorizontalAlign.Center)
            .width('100%')
            .padding({ top: 8, bottom: this.bottomPad() })
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 8 })
        }
        .scrollBar(BarState.Off)
        .width('100%')
        .height('100%')
        .align(Alignment.Top)
      }
      }

      OptionSheetOverlay({ sheet: this.sheet })
    }
    .width('100%')
    .height('100%')
  }

  private bottomPad(): number {
    const v = AppStorage.get<number>('bottomAvoid');
    return (v === undefined ? 0 : v) + 24;
  }
}
