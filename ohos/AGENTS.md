# AGENTS.md — ohos/ 子目录

适用范围：`ohos/` 内全部文件。

## 结构

- `ohos/` 是独立 DevEco 工程：`AppScope/` + `entry/`；ArkTS 源码位于 `entry/src/main/ets/`：`core/`（解析与网络）、`data/`（设置/记录/队列/保存）、`pages/`（UI）、`view/`（通用组件）。

## 编码约束

- 遵守 ArkTS 严格模式：不用 `any`、不用对象字面量充当未声明类型、不用 `require`；JSON 处理统一走 `core/JsonNode.ets`。
- 网络层统一走 `core/XhsHttpClient.ets`（UA 尾缀 `xiaohongshu`、按 host 注入会话 Cookie）。
- API 面向 compatibleSdkVersion 5.0.0(API 12)：不要使用 uiMaterial、Web.scrollBar 等高版本 API。
- HdsNavigation/@BuilderParam 容器的内容闭包只放一个根节点；悬浮条需在内部自包 Column/Stack。
- 页面注意顶栏与底部手势条避让（topAvoid / bottomAvoid）。
- 版本发布前递增 `AppScope/app.json5` 的 versionName 与 versionCode。

## 文案与资源

- 禁止硬编码用户可见字符串；使用 `$r('app.string.xxx')`。新增字符串必须同步维护：
  - `entry/src/main/resources/base/element/string.json`（中文）
  - `entry/src/main/resources/en_US/element/string.json`（英文）
  - key 命名 `{页面}_{描述}`，通用按钮 `common_` 前缀。
- 颜色使用 `view/Common.ets` 的 `Theme` 常量；不要散落 `#RRGGBB` 字面量（Theme 内部除外）。

## Git

- 提交信息用中文，形如 `v<版本>: xxx修复+xxx优化：①②③`。
- 构建统一用仓库根目录 `build_ohos.sh`；交付产物为 `collection-<版本>-unsigned.hap`。
- 未经用户在当前请求中明确授权，不执行 `git push`。
