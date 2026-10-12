#import <UIKit/UIKit.h>
#import "KayokoFingerImageRenderer.h"

NS_ASSUME_NONNULL_BEGIN

/// A zoomable, aspect-fit image canvas. Operations use normalized image points
/// and pixel widths so the renderer does not depend on the current viewport.
@interface KayokoFingerCanvasView : UIView

@property(nonatomic, strong, nullable) UIImage *image;
@property(nonatomic, assign) KayokoFingerTool tool;
@property(nonatomic, strong) UIColor *strokeColor;
@property(nonatomic, assign) CGFloat strokeWidth;
@property(nonatomic, assign, readonly) CGFloat imageLineWidth;
@property(nonatomic, assign) BOOL navigationMode;
@property(nonatomic, copy, nullable) void (^operationHandler)(KayokoFingerEditOperation *operation);
@property(nonatomic, copy, nullable) void (^textPositionHandler)(CGPoint normalizedPosition);

/// Remains YES between finger-up and the atomic image/preview handoff.
@property(nonatomic, readonly) BOOL hasPendingOperation;
- (void)cancelPendingOperation;
- (void)resetZoom;

@end

NS_ASSUME_NONNULL_END
