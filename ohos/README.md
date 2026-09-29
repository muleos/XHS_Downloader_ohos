# 小红书下载器 (HarmonyOS 版)

Android 版（仓库根目录 `app/`）的鸿蒙原生移植，使用 ArkTS / ArkUI 构建。本目录是独立完整的 DevEco Studio 工程，用 DevEco 打开 `ohos/` 即可构建。

- Android 版本：见仓库根目录 [README.md](../README.md)
- 许可：AGPL-3.0（与主仓库一致）

## 构建要求

- DevEco Studio 5.0+（compatibleSdkVersion 5.0.0(API 12)）
- 真机签名后安装运行

## 当前实现（v1）

- 笔记链接解析：分享文本提取链接、短链（xhslink）跟随重定向、`window.__INITIAL_STATE__` 归一化与深度查找（与 Android 版 `XhsNoteParser.kt` 1:1 对应）
- 媒体瀑布流预览与勾选下载，实况照片（v1 按图片+视频分开保存，即 Android 版 SEPARATE 模式）
- 评论配图下载（来自笔记详情状态，不自动翻页）
- 下载队列：串行、进度/速度、暂停/继续/取消/重试，去重
- 保存：相册（安全控件 SaveButton 临时授权）或文件（DocumentViewPicker），两步式（先下载到缓存，再点击保存）
- 文案复制 / TXT、Markdown 笔记信息保存
- 登录会话：WebView 登录后提取 Cookie，供解析与下载注入
- 下载记录：JSON / CSV 导出
- i18n：中文（base）+ 英文（en_US）

## 与 Android 版的差异（有意为之）

- **保存流程为两步**：鸿蒙普通应用写相册需安全控件临时授权（有效期短），因此先由队列下载到应用缓存，再由用户点击「保存到相册」（SaveButton）或「保存到文件」完成落盘。临时文件均为原始媒体数据。
- **实况照片合成**：小米/OPPO/三星等厂商容器格式合成待后续版本（Android 版 `LivePhotoCreator.kt` 的字节级装配逻辑可移植），v1 提供分开保存与仅静态图。
- **更新检查**：暂未移植。
- **代理**：设置项保留，v1 仅对页面请求生效，媒体下载暂不区分。
