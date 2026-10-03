/**
 * 平台帖子统计（v1.22.0）：按平台汇总收藏页已保存作品的照片/视频数量。
 * 数据源 SavedStore（收藏瀑布流同源），savedVersion 变化时自动刷新。
 */
import { AppContainer } from '../data/AppContainer';
import { SavedItem, Platform, WorkType, platformName } from '../model/SaveModels';
import { FrostScaffold } from '../view/FrostScaffold';
import { Theme } from '../view/Common';

/** 单平台统计行 */
class StatRow {
  platform: Platform = Platform.XHS;
  posts: number = 0;
  photos: number = 0;
  videos: number = 0;
}

/** 平台应用图标（与收藏页瀑布流角标同素材） */
function badgeRes(p: Platform): Resource {
  if (p === Platform.XHS) {
    return $r('app.media.ic_xhs');
  }
  if (p === Platform.DOUYIN) {
    return $r('app.media.ic_dy');
  }
  if (p === Platform.X) {
    return $r('app.media.ic_x');
  }
  if (p === Platform.INSTAGRAM) {
    return $r('app.media.ic_ig');
  }
  if (p === Platform.TIKTOK) {
    return $r('app.media.ic_tiktok');
  }
  return $r('app.media.ic_xhs');
}

@Entry
@Component
struct PlatformStats {
  @StorageLink('topAvoid') topAvoid: number = 0;
  @StorageLink('savedVersion') @Watch('onSavedChanged') savedVersion: number = 0;
  @State rows: StatRow[] = [];
  @State totalPosts: number = 0;
  @State totalPhotos: number = 0;
  @State totalVideos: number = 0;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.reload();
  }

  onSavedChanged(): void {
    this.reload();
  }

  private reload(): void {
    // 与收藏页完全同源同口径：先按源链接去重（保留最新一次保存），再按平台分组
    const items: SavedItem[] = AppContainer.get().saved.dedupeBySource(
      AppContainer.get().saved.getAll());
    // 固定顺序：小红书 / 抖音 / Instagram / X；TikTok 有数据才显示
    const order: Platform[] = [Platform.XHS, Platform.DOUYIN, Platform.INSTAGRAM, Platform.X, Platform.TIKTOK];
    const map: Map<Platform, StatRow> = new Map();
    for (const p of order) {
      const row = new StatRow();
      row.platform = p;
      map.set(p, row);
    }
    let posts = 0;
    let photos = 0;
    let videos = 0;
    for (const it of items) {
      let row = map.get(it.platform);
      if (row === undefined) {
        row = new StatRow();
        row.platform = it.platform;
        map.set(it.platform, row);
      }
      row.posts++;
      posts++;
      if (it.workType === WorkType.VIDEO) {
        row.videos += Math.max(1, it.mediaPaths.length);
        videos += Math.max(1, it.mediaPaths.length);
      } else {
        row.photos += it.mediaPaths.length;
        photos += it.mediaPaths.length;
      }
    }
    const next: StatRow[] = [];
    for (const p of order) {
      const row = map.get(p);
      if (row !== undefined && (row.posts > 0 || p !== Platform.TIKTOK)) {
        next.push(row);
      }
    }
    this.rows = next;
    this.totalPosts = posts;
    this.totalPhotos = photos;
    this.totalVideos = videos;
  }

  build() {
    Stack() {
      FrostScaffold({ title: '平台帖子统计', scroller: this.scroller, bgColor: Theme.pageBg }) {
        Scroll(this.scroller) {
          Column({ space: 12 }) {
            // 总览卡
            Row() {
              this.summaryCell(this.totalPosts, '作品')
              Divider().strokeWidth(1).color(Theme.pageBg).height(32).vertical(true)
              this.summaryCell(this.totalPhotos, '照片')
              Divider().strokeWidth(1).color(Theme.pageBg).height(32).vertical(true)
              this.summaryCell(this.totalVideos, '视频')
            }
            .width('100%')
            .padding({ top: 18, bottom: 18 })
            .borderRadius(18)
            .backgroundColor(Theme.cardBg)

            // 各平台统计卡
            Column() {
              ForEach(this.rows, (row: StatRow, idx: number) => {
                if (idx > 0) {
                  Divider().color(Theme.pageBg)
                }
                Row({ space: 12 }) {
                  Image(badgeRes(row.platform))
                    .width(36)
                    .height(36)
                    .borderRadius(10)
                    .objectFit(ImageFit.Cover)
                  Column({ space: 2 }) {
                    Text(platformName(row.platform))
                      .fontSize(15)
                      .fontColor(Theme.textPrimary)
                    Text(`${row.posts} 个作品`)
                      .fontSize(12)
                      .fontColor(Theme.textSecondary)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Row({ space: 22 }) {
                    Column({ space: 2 }) {
                      Text(`${row.photos}`)
                        .fontSize(16)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(Theme.textPrimary)
                      Text('照片')
                        .fontSize(10)
                        .fontColor(Theme.textSecondary)
                    }
                    .alignItems(HorizontalAlign.Center)
                    Column({ space: 2 }) {
                      Text(`${row.videos}`)
                        .fontSize(16)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(Theme.textPrimary)
                      Text('视频')
                        .fontSize(10)
                        .fontColor(Theme.textSecondary)
                    }
                    .alignItems(HorizontalAlign.Center)
                  }
                  .alignItems(VerticalAlign.Center)
                }
                .width('100%')
                .padding(14)
              }, (row: StatRow) => `${row.platform}_${row.posts}_${row.photos}_${row.videos}`)
            }
            .width('100%')
            .borderRadius(18)
            .backgroundColor(Theme.cardBg)
            .clip(true)

            Text('统计来自首页收藏的作品，删除收藏后同步减少。')
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

  @Builder
  summaryCell(num: number, label: string) {
    Column({ space: 3 }) {
      Text(`${num}`)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.textPrimary)
      Text(label)
        .fontSize(12)
        .fontColor(Theme.textSecondary)
    }
    .alignItems(HorizontalAlign.Center)
    .layoutWeight(1)
  }
}
