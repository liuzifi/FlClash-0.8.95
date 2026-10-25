# FlClash 自定义增强功能摘要

> 本文件维护各版本通过 editor-fixes.patch 引入的功能特性，CI 构建时会自动附加到 GitHub Release 说明中。
> 每次发布新版本前更新本文件，把当版本新增的功能写在顶部对应段落。

---

## v0.9.6（浅色模式 / Android 插件 / 应用设置 / 添加配置小组件）

### 新增功能
- **浅色模式（light mode）**：提供亮色主题切换，对应深色模式互补。
  - [`lib/common/light_mode.dart`](lib/common/light_mode.dart) — 浅色模式工具与判定
  - [`lib/providers/light_mode.dart`](lib/providers/light_mode.dart) — 浅色模式 Provider
  - [`test/common/light_mode_test.dart`](test/common/light_mode_test.dart) — 单元测试
- **Android 原生插件**：通过 Kotlin AppPlugin 暴露原生能力给 Flutter 层。
  - [`android/app/src/main/kotlin/com/follow/clash/plugins/AppPlugin.kt`](android/app/src/main/kotlin/com/follow/clash/plugins/AppPlugin.kt) — 原生插件入口
  - [`lib/plugins/app.dart`](lib/plugins/app.dart) — Flutter 侧插件通道
  - [`lib/manager/android_manager.dart`](lib/manager/android_manager.dart) — Android 平台管理器
- **应用设置页**：[`lib/views/application_setting.dart`](lib/views/application_setting.dart) — 集中的应用设置入口。
- **添加配置小组件**：[`lib/views/dashboard/widgets/add_profile.dart`](lib/views/dashboard/widgets/add_profile.dart) — 仪表盘快速添加配置入口。

### 改进
- 补丁格式由 context diff（`diff -ruN`，`-p2`）切换为 git unified diff（`a/` `b/`，`-p1`），更利于 review 与生成。
- editor-fixes.patch 覆盖文件数从 51 → 59，全面整合 v0.9.2~v0.9.6 全部增强。

---

## v0.9.5（收藏代理与体验优化）

### 新增功能
- **收藏代理**：支持将常用代理节点加入收藏，在仪表盘提供收藏代理小组件快速切换。
  - [`lib/common/favorite_proxies.dart`](lib/common/favorite_proxies.dart) — 收藏列表管理
  - [`lib/providers/favorite_proxies.dart`](lib/providers/favorite_proxies.dart) — 收藏状态 Provider
  - [`lib/views/dashboard/widgets/favorite_proxies.dart`](lib/views/dashboard/widgets/favorite_proxies.dart) — 仪表盘收藏代理小组件
  - [`lib/views/proxies/card.dart`](lib/views/proxies/card.dart) — 代理卡片新增收藏按钮
- **偏好设置存储**：[`lib/common/preferences.dart`](lib/common/preferences.dart) 统一的轻量偏好持久化工具。
- **Provider 注册整合**：[`lib/providers/providers.dart`](lib/providers/providers.dart) + [`lib/state.dart`](lib/state.dart) 统一 Provider 注册入口。

### 改进
- 代理列表卡片交互优化，收藏状态实时同步。

---

## v0.9.4（DNS 校验 / 编辑器草稿 / GeoIP 镜像 / YAML 折叠 / 设置搜索）

### 新增功能
- **DNS 服务器校验**：[`lib/common/dns_validator.dart`](lib/common/dns_validator.dart) — DNS 配置输入实时校验。
- **编辑器草稿自动保存**：[`lib/common/editor_draft.dart`](lib/common/editor_draft.dart) — 编辑配置时自动保存草稿，异常退出可恢复。
- **GeoIP 数据库镜像**：[`lib/common/geo_mirror.dart`](lib/common/geo_mirror.dart) — GeoIP 库支持镜像源选择，加速下载。
- **YAML 折叠/展开**：[`lib/common/yaml_folding.dart`](lib/common/yaml_folding.dart) — 编辑器内 YAML 按缩进折叠展开。
- **设置搜索**：[`lib/views/settings_search.dart`](lib/views/settings_search.dart) — 全局搜索设置项。
- **备份与恢复页**：[`lib/views/backup_and_restore.dart`](lib/views/backup_and_restore.dart) + [`lib/providers/actions/backup.dart`](lib/providers/actions/backup.dart)。
- **高级配置 / DNS 配置页**：[`lib/views/config/advanced.dart`](lib/views/config/advanced.dart) + [`lib/views/config/dns.dart`](lib/views/config/dns.dart)。
- **资源页 / 工具页**：[`lib/views/resources.dart`](lib/views/resources.dart) + [`lib/views/tools.dart`](lib/views/tools.dart)。
- **通用组件**：[`lib/widgets/input.dart`](lib/widgets/input.dart) + [`lib/widgets/scaffold.dart`](lib/widgets/scaffold.dart)。

---

## v0.9.3（拼音搜索与代理列表增强）

### 新增功能
- **拼音搜索**：[`lib/common/pinyin.dart`](lib/common/pinyin.dart) — 代理节点支持中文拼音首字母搜索。
- **访问控制页增强**：[`lib/views/access.dart`](lib/views/access.dart)。
- **代理列表增强**：[`lib/views/proxies/list.dart`](lib/views/proxies/list.dart)。
- **配置模型与状态扩展**：[`lib/models/common.dart`](lib/models/common.dart) + [`lib/providers/state.dart`](lib/providers/state.dart)。
- **filter_groups 测试**：[`test/providers/filter_groups_test.dart`](test/providers/filter_groups_test.dart)。

---

## v0.9.2（编辑器增强 + anytls 内核修复）

### 新增功能（编辑器）
- **YAML 大纲**：[`lib/common/yaml_outline.dart`](lib/common/yaml_outline.dart) — 编辑器侧栏 YAML 结构大纲，点击跳转。
- **跳转到行**：编辑器工具栏"跳转到行"按钮。
- **搜索预填**：从大纲或错误信息预填搜索内容。
- **撤销/重做工具栏按钮**。
- **替换提示 i18n**：4 语言（en/ja/ru/zh_CN）.arb 文件更新。
- **查找面板关闭回调**：修复关闭后状态残留。
- **上下文菜单陈旧状态修复**。
- **单元测试**：[`test/common/yaml_outline_test.dart`](test/common/yaml_outline_test.dart)。

### 内核修复（anytls）
- [`anytls-fix.patch`](anytls-fix.patch)：anytls SYNACK 超时 3s → 10s，仅关闭违规流而非整个 session，避免偶发断流。
