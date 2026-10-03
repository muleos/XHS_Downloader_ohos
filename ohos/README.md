# ohos/ — DevEco Studio 工程

「收藏」应用的完整 DevEco Studio 工程，使用 ArkTS / ArkUI 构建。整体介绍见仓库根目录 [README.md](../README.md)。

## 构建要求

- DevEco Studio 5.0+（compatibleSdkVersion 5.0.0(API 12)）
- 真机签名后安装运行（bundleName `com.hmos.collection`）
- 命令行构建可用仓库根目录的 `build_ohos.sh`，产物自动按 `AppScope/app.json5` 的版本号命名

## 工程结构

- `AppScope/`：应用级配置（bundleName、图标、版本号）
- `entry/src/main/ets/core/`：解析与网络层（链接提取、INITIAL_STATE 归一化、深度找 note、streamType 水印判定、XhsHttpClient）
- `entry/src/main/ets/data/`：设置、收藏记录、下载队列与保存
- `entry/src/main/ets/pages/`：页面 UI（首页收藏、解析、任务、我的、详情、网页提取等）
- `entry/src/main/ets/view/`：通用组件（Theme、通用行组件、底部浮层等）

## 实现要点

- 遵守 ArkTS 严格模式：不用 `any`、不用对象字面量充当未声明类型、不用 `require`；JSON 处理统一走 `core/JsonNode.ets`。
- 网络层统一走 `core/XhsHttpClient.ets`（UA 尾缀 `xiaohongshu`、按 host 注入会话 Cookie）。
- 保存流程为两步：先由队列下载到应用缓存，再由用户通过安全控件 SaveButton（相册）或 DocumentViewPicker（文件）落盘。
- 收藏页 / 统计 / 我的页的作品数量统一走 `SavedStore.dedupeBySource`，按 sourceUrl 去重保持一致。
