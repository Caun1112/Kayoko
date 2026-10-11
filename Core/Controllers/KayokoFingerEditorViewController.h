#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// In-process adaptation of FingerEditor's image tools. The caller persists the
/// supplied PNG before invoking the save completion; failed saves stay editable.
@interface KayokoFingerEditorViewController : UIViewController
- (instancetype)initWithImageURL:(NSURL *)imageURL
                     saveHandler:(void (^)(NSURL *outputURL, void (^completion)(NSError *_Nullable error)))saveHandler
                       didFinish:(void (^)(BOOL saved))didFinish NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)name bundle:(nullable NSBundle *)bundle NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (void)invalidate;
@end

NS_ASSUME_NONNULL_END
