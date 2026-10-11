//
//  KayokoFingerImageRenderer.h
//  Kayoko
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, KayokoFingerTool) {
    kKayokoFingerToolPen,
    kKayokoFingerToolArrow,
    kKayokoFingerToolRectangle,
    kKayokoFingerToolEllipse,
    kKayokoFingerToolText,
    kKayokoFingerToolMosaic,
    kKayokoFingerToolCoarseMosaic,
    kKayokoFingerToolBlur,
    kKayokoFingerToolCover,
    kKayokoFingerToolPixelate,
    kKayokoFingerToolCrop,
    kKayokoFingerToolSticker,
};

@interface KayokoFingerEditOperation : NSObject <NSCopying>
@property(nonatomic) KayokoFingerTool tool;
// Top-left-origin normalized image coordinates; rectangles use first and last points.
@property(nonatomic, copy) NSArray<NSValue *> *points;
@property(nonatomic, strong) UIColor *color;
@property(nonatomic) CGFloat lineWidth; // Image pixels, independent of the canvas zoom.
@property(nonatomic, copy) NSString *text;
@property(nonatomic, strong, nullable) UIImage *stickerImage;
@end

@interface KayokoFingerImageRenderer : NSObject
// Decodes the first image frame, applies EXIF orientation and limits the decoded
// image to a 4096-pixel edge and 4 million pixels. Small images are not enlarged.
+ (nullable UIImage *)preparedImageAtURL:(NSURL *)url;
// Returns a flattened, upright, scale-1 image, or nil for invalid/failed edits.
// Call serially off the main thread; the operation is copied by the caller.
+ (nullable UIImage *)image:(UIImage *)image byApplyingOperation:(KayokoFingerEditOperation *)operation;
@end

NS_ASSUME_NONNULL_END
