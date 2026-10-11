# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

Kayoko 是 iOS 剪切板管理器（Theos 越狱插件）。本仓库是 mlgm 维护的 fork，基于 [OwnGoalStudio/Kayoko](https://github.com/OwnGoalStudio/Kayoko)，上游为 [AlexandraAurora/Kayoko](https://github.com/AlexandraAurora/Kayoko)。GPLv3，见 `COPYING`。

包 ID `com.mlgm.kayoko`（`control` 中声明 Conflicts/Replaces 了 `codes.aurora.kayoko`、`dev.traurige.kayoko` 等一批旧版包）。支持三种打包方案：rootful / rootless / roothide。

代码全部是 Objective-C（ARC、`USE_MODULES := 0`），类前缀统一为 `Kayoko`。

## 构建与打包

```bash
./build.sh roothide      # 或 rootless / rootful，产物落在 ./packages/
```

`build.sh` 会：自动探测 Theos（`$THEOS` → `~/theos` → `/opt/theos` → `~/theos-roothide`），按 scheme 传 `THEOS_PACKAGE_SCHEME` 调 `make clean && make package FINALPACKAGE=1`，退出时清理 `.theos/`、`*.o` 等中间产物并列出 deb。三种 scheme 必须分别编译（安装路径与 install name 不同）。

等价的原始命令：

```bash
THEOS_PACKAGE_SCHEME=roothide make package FINALPACKAGE=1   # rootful 用空 scheme
```

**越狱根路径**：所有 `jbroot()` 调用统一走 `Preferences/KayokoJailbreakPath.h`，它按 scheme 切换实现：

- roothide：`#import <roothide.h>`，`jbroot()` 由 libroothide 提供，另外链 `-lroothide`（各子项目 Makefile 的 `ifeq ($(THEOS_PACKAGE_SCHEME),roothide)` 分支，同时定义 `THEOS_PACKAGE_SCHEME_ROOTHIDE=1`）。**需要 roothide 的 Theos fork**，它才提供 `vendor/include/roothide.h` 与 `vendor/lib/iphone/roothide/`。
- rootless / rootful：`#import <rootless.h>`，`jbroot()` 内联包装 Theos 自带 libroot 的 `ROOT_PATH_NS()`（`rules.mk` 会自动加 `-lroot`，静态链入，无额外运行时依赖）。**stock Theos 即可**，不需要 roothide 工具链。

即：打 rootless DEB 不再依赖 roothide 工具链；只有打 roothide 包才需要它。任何 target 都不要再直接 `#import <roothide.h>`。

Theos 的 rootless 模块（`vendor/mod/rootless/package/deb.mk`）会强制把 `control` 里的 `Architecture` 改写成 `iphoneos-arm64` 并把文件铺到 `var/jb/…`，所以 `control` 里写的 `iphoneos-arm` 不影响 rootless 产物。

Xcode 侧：`Kayoko.xcodeproj` 由 `xcodegen generate` 从 `project.yml` 生成，**不要手改 `project.pbxproj`**。`project.yml` 里 `KAYOKO_PACKAGE_SCHEME: roothide`、`THEOS: /opt/theos`、install name 写死为 `@loader_path/.jbroot/...`，即 Xcode 工程只对应 roothide 一种方案；三方案打包走 `build.sh`。

**没有测试套件**，验证方式只有编译通过 + 真机行为。

版本号需要同步修改 5 处：根 `Makefile` 的 `PACKAGE_VERSION`、`control` 的 `Version`、`project.yml` 的 `MARKETING_VERSION` 与 `CURRENT_PROJECT_VERSION`、`Preferences/Resources/Info.plist` 的两个版本字段。

## 架构

### 四个产物与注入目标

| 产物 | 形态 | 注入 / 安装位置 | 过滤条件 |
|---|---|---|---|
| `KayokoCore` | tweak dylib | `/Library/MobileSubstrate/DynamicLibraries` | `Core/KayokoCore.plist`：SpringBoard + 可执行文件 `druid`、`pasted` |
| `KayokoHelper` | tweak dylib | 同上 | `Helper/KayokoHelper.plist`：`com.apple.UIKit`（几乎所有进程，真实分发在进程内判断） |
| `KayokoPreferences` | preference bundle | `/Library/PreferenceBundles` | PreferenceLoader 入口 `Preferences/layout/Library/PreferenceLoader/Preferences/KayokoPreferences/Root.plist` |
| `kayoko_updater` | CLI tool | `/usr/local/libexec` | 由 `layout/DEBIAN/postinst` 和设置界面调用 |

两个 dylib 的入口都是 `__attribute((constructor)) initialize()`，先按进程类型分发再决定装哪些 hook：`Core/KayokoCore.m`（SpringBoard vs druid/pasted vs 其他）与 `Helper/KayokoHelper.m`（KeyboardExtension / SpringBoard / Application，Spotlight 归入 Application）。

### Core 分层

```
KayokoCoreRuntime            单例：偏好加载、面板生命周期、锁屏/场景观察、Darwin 通知派发、触感与音效
  └── KayokoMainViewController   面板的唯一根 VC，同时实现各 Coordinator 的 delegate（最大的文件）
        ├── Coordinators/    KayokoHistoryController / KayokoSearchController / KayokoExternalHideCoordinator
        ├── Presentation/    KayokoPanelPresentationController / KayokoSearchPresentationController（布局与动画引擎）
        ├── Controllers/     列表、预览、备注/文本编辑、选词、清除确认等子页面
        └── Views/           纯 UI（KayokoMainView、cell、header、tag chip、EdgeFading* 系列滚动视图）
  └── KayokoPasteboardManager    单例：唯一的数据 API（UIPasteboard 读写、图片/富文本落盘、缩略图、历史写入策略）
        └── KayokoHistoryRepository   串行队列门面，持有 limitProvider，把同步调用包装成回调
              ├── KayokoHistoryStore        纯 sqlite3 层（schema、WAL、搜索索引、迁移标记）
              └── KayokoHistoryMigrator     旧版 JSON 历史导入
```

约定：**UI 层只能调 `KayokoPasteboardManager`**，绝不直接碰 `KayokoHistoryStore`；DB 操作全部走 Repository 的串行队列，重活（写粘贴板）走 `com.mlgm.kayoko.queue.pasteboard`。所有跨层传递的对象都是 `NSDictionary`（模型对象是 `KayokoPasteboardItem`，落库为字典）。

Coordinators 是不继承 VC 的普通对象，持有跨页面状态（已加载/脏的 history key、搜索态、被延迟的外部隐藏请求）；Views 是被动的，Controllers 每个页面对应一个 View。

### 持久化

- 数据库：`jbroot("/var/mobile/Library/com.mlgm.kayoko/history-v4.sqlite")`，路径单点定义在 `Shared/Tags/KayokoFilterCatalog.m` 的 `KayokoHistoryDatabasePath()`。
- 表：`history_items`（`(history_key, content)` 唯一，`(history_key, sequence DESC)` 有序索引）、`history_item_search_tokens`（含 delete trigger）、`image_edit_originals`、`metadata` 键值表。`journal_mode=WAL`、`synchronous=NORMAL`。
- 迁移是**增量 `ALTER TABLE` + 回填**，完成标记写在 `metadata` 表（如 `v4_legacy_sources_imported`），没有独立的版本表。
- 旁边目录：`images/`、`rich-text/`；标签单独存 `tags-v4.plist`。
- `history_key` 只有两个取值：`history` 与 `favorites`（`KayokoPasteboardManager.h`）。

### 面板呈现

竖屏下面板不是独立窗口：hook `UIStatusBarWindow` 的初始化拿到 window，再由 `KayokoCoreRuntime installPanelInStatusBarWindow:` 懒加载 `KayokoMainViewController`，显示时从该 window 的 `windowScene` 创建 `KayokoOverlayWindow`（层级 `CGFLOAT_MAX` 或自定义），竖屏为抽屉、紧凑横屏为全屏。手势与系统上滑抑制 hook 打在 `_UISystemGestureWindow` 上。

`KayokoKeyboardHostResolver` 回答"当前键盘属于哪个场景"（Application / SpringBoard / Spotlight），用于三处：写入历史时标注来源 App、面板 UI 风格匹配、模拟自动粘贴后恢复焦点。

### Helper 与激活方式

Helper 在进程内按 `KayokoHelperProcessContext` 分类后按 `ActivationMethod` 位掩码装 hook：

- `KayokoPredictionBarHooks` 候选栏（`{kayoko-History}` / `{kayoko-Copy}` / `{kayoko-Paste}` 伪候选）
- `KayokoDictationHooks` 把听写键换成剪贴板图标
- `KayokoInputSwitcherHooks` 地球键菜单项
- `KayokoCalloutMenuHooks` 编辑菜单（iOS 16+ 走 `_UIEditMenuPresentation`，更早走 `UICalloutBar` 私有 ivar）
- `KayokoSwipeUpHooks` + `KayokoSwipeUpGestureRecognizer`（克隆系统键盘收起手势的阈值与状态机）

`kActivationMethodExternalKeyboard`（1<<5）不在 Helper，而是 Core 的 `KayokoSpringBoardHooks` 里。注意 `KayokoSwipeUpGestureRecognizer` 被同时编译进 Helper 和 Core（`Core/Makefile` 显式引用 `../Helper/KayokoSwipeUpGestureRecognizer.m`），一处改动影响两侧。

Helper 还负责焦点捕获/恢复和"待粘贴"状态机（Core 发 `helper.paste`，Helper 执行 Cmd-V 后回 `paste.feedback`）。

### Preferences

`PSListController` 体系 + `Preferences/Resources/Root.plist` specifier（`AdvancedOptions.plist`、`Credits.plist` 为二级页），自定义 cell 在 `Preferences/Cells`。应用黑名单页继承 AltList 的 `ATLApplicationListMultiSelectionController`。

- `Preferences/Resources/{en,zh-Hans}.lproj/` 下的 strings 分表存放：`Root` / `AdvancedOptions` / `Credits` / `Tags` / `Tweak`，两语言必须同步。
- 偏好值就是 `com.mlgm.kayoko.preferences` 这个 NSUserDefaults suite；Helper 直接按 plist 路径读同一个域。
- 改动通过 Darwin 通知生效（`preferences.reload`、`preferences.height.reload`），但 **Enabled / ActivationMethod / AutomaticallyPaste 需要 respring**（Helper 只在进程启动时注入），界面会主动提示。
- `KayokoAdvancedOptionsListController` 是维护入口：清空历史/收藏、checkpoint、显示数据目录、执行 `kayoko_updater`（导入 CopyLog / CopyVault）、重置偏好。

### kayoko_updater

`postinst | import-copylog | import-copyvault | reset-thumbnail-cache` 四个子命令（`Updater/main.m`）。它直接复用 Core 的 `KayokoHistoryStore` / `KayokoHistoryMigrator` / 模型和 `Shared/Tags` 里的持久化代码（`Updater/Makefile` 逐个列出），因此改这些文件会同时影响插件本体和这个工具。`postinst` 里调用它是为了在安装时完成旧数据导入与缩略图缓存清理。

## 跨进程通信

只有四种通道，没有 XPC/socket：

1. **Darwin 通知**（主力）。名字全部集中在 `Preferences/KayokoNotificationKeys.h`，**不要把通知字符串内联到代码里**。分方向：Helper → Core `core.show` / `core.hide` / `paste.willstart`；Core → Helper `helper.paste` / `helper.restore-focus`；Preferences → Core `preferences.reload` / `preferences.height.reload`；Updater/Preferences → Core `core.checkpoint-history` / `core.prepare-maintenance` / `core.reset-thumbnail-memory-cache` / `core.clear-favorites` / `core.clear-history`。旧包名别名（`dev.traurige.kayoko.*`、`codes.aurora.kayoko.core.show`）仍需继续监听。
2. **FBS scene client setting 标志位**：`kKayokoSceneClientSettingHelperInjected = 0x4B41594F4B485001`（`Preferences/KayokoSceneSettingKeys.h`），Helper 在每个 `FBSScene updateClientSettingsWithBlock:` 打标，Core 用它判断某场景是否已注入 Helper。
3. **共享 NSUserDefaults plist**：`/var/mobile/Library/Preferences/com.mlgm.kayoko.preferences.plist`。
4. **请求/响应文件桥**：`KayokoFilterApplicationBridge` 用数据目录下 `application-catalog/request.plist`、`response.plist` 加一对 libnotify 通知，让 Preferences 进程向 SpringBoard 里的 Core 索取"有历史的 App 列表"（Core 是服务端，5 秒超时，同一时刻只允许一个请求）。

跨 bundle 取本地化字符串也是走安装路径（`jbroot("/Library/PreferenceBundles/KayokoPreferences.bundle")`，表 `Tweak`），没有链接期依赖——所以 bundle 名、路径和 strings 表名不能随意改。

## 约定

- 头文件用 `NS_ASSUME_NONNULL_BEGIN/END`；指定初始化器 + `init`/`new` 标 `NS_UNAVAILABLE`。
- 常量统一 `static NSString *const kKayoko...`，枚举成员 `k` 前缀；所有共享常量放 `Preferences/KayokoPreferenceKeys.h`（含默认值，是唯一真源）、`KayokoNotificationKeys.h`、`KayokoSceneSettingKeys.h`，其他 target 靠 `-I../Preferences` 引用。
- Hook 一律用 CaptainHook（`#define CHUseSubstrate`），每次 `CHLoadClass_`/`CHHook` 前先用 `Shared/KayokoHookValidation.h` 的 `KayokoHookMethodMatches` 校验方法签名，不匹配就跳过并打日志。私有类声明写在各自的 hook 文件里，不共享头文件。
- 绝对路径一律 `jbroot()` 包一层，并在 `dispatch_once` 里懒解析；用户数据固定放 `/var/mobile/Library/com.mlgm.kayoko/`。`jbroot()` 只从 `Preferences/KayokoJailbreakPath.h` 来，不要在别处 `#import <roothide.h>`。
- 新增文件：放进已有的 `Manager/ Actions/ Controllers/ Coordinators/ Models/ Presentation/ Views/` 等目录即可（Makefile 和 `project.yml` 都用通配/目录引用），**但 `Updater/Makefile` 是逐个列文件的**，新增 updater 用到的文件必须手动加进去。

## 需要注意的同步点

- `Shared/Tags/*.m` 同时编译进 Core、Preferences 和 updater 三个 target。改 tag 字典键名、`tags-v4.plist` 路径/默认值或 `KayokoFilterCatalog` 的标识符会同时影响三处。
- `KayokoTagColorFormatter` 存在两份且已经分叉：`Core/Models/` 版多了 `dotImageWithHexColor:` 系列（Core 画色点用），`Preferences/Utilities/` 版多了 `hexColorFromColor:`。改颜色算法要两边都改。
- `KayokoPreferenceKeys.h` 里的默认值在 `Helper/KayokoHelperConfiguration.m` 的 `registerDefaults` 中有一份重复声明，必须保持一致。
- 数据目录 `/var/mobile/Library/com.mlgm.kayoko` 在 `KayokoTagStore.m`、`KayokoFilterCatalog.m`（`KayokoHistoryDatabasePath`）和 `Preferences/Controllers/KayokoAdvancedOptionsListController.m` 三处各自写出。
- `Preferences/Frameworks/{,_rootless,_roothide}/AltList.framework/AltList.tbd` 是 AltList 的三份 stub，符号相同、只有 install name 不同（`/Library/Frameworks/...`、`@rpath/...`、`@loader_path/.jbroot/...`），由 `THEOS_PACKAGE_SCHEME` 选择。AltList 是第三方（MIT，见 `THIRD_PARTY_NOTICES.md`），仅用于黑名单多选列表。
- 标签在 Preferences 侧编辑后**不发任何通知**（直接写 `tags-v4.plist`），Core 要等下一次 reload 才读到；改任一侧时留意这个同步点。
- `Core/DataSources/` 被 `Core/Makefile` 和 `project.yml` 引用，但目录并不存在（通配符无害，别被误导）。
- 部分 hook 按系统版本走两套私有 API（如编辑菜单：iOS 16+ 用 `_UIEditMenuPresentation`，iOS 14/15 用 `UICalloutBar`），改动时两条路径都要顾及。部署目标 iOS 14.0，编译用 iPhoneOS 16.5 SDK。
