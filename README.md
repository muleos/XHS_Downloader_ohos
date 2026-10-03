# 收藏 (HarmonyOS)

使用 ArkTS / ArkUI 构建的 HarmonyOS NEXT 媒体收藏下载工具，支持多平台笔记与帖子的图片、视频、实况照片与文案保存。

<p align="center">

![HarmonyOS NEXT](https://img.shields.io/badge/HarmonyOS-NEXT-blue)
![API 12+](https://img.shields.io/badge/API-12%2B-green)
![License](https://img.shields.io/badge/License-AGPLv3-orange)

</p>

## 主要功能

- **多平台链接解析**：识别分享文本中的小红书、Instagram、X（Twitter）、抖音等平台链接（部分平台需在设置中配置代理），支持批量识别一次提交多个链接。
- **网页提取**：对无法直接解析的内容，可从内置浏览器加载的网页中提取媒体资源，支持常见图床 / CDN 白名单与懒加载图片识别。
- **收藏页**：作品库瀑布流浏览，支持批量管理、长按删除，按平台筛选查看。
- **帖子详情**：媒体预览、逐项保存，长按可复制文案与标题。
- **下载任务队列**：串行下载、进度与实时网速、暂停 / 继续 / 取消 / 重试，支持勾选批量删除任务。
- **平台帖子统计**：按平台统计已收藏的照片与视频数量，与收藏页数据实时同步。
- **账号登录**：内置浏览器登录小红书网页版，登录会话供解析与下载使用。
- **媒体与格式**：图片格式与视频优先级偏好、视频封面、实况照片保存方式。
- **归档与记录**：按作者 / 笔记分目录归档、命名模板、下载记录导出 JSON / CSV。
- **网络设置**：超时、重试、HTTP / SOCKS5 代理。

## 构建与安装

- 使用 DevEco Studio 5.0+ 打开 `ohos/` 目录（compatibleSdkVersion 5.0.0(API 12)），或直接运行仓库根目录的 `build_ohos.sh` 命令行构建。
- 构建产物为未签名 HAP，安装前需按 bundleName `com.hmos.collection` 自行生成签名。
- 也可前往 [Releases](https://github.com/muleos/collection_ohos/releases) 下载已构建的 HAP 包。

## 目录结构

- `ohos/`：DevEco Studio 完整工程（AppScope + entry），全部应用源码位于 `ohos/entry/src/main/ets/`。
- `docs/`：媒体资源研究与笔记案例等参考资料。
- `build_ohos.sh`：命令行构建脚本，自动按 `app.json5` 版本号命名产物。

## 许可

[AGPL-3.0](LICENSE)
