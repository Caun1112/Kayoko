#import <UIKit/UIKit.h>
#import "KayokoFingerImageRenderer.h"

NS_ASSUME_NONNULL_BEGIN

/// Thumb-reachable settings, mode switcher and actions for the built-in editor.
/// The owner supplies the outer safe-area margins and wires the action buttons.
@interface KayokoFingerEditorControlsView : UIView
@property(nonatomic, readonly) CGFloat preferredHeight;
@property(nonatomic, strong, readonly) UIButton *cancelButton;
@property(nonatomic, strong, readonly) UIButton *resetButton;
@property(nonatomic, strong, readonly) UIButton *undoButton;
@property(nonatomic, strong, readonly) UIButton *exportButton;
- (UIButton *)copyButton __attribute__((objc_method_family(none)));
@property(nonatomic, strong, readonly) UIButton *copyButton;
@property(nonatomic, strong, readonly) UIButton *doneButton;
@property(nonatomic, strong, readonly) UIButton *recognizeButton;
@property(nonatomic, strong, readonly) UIButton *importOverlayButton;
@property(nonatomic, strong, readonly) UISlider *widthSlider;
@property(nonatomic, strong, readonly) UILabel *hintLabel;
@property(nonatomic, strong, readonly) UILabel *statusLabel;
@property(nonatomic, copy, readonly) NSArray<UIButton *> *colorButtons;

/// Modes are 0: annotate, 1: cover, 2: OCR, 3: crop.
@property(nonatomic, copy, nullable) void (^modeSelectionHandler)(NSInteger mode);
@property(nonatomic, copy, nullable) void (^toolSelectionHandler)(KayokoFingerTool tool);
@property(nonatomic, copy, nullable) void (^colorSelectionHandler)(NSInteger colorIndex);

/// These updates do not send callbacks back to the owner.
- (void)setSelectedMode:(NSInteger)mode tool:(KayokoFingerTool)tool;
- (void)setSelectedColorIndex:(NSInteger)index;
- (void)setStrokeWidth:(CGFloat)width;
- (void)setCompactLayout:(BOOL)compact;
@end

NS_ASSUME_NONNULL_END
