# Kayoko

Feature-rich clipboard manager for iOS.

A Kayoko fork maintained by **mlgm**, based on the [OwnGoal Studio edition](https://github.com/OwnGoalStudio/Kayoko).

## 5.0.5 图片编辑与预览修复

- 移除旧的系统简单图片编辑入口，图片预览只保留内置 FingerEditor、分享、保存、恢复原图（可用时）和返回。
- 图片预览的返回按钮移到最右侧；文字预览仍可编辑，返回位置保持原有布局。
- 松手后保留笔迹预览，渲染和快照写入完成时无动画替换为新图片，避免笔迹先消失再出现。
- 每笔绘制不再使工具栏变暗或闪现加载指示；保存、打开图片和 OCR 等耗时操作仍显示处理状态。

## 5.0.4 单手编辑布局

内置编辑器按 FingerEditor 的单手排版调整：上方只保留图片画布，下方依次为工具设置卡片、标注／遮盖／OCR／裁剪模式，以及图标操作栏。工具分组、颜色圆点、独立线宽数值、浅色圆角卡片和靠右排列均参考原 App。

- 画布右下角的锁定按钮切换绘制与移动／缩放，常用控件均在底部。
- 底部提供取消、重置、撤销、导出、复制和完成；长按撤销可重做。
- 重置返回本次打开时的图片；“完成”仍写回当前剪贴板条目，取消不保存。
- 横屏将工具区放到右侧，小屏和横屏的设置卡片可滚动，保留底部模式与操作栏。

## 内置图片工具

长按图片进入预览，点击滑杆图标，即可打开内置 **FingerEditor**，无需另外安装 App。

- 标注：箭头、方框、圆框、文字、涂鸦。
- 遮盖：细／粗马赛克画笔、模糊、纯色遮盖、矩形马赛克、从照片导入覆盖图片。
- 裁剪、文字识别与选取／全部复制，撤销和重做。
- 标注模式包含箭头、方框、圆框、文字、涂鸦笔、马赛克；选择马赛克可再切换细／粗马赛克和模糊。
- 锁定画布时单指绘制，解锁后可单指移动、双指缩放。遮盖模式内可导入覆盖图片。
- 点“完成”写回当前历史或收藏条目，保留标签、备注和来源；返回预览后可使用“恢复原图”、分享和保存到相册。取消不会保存此次编辑。

工具参考用户提供的 [FingerEditor](https://github.com/Caun1112/FingerEditor) 项目，以 Objective-C/UIKit 集成，保持 iOS 14 兼容。撤销保留最近 12 步并使用临时文件存储；编辑超大图片时限制到最长边 4096、总像素 400 万，原始文件仍可恢复。保存和恢复后会重新识别图片文字，防止旧 OCR 内容留在搜索中。

Rootless 构建：`THEOS=/path/to/theos ./build.sh rootless`，产物在 `packages/`。验证说明见 [tests/README.md](tests/README.md)。

## Credits

- Original project: [AlexandraAurora/Kayoko](https://github.com/AlexandraAurora/Kayoko)
- Based on: [OwnGoalStudio/Kayoko](https://github.com/OwnGoalStudio/Kayoko)

## License

GPLv3. See [`COPYING`](COPYING).
