# AGENTS.md — ohos/ 子目录

适用范围：`ohos/` 内全部文件。根目录 AGENTS.md 规范 Android 代码；本目录规范鸿蒙移植。两者冲突时以本文件为准（针对 `ohos/` 内文件）。

## 结构

- `ohos/` 是独立 DevEco 工程：`AppScope/` + `entry/`；不要在 `ohos/` 内引用 Android 代码，也不要让 Android 源依赖 `ohos/`。
- ArkTS 源码位于 `entry/src/main/ets/`：`core/`（解析与网络，对应 Android `data/xhs`、`data/network`）、`data/`（设置/记录/队列/保存）、`pages/`（UI）、`view/`（通用组件）。

## 移植原则

- 解析逻辑与 `app/src/main/java/com/neoruaa/xhsdn/data/xhs/` 保持 1:1（INITIAL_STATE 归一化、深度找 note、streamType 259/309 水印判定、评论图 BFS）。修改解析行为时必须同步两侧或明确注释差异。
- 遵守 ArkTS 严格模式：不用 `any`、不用对象字面量充当未声明类型、不用 `require`；JSON 处理统一走 `core/JsonNode.ets`。
- 网络层统一走 `core/XhsHttpClient.ets`（UA 尾缀 `xiaohongshu`、按 host 注入会话 Cookie）。
- API 面向 compatibleSdkVersion 5.0.0(API 12)：不要使用 uiMaterial、Web.scrollBar 等高版本 API。

## 文案与资源

- 禁止硬编码用户可见字符串；使用 `$r('app.string.xxx')`。新增字符串必须同步维护：
  - `entry/src/main/resources/base/element/string.json`（中文）
  - `entry/src/main/resources/en_US/element/string.json`（英文）
  - key 命名 `{页面}_{描述}`，通用按钮 `common_` 前缀，与根目录 Android 规范一致。
- 颜色使用 `view/Common.ets` 的 `Theme` 常量；不要散落 `#RRGGBB` 字面量（Theme 内部除外）。

## Git

- 提交前确认只暂存 `ohos/` 内目标文件；不触碰 Android 代码。
- 提交信息用中文，形如 `ohos: xxx修复+xxx优化：①②③`。
- 未经用户在当前请求中明确授权，不执行 `git push`。
