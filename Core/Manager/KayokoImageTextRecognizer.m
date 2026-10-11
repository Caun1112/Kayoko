//
//  KayokoImageTextRecognizer.m
//  Kayoko
//

#import "KayokoImageTextRecognizer.h"

#import <HBLog.h>
#import <UIKit/UIKit.h>
#import <Vision/Vision.h>

static NSString *const kKayokoImageTextRecognizerQueueName = @"com.mlgm.kayoko.queue.ocr";
// 中文截图占多数，英文紧随其后；顺序即优先级。
static NSString *const kKayokoImageTextRecognizerChineseLanguage = @"zh-Hans";
static NSString *const kKayokoImageTextRecognizerEnglishLanguage = @"en-US";
// 多行结果用换行拼接：搜索走子串匹配，拼接方式不影响检索，但保留分行便于日后展示。
static NSString *const kKayokoImageTextRecognizerLineSeparator = @"\n";
// 识别前把长边压到这个上限。识别发生在 SpringBoard 进程里，全尺寸截图（长边 2500+）直接送进
// Vision 的 accurate 模式内存峰值很高，有被 jetsam 干掉的风险；降采样后精度对截图文字仍然够用。
static CGFloat const kKayokoImageTextRecognizerMaximumDimension = 2048.0;

@interface KayokoImageTextRecognizer ()

@property(nonatomic, strong) dispatch_queue_t recognitionQueue;

@end

@implementation KayokoImageTextRecognizer

#pragma mark - Lifecycle

+ (instancetype)sharedRecognizer {
    static KayokoImageTextRecognizer *sharedRecognizer = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      sharedRecognizer = [[self alloc] init];
    });
    return sharedRecognizer;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _recognitionQueue = dispatch_queue_create([kKayokoImageTextRecognizerQueueName UTF8String],
                                                  DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

#pragma mark - Recognition

- (void)recognizeTextInImageAtPath:(NSString *)imagePath completion:(void (^)(NSString *_Nullable))completion {
    if (!completion) {
        return;
    }
    if ([imagePath length] == 0) {
        completion(nil);
        return;
    }

    NSString *path = [imagePath copy];
    dispatch_async(_recognitionQueue, ^{
      NSString *text = nil;
      @autoreleasepool {
          text = [self recognizedTextInImageAtPath:path];
      }
      dispatch_async(dispatch_get_main_queue(), ^{
        completion(text);
      });
    });
}

- (nullable NSString *)recognizedTextInImageAtPath:(NSString *)imagePath {
    UIImage *image = [self downscaledImageForRecognition:[UIImage imageWithContentsOfFile:imagePath]];
    CGImageRef cgImage = [image CGImage];
    if (!cgImage) {
        return nil;
    }

    VNRecognizeTextRequest *request = [[VNRecognizeTextRequest alloc] init];
    request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
    request.usesLanguageCorrection = YES;
    request.recognitionLanguages = @[ kKayokoImageTextRecognizerChineseLanguage, kKayokoImageTextRecognizerEnglishLanguage ];

    if (![self performRequest:request onCGImage:cgImage]) {
        // 指定语言不被支持时（缺中文识别模型）退回系统默认语言，至少别让整个功能哑掉。
        VNRecognizeTextRequest *fallbackRequest = [[VNRecognizeTextRequest alloc] init];
        fallbackRequest.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
        fallbackRequest.usesLanguageCorrection = YES;
        if (![self performRequest:fallbackRequest onCGImage:cgImage]) {
            return nil;
        }
        request = fallbackRequest;
    }

    NSMutableArray<NSString *> *lines = [[NSMutableArray alloc] init];
    for (VNRecognizedTextObservation *observation in [request results]) {
        NSString *line = [[[observation topCandidates:1] firstObject] string];
        if ([line length] > 0) {
            [lines addObject:line];
        }
    }
    if ([lines count] == 0) {
        return nil;
    }
    return [lines componentsJoinedByString:kKayokoImageTextRecognizerLineSeparator];
}

- (nullable UIImage *)downscaledImageForRecognition:(nullable UIImage *)image {
    if (!image) {
        return nil;
    }

    CGSize pixelSize = CGSizeMake([image size].width * [image scale], [image size].height * [image scale]);
    CGFloat largestDimension = MAX(pixelSize.width, pixelSize.height);
    if (largestDimension <= kKayokoImageTextRecognizerMaximumDimension) {
        return image;
    }

    CGFloat ratio = kKayokoImageTextRecognizerMaximumDimension / largestDimension;
    CGSize targetSize = CGSizeMake(floor(pixelSize.width * ratio), floor(pixelSize.height * ratio));
    UIGraphicsBeginImageContextWithOptions(targetSize, NO, 1.0);
    [image drawInRect:CGRectMake(0, 0, targetSize.width, targetSize.height)];
    UIImage *downscaledImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return downscaledImage ?: image;
}

- (BOOL)performRequest:(VNRecognizeTextRequest *)request onCGImage:(CGImageRef)cgImage {
    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:cgImage options:@{}];
    NSError *error = nil;
    if ([handler performRequests:@[ request ] error:&error]) {
        return YES;
    }
    HBLogDebug(@"Kayoko: Image text recognition failed: %@", error);
    return NO;
}

@end
