//
//  KayokoImageTextRecognizer.h
//  Kayoko
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 用系统 Vision 框架对复制进来的图片做文字识别（OCR），识别结果交给调用方去落库。
///
/// 识别在私有串行队列上进行，磁盘读取也放在该队列，因此调用方（粘贴板捕获队列）只做入队、
/// 不会被识别耗时拖住——自动粘贴与捕获共用 _pasteboardQueue，挡住它会直接让点选粘贴变卡。
@interface KayokoImageTextRecognizer : NSObject

+ (instancetype)sharedRecognizer;

/// 识别图片文件中的文字。回调固定派发到主队列；识别失败或图内无文字时 text 为 nil。
- (void)recognizeTextInImageAtPath:(NSString *)imagePath completion:(void (^)(NSString *_Nullable text))completion;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
