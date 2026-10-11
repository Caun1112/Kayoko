// Renderer regressions for an iOS XCTest host linking UIKit, ImageIO and CoreImage.
// The Theos tweak itself deliberately does not include test files.
#import <XCTest/XCTest.h>
#import <ImageIO/ImageIO.h>
#import "../Core/Models/KayokoFingerImageRenderer.h"

@interface KayokoFingerImageRendererTests : XCTestCase
@property(nonatomic, strong) NSMutableArray<NSURL *> *temporaryURLs;
@end

@implementation KayokoFingerImageRendererTests

- (void)setUp {
    [super setUp];
    self.temporaryURLs = [[NSMutableArray alloc] init];
}

- (void)tearDown {
    for (NSURL *url in self.temporaryURLs) {
        [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
    }
    [super tearDown];
}

- (UIImage *)imageWithSize:(CGSize)size checkerboard:(BOOL)checkerboard {
    UIGraphicsImageRendererFormat *format = [[UIGraphicsImageRendererFormat alloc] init];
    format.scale = 1;
    format.preferredRange = UIGraphicsImageRendererFormatRangeStandard;
    return [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format]
        imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [[UIColor whiteColor] setFill];
            [context fillRect:(CGRect){CGPointZero, size}];
            if (checkerboard) {
                [[UIColor blackColor] setFill];
                for (NSInteger y = 0; y < size.height; y++) {
                    for (NSInteger x = y % 2; x < size.width; x += 2) {
                        [context fillRect:CGRectMake(x, y, 1, 1)];
                    }
                }
            }
        }];
}

- (NSURL *)writeImage:(UIImage *)image orientation:(NSInteger)orientation {
    NSURL *url = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
        URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.png", NSUUID.UUID.UUIDString]];
    [self.temporaryURLs addObject:url];
    CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)url,
                                                                       CFSTR("public.png"), 1, NULL);
    XCTAssertTrue(destination != NULL);
    if (destination) {
        CGImageDestinationAddImage(destination, image.CGImage,
                                   (__bridge CFDictionaryRef)@{(id)kCGImagePropertyOrientation: @(orientation)});
        XCTAssertTrue(CGImageDestinationFinalize(destination));
        CFRelease(destination);
    }
    return url;
}

