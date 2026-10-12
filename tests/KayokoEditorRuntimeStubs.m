// The real controller, canvas, controls and renderer are linked into this test
// bundle. Only SpringBoard's localization provider and OCR service are replaced.
#import <UIKit/UIKit.h>

@interface KayokoPasteboardManager : NSObject
+ (NSBundle *)localizationBundle;
@end

@implementation KayokoPasteboardManager
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
