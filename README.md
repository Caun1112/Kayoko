# Kayoko

Feature-rich clipboard manager for iOS.

A Kayoko fork maintained by **mlgm**, based on the [OwnGoal Studio edition](https://github.com/OwnGoalStudio/Kayoko).

## 5.0.3 图片工具

长按图片进入预览，点击原“编辑”右侧的滑杆图标，即可打开内置 **FingerEditor**。无需另外安装 App；原来的系统标记编辑入口继续保留。

- 标注：箭头、方框、圆框、文字、涂鸦。
- 遮盖：细／粗马赛克画笔、模糊、纯色遮盖、矩形马赛克、从照片导入覆盖图片。
- 裁剪、文字识别与选取／全部复制，撤销和重做。
- 单指绘制，双指移动和缩放；横向滑动底部工具栏查看全部工具。
- 点“完成”写回当前历史或收藏条目，保留标签、备注和来源；返回预览后可使用“恢复原图”、分享和保存到相册。取消不会保存此次编辑。

工具参考用户提供的 [FingerEditor](https://github.com/Caun1112/FingerEditor) 项目，以 Objective-C/UIKit 集成，保持 iOS 14 兼容。撤销保留最近 12 步并使用临时文件存储；编辑超大图片时限制到最长边 4096、总像素 400 万，原始文件仍可恢复。保存和恢复后会重新识别图片文字，防止旧 OCR 内容留在搜索中。

Rootless 构建：`THEOS=/path/to/theos ./build.sh rootless`，产物在 `packages/`。验证说明见 [tests/README.md](tests/README.md)。

## Credits

- Original project: [AlexandraAurora/Kayoko](https://github.com/AlexandraAurora/Kayoko)
- Based on: [OwnGoalStudio/Kayoko](https://github.com/OwnGoalStudio/Kayoko)

## License

GPLv3. See [`COPYING`](COPYING).