- (uint32_t)pixelInImage:(UIImage *)image x:(size_t)x y:(size_t)y {
    CGImageRef pixel = CGImageCreateWithImageInRect(image.CGImage, CGRectMake(x, y, 1, 1));
    uint8_t rgba[4] = {0};
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(rgba, 1, 1, 8, 4, colorSpace,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    XCTAssertTrue(pixel != NULL && context != NULL);
    if (pixel && context) {
        CGContextDrawImage(context, CGRectMake(0, 0, 1, 1), pixel);
    }
    if (context) CGContextRelease(context);
    if (pixel) CGImageRelease(pixel);
    CGColorSpaceRelease(colorSpace);
    return ((uint32_t)rgba[0] << 24) | ((uint32_t)rgba[1] << 16) | ((uint32_t)rgba[2] << 8) | rgba[3];
}

- (KayokoFingerEditOperation *)operation:(KayokoFingerTool)tool from:(CGPoint)start to:(CGPoint)end {
    KayokoFingerEditOperation *operation = [[KayokoFingerEditOperation alloc] init];
    operation.tool = tool;
    operation.points = @[[NSValue valueWithCGPoint:start], [NSValue valueWithCGPoint:end]];
    operation.color = UIColor.redColor;
    operation.lineWidth = 16;
    return operation;
}

- (void)testThumbnailKeepsSmallResolutionAndBoundsLargeImages {
    for (NSValue *sizeValue in @[[NSValue valueWithCGSize:CGSizeMake(80, 60)],
                                [NSValue valueWithCGSize:CGSizeMake(6000, 1000)],
                                [NSValue valueWithCGSize:CGSizeMake(4000, 3000)]]) {
        @autoreleasepool {
            CGSize size = sizeValue.CGSizeValue;
            NSURL *url = [self writeImage:[self imageWithSize:size checkerboard:NO] orientation:1];
            UIImage *prepared = [KayokoFingerImageRenderer preparedImageAtURL:url];
            XCTAssertNotNil(prepared);
            XCTAssertLessThanOrEqual(MAX(prepared.size.width, prepared.size.height), 4096);
            XCTAssertLessThanOrEqual(prepared.size.width * prepared.size.height, 4000000);
            XCTAssertLessThanOrEqual(prepared.size.width, size.width);
            XCTAssertLessThanOrEqual(prepared.size.height, size.height);
            if (size.width == 80) XCTAssertTrue(CGSizeEqualToSize(prepared.size, size));
            XCTAssertEqual(prepared.scale, 1);
            XCTAssertEqual(prepared.imageOrientation, UIImageOrientationUp);
        }
    }
}

- (void)testThumbnailAppliesEXIFOrientationBeforeEditing {
    UIImage *base = [self imageWithSize:CGSizeMake(80, 60) checkerboard:NO];
    KayokoFingerEditOperation *redCorner = [self operation:kKayokoFingerToolCover
                                                     from:CGPointZero to:CGPointMake(0.25, 0.25)];
    UIImage *marked = [KayokoFingerImageRenderer image:base byApplyingOperation:redCorner];
    NSURL *url = [self writeImage:marked orientation:6]; // 90 degrees clockwise.
    UIImage *prepared = [KayokoFingerImageRenderer preparedImageAtURL:url];
    XCTAssertNotNil(prepared);
    XCTAssertTrue(CGSizeEqualToSize(prepared.size, CGSizeMake(60, 80)));
    XCTAssertEqual([self pixelInImage:prepared x:58 y:1], 0xff0000ffu);
    XCTAssertEqual([self pixelInImage:prepared x:1 y:1], 0xffffffffu);
}

- (void)testReverseCropUsesTopLeftCoordinatesAndRejectsFlatSelection {
    UIImage *base = [self imageWithSize:CGSizeMake(80, 60) checkerboard:NO];
    KayokoFingerEditOperation *cover = [self operation:kKayokoFingerToolCover
                                                 from:CGPointMake(0.25, 0.25) to:CGPointMake(0.75, 0.75)];
    UIImage *marked = [KayokoFingerImageRenderer image:base byApplyingOperation:cover];
    KayokoFingerEditOperation *crop = [self operation:kKayokoFingerToolCrop
                                                from:CGPointMake(0.75, 0.75) to:CGPointMake(0.25, 0.25)];
    UIImage *result = [KayokoFingerImageRenderer image:marked byApplyingOperation:crop];
    XCTAssertNotNil(result);
    XCTAssertTrue(CGSizeEqualToSize(result.size, CGSizeMake(40, 30)));
    XCTAssertEqual([self pixelInImage:result x:1 y:1], 0xff0000ffu);
    crop.points = @[[NSValue valueWithCGPoint:CGPointMake(0.5, 0.1)],
                    [NSValue valueWithCGPoint:CGPointMake(0.5, 0.9)]];
    XCTAssertNil([KayokoFingerImageRenderer image:base byApplyingOperation:crop]);
}

- (void)testCoverAndStickerOnlyTouchTheirSelectedRegions {
    UIImage *base = [self imageWithSize:CGSizeMake(100, 100) checkerboard:NO];
    KayokoFingerEditOperation *cover = [self operation:kKayokoFingerToolCover
                                                 from:CGPointMake(0.25, 0.25) to:CGPointMake(0.75, 0.75)];
    UIImage *covered = [KayokoFingerImageRenderer image:base byApplyingOperation:cover];
    XCTAssertEqual([self pixelInImage:covered x:50 y:50], 0xff0000ffu);
    XCTAssertEqual([self pixelInImage:covered x:1 y:1], 0xffffffffu);

    UIImage *stickerBase = [self imageWithSize:CGSizeMake(100, 50) checkerboard:NO];
    cover.points = @[[NSValue valueWithCGPoint:CGPointZero], [NSValue valueWithCGPoint:CGPointMake(1, 1)]];
    UIImage *redSticker = [KayokoFingerImageRenderer image:stickerBase byApplyingOperation:cover];
    KayokoFingerEditOperation *sticker = [self operation:kKayokoFingerToolSticker
                                                   from:CGPointMake(0.1, 0.1) to:CGPointMake(0.9, 0.9)];
    sticker.stickerImage = redSticker;
    UIImage *result = [KayokoFingerImageRenderer image:base byApplyingOperation:sticker];
    XCTAssertNotNil(result);
    XCTAssertEqual([self pixelInImage:result x:50 y:50], 0xff0000ffu);
    XCTAssertEqual([self pixelInImage:result x:50 y:20], 0xffffffffu); // Aspect-fit top margin.
    XCTAssertEqual([self pixelInImage:result x:50 y:80], 0xffffffffu);
    XCTAssertEqual([self pixelInImage:result x:1 y:50], 0xffffffffu);
}

- (void)testAllPrivacyToolsChangePixelsOnlyInsideSelection {
    UIImage *base = [self imageWithSize:CGSizeMake(96, 96) checkerboard:YES];
    for (NSNumber *value in @[@(kKayokoFingerToolMosaic), @(kKayokoFingerToolCoarseMosaic),
                              @(kKayokoFingerToolBlur), @(kKayokoFingerToolPixelate)]) {
        KayokoFingerTool tool = value.integerValue;
        KayokoFingerEditOperation *operation = [self operation:tool
                                                         from:CGPointMake(0.25, tool == kKayokoFingerToolPixelate ? 0.25 : 0.5)
                                                           to:CGPointMake(0.75, tool == kKayokoFingerToolPixelate ? 0.75 : 0.5)];
        UIImage *result = [KayokoFingerImageRenderer image:base byApplyingOperation:operation];
        XCTAssertNotNil(result, @"Privacy tool %@ must report a result", value);
        XCTAssertEqual([self pixelInImage:result x:1 y:1], [self pixelInImage:base x:1 y:1]);
        NSUInteger changed = 0;
        for (size_t y = 45; y < 51; y++) {
            for (size_t x = 35; x < 60; x++) {
                changed += [self pixelInImage:result x:x y:y] != [self pixelInImage:base x:x y:y];
            }
        }
        XCTAssertGreaterThan(changed, 0u, @"Privacy tool %@ must actually alter the selected pixels", value);
    }
}

- (void)testInvalidEditsFailAndOperationCopyIsIndependent {
    UIImage *base = [self imageWithSize:CGSizeMake(80, 60) checkerboard:NO];
    KayokoFingerEditOperation *operation = [[KayokoFingerEditOperation alloc] init];
    XCTAssertNil([KayokoFingerImageRenderer image:base byApplyingOperation:operation]);
    operation.points = @[[NSValue valueWithCGPoint:CGPointMake(NAN, 0.5)]];
    XCTAssertNil([KayokoFingerImageRenderer image:base byApplyingOperation:operation]);
    operation.points = @[[NSValue valueWithCGPoint:CGPointMake(0.5, 0.5)]];
    operation.tool = kKayokoFingerToolText;
    operation.text = @" \n ";
    XCTAssertNil([KayokoFingerImageRenderer image:base byApplyingOperation:operation]);
    operation.tool = kKayokoFingerToolSticker;
    operation.points = @[[NSValue valueWithCGPoint:CGPointZero], [NSValue valueWithCGPoint:CGPointMake(1, 1)]];
    XCTAssertNil([KayokoFingerImageRenderer image:base byApplyingOperation:operation]);
    operation.tool = kKayokoFingerToolPen;
    KayokoFingerEditOperation *copy = [operation copy];
    operation.points = @[];
    operation.lineWidth = 30;
    XCTAssertEqual(copy.points.count, 2u);
    XCTAssertEqual(copy.lineWidth, 8);
    XCTAssertNotNil([KayokoFingerImageRenderer image:base byApplyingOperation:copy]);
}

@end
