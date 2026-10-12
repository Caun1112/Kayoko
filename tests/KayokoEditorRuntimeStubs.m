// The real controller, canvas, controls and renderer are linked into this test
// bundle. Only SpringBoard's localization provider and OCR service are replaced.
#import <UIKit/UIKit.h>

@interface KayokoPasteboardManager : NSObject
+ (NSBundle *)localizationBundle;
+ (instancetype)sharedInstance;
+ (NSString *)historyImagesPath;
- (void)canRestoreImageForPasteboardItem:(id)item inHistoryWithKey:(NSString *)key completion:(void (^)(BOOL, NSError *))completion;
@end

@implementation KayokoPasteboardManager
+ (instancetype)sharedInstance {
    static KayokoPasteboardManager *manager;
    static dispatch_once_t token;
    dispatch_once(&token, ^{ manager = [[self alloc] init]; });
    return manager;
}
+ (NSString *)historyImagesPath { return NSTemporaryDirectory(); }
- (void)canRestoreImageForPasteboardItem:(id)item inHistoryWithKey:(NSString *)key completion:(void (^)(BOOL, NSError *))completion {
    completion(NO, nil);
}
+ (NSBundle *)localizationBundle {
    NSBundle *bundle = [NSBundle bundleForClass:self];
    NSString *path = [bundle pathForResource:@"zh-Hans" ofType:@"lproj"];
    return path ? [NSBundle bundleWithPath:path] : bundle;
}
@end

@interface KayokoImageTextRecognizer : NSObject
+ (instancetype)sharedRecognizer;
- (void)recognizeTextInImageAtPath:(NSString *)path completion:(void (^)(NSString *))completion;
@end

@implementation KayokoImageTextRecognizer
+ (instancetype)sharedRecognizer {
    static KayokoImageTextRecognizer *recognizer;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ recognizer = [[self alloc] init]; });
    return recognizer;
}
- (void)recognizeTextInImageAtPath:(NSString *)path completion:(void (^)(NSString *))completion {
    dispatch_async(dispatch_get_main_queue(), ^{ completion(@"图片编辑布局测试\nSample image"); });
}
@end

// System-sharing/database services are not invoked by the preview layout tests.
@interface KayokoHistoryItemActionHandler : NSObject @end
@implementation KayokoHistoryItemActionHandler @end
@interface KayokoActivitySharePresenter : NSObject @end
@implementation KayokoActivitySharePresenter @end
@interface KayokoTextActionPresenter : NSObject
- (BOOL)isTranslationAvailable;
@end
@implementation KayokoTextActionPresenter
- (BOOL)isTranslationAvailable { return NO; }
@end
@interface KayokoMainView : UIView @end
@implementation KayokoMainView @end
