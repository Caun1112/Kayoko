//
//  KayokoFingerImageRenderer.m
//  Kayoko
//
//  Native UIKit adaptation of the user's FingerEditor ImageProcessor.swift
//  (https://github.com/Caun1112/FingerEditor), retaining its normalized drawing
//  coordinates and fine/coarse mosaic and blur behavior for iOS 14 and later.
//

#import "KayokoFingerImageRenderer.h"

#import <CoreImage/CoreImage.h>
#import <ImageIO/ImageIO.h>
#import <math.h>
#import <string.h>

static const CGFloat KayokoFingerMaximumEdge = 4096;
static const double KayokoFingerMaximumPixels = 4000000;

@implementation KayokoFingerEditOperation

- (instancetype)init {
    self = [super init];
    if (self) {
        _tool = kKayokoFingerToolPen;
        _points = @[];
        _color = [UIColor systemRedColor];
        _lineWidth = 8;
        _text = @"";
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    KayokoFingerEditOperation *copy = [[[self class] allocWithZone:zone] init];
    copy.tool = self.tool;
    copy.points = self.points;
    copy.color = self.color;
    copy.lineWidth = self.lineWidth;
    copy.text = self.text;
    copy.stickerImage = self.stickerImage;
    return copy;
}

@end

static BOOL KayokoFingerValidSize(CGSize size) {
    return isfinite(size.width) && isfinite(size.height) && size.width >= 1 && size.height >= 1;
}

static UIGraphicsImageRendererFormat *KayokoFingerRendererFormat(void) {
    UIGraphicsImageRendererFormat *format = [[UIGraphicsImageRendererFormat alloc] init];
    format.scale = 1;
    format.opaque = NO;
    format.preferredRange = UIGraphicsImageRendererFormatRangeStandard;
    return format;
}

static UIImage *KayokoFingerUprightImage(UIImage *image) {
    if (!image.CGImage) {
        return nil;
    }
    if (image.imageOrientation == UIImageOrientationUp) {
        return [UIImage imageWithCGImage:image.CGImage scale:1 orientation:UIImageOrientationUp];
    }
    CGSize size = CGSizeMake(image.size.width * image.scale, image.size.height * image.scale);
    if (!KayokoFingerValidSize(size)) {
        return nil;
    }
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size
                                                                            format:KayokoFingerRendererFormat()];
    UIImage *result = [renderer imageWithActions:^(__unused UIGraphicsImageRendererContext *context) {
        [image drawInRect:(CGRect){CGPointZero, size}];
    }];
    return result.CGImage ? result : nil;
}

static BOOL KayokoFingerReadPoints(NSArray<NSValue *> *values, CGSize size, NSMutableArray<NSValue *> *points) {
    if (![values isKindOfClass:[NSArray class]] || values.count == 0) {
        return NO;
    }
    for (NSValue *value in values) {
        if (![value isKindOfClass:[NSValue class]] || strcmp(value.objCType, @encode(CGPoint)) != 0) {
            return NO;
        }
        CGPoint point = value.CGPointValue;
        if (!isfinite(point.x) || !isfinite(point.y)) {
            return NO;
        }
        point.x = MIN(1, MAX(0, point.x)) * size.width;
        point.y = MIN(1, MAX(0, point.y)) * size.height;
        [points addObject:[NSValue valueWithCGPoint:point]];
    }
    return YES;
}

static CGRect KayokoFingerOperationRect(NSArray<NSValue *> *points, CGSize size) {
    if (points.count < 2) {
        return CGRectNull;
    }
    CGPoint first = points.firstObject.CGPointValue;
    CGPoint last = points.lastObject.CGPointValue;
    CGRect rect = CGRectStandardize(CGRectMake(first.x, first.y, last.x - first.x, last.y - first.y));
    rect = CGRectIntersection(rect, (CGRect){CGPointZero, size});
    // A click or a one-dimensional drag is not a crop/region operation.
    return CGRectIsNull(rect) || rect.size.width < 1 || rect.size.height < 1 ? CGRectNull : rect;
}

static UIBezierPath *KayokoFingerStrokePath(NSArray<NSValue *> *points, CGFloat width) {
    UIBezierPath *path = [UIBezierPath bezierPath];
    path.lineWidth = width;
    path.lineCapStyle = kCGLineCapRound;
    path.lineJoinStyle = kCGLineJoinRound;
    [path moveToPoint:points.firstObject.CGPointValue];
    for (NSUInteger index = 1; index < points.count; index++) {
        [path addLineToPoint:points[index].CGPointValue];
    }
    return path;
}

static BOOL KayokoFingerStrokeIsDot(NSArray<NSValue *> *points) {
    CGPoint first = points.firstObject.CGPointValue;
    for (NSValue *value in points) {
        CGPoint point = value.CGPointValue;
        if (hypot(point.x - first.x, point.y - first.y) >= 0.01) {
            return NO;
        }
    }
    return YES;
}

static UIBezierPath *KayokoFingerBrushOutline(NSArray<NSValue *> *points, CGFloat width) {
    if (KayokoFingerStrokeIsDot(points)) {
        CGPoint center = points.firstObject.CGPointValue;
        return [UIBezierPath bezierPathWithOvalInRect:CGRectMake(center.x - width / 2, center.y - width / 2,
                                                                width, width)];
    }
    UIBezierPath *stroke = KayokoFingerStrokePath(points, width);
    CGPathRef outline = CGPathCreateCopyByStrokingPath(stroke.CGPath, NULL, width, kCGLineCapRound,
                                                     kCGLineJoinRound, 10);
    if (!outline) {
        return nil;
    }
    UIBezierPath *result = [UIBezierPath bezierPathWithCGPath:outline];
    CGPathRelease(outline);
    return result;
}

static UIImage *KayokoFingerPrivacyImage(UIImage *image, KayokoFingerTool tool, CGFloat width) {
    CIImage *input = [CIImage imageWithCGImage:image.CGImage];
    CIFilter *filter = nil;
    if (tool == kKayokoFingerToolBlur) {
        filter = [CIFilter filterWithName:@"CIGaussianBlur"];
        [filter setValue:[input imageByClampingToExtent] forKey:kCIInputImageKey];
        [filter setValue:@(MAX(8, width * 1.8)) forKey:kCIInputRadiusKey];
    } else {
        filter = [CIFilter filterWithName:@"CIPixellate"];
        [filter setValue:input forKey:kCIInputImageKey];
        CGFloat pixelScale = MAX(6, width * 1.2);
        if (tool == kKayokoFingerToolCoarseMosaic) {
            pixelScale = MAX(14, width * 2.4);
        } else if (tool == kKayokoFingerToolPixelate) {
            pixelScale = MAX(12, MIN(image.size.width, image.size.height) / 80);
        }
        [filter setValue:@(pixelScale) forKey:kCIInputScaleKey];
        [filter setValue:[CIVector vectorWithX:image.size.width / 2 Y:image.size.height / 2] forKey:kCIInputCenterKey];
    }
    CIImage *output = [filter.outputImage imageByCroppingToRect:input.extent];
    if (!output) {
        return nil;
    }
    static CIContext *context;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        context = [CIContext contextWithOptions:@{kCIContextCacheIntermediates: @NO}];
    });
    CGImageRef processed = [context createCGImage:output fromRect:input.extent];
    if (!processed) {
        return nil;
    }
    UIImage *result = [UIImage imageWithCGImage:processed scale:1 orientation:UIImageOrientationUp];
    CGImageRelease(processed);
    return result;
}

@implementation KayokoFingerImageRenderer

+ (UIImage *)preparedImageAtURL:(NSURL *)url {
    if (!url.isFileURL) {
        return nil;
    }
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url,
                                                        (__bridge CFDictionaryRef)@{(id)kCGImageSourceShouldCache: @NO});
    if (!source) {
        return nil;
    }
    NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL));
    double width = [properties[(id)kCGImagePropertyPixelWidth] doubleValue];
    double height = [properties[(id)kCGImagePropertyPixelHeight] doubleValue];
    if (!isfinite(width) || !isfinite(height) || width < 1 || height < 1) {
        CFRelease(source);
        return nil;
    }
    double longest = MAX(width, height);
    double scale = MIN(1, MIN(KayokoFingerMaximumEdge / longest,
                              sqrt(KayokoFingerMaximumPixels / (width * height))));
    size_t maxPixelSize = MAX((size_t)1, (size_t)floor(longest * scale));
    NSDictionary *options = @{
        (id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (id)kCGImageSourceCreateThumbnailWithTransform: @YES,
        (id)kCGImageSourceThumbnailMaxPixelSize: @(maxPixelSize),
        (id)kCGImageSourceShouldCacheImmediately: @YES,
    };
    CGImageRef thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
    CFRelease(source);
    if (!thumbnail) {
        return nil;
    }
    UIImage *image = [UIImage imageWithCGImage:thumbnail scale:1 orientation:UIImageOrientationUp];
    CGImageRelease(thumbnail);
    // Some codecs round thumbnail dimensions up; enforce the pixel budget too.
    CGSize size = image.size;
    double pixels = size.width * size.height;
    if (MAX(size.width, size.height) > KayokoFingerMaximumEdge || pixels > KayokoFingerMaximumPixels) {
        CGFloat finalScale = MIN(KayokoFingerMaximumEdge / MAX(size.width, size.height),
                                 sqrt(KayokoFingerMaximumPixels / pixels));
        CGSize bounded = CGSizeMake(MAX(1, floor(size.width * finalScale)), MAX(1, floor(size.height * finalScale)));
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:bounded
                                                                                format:KayokoFingerRendererFormat()];
        image = [renderer imageWithActions:^(__unused UIGraphicsImageRendererContext *context) {
            [image drawInRect:(CGRect){CGPointZero, bounded}];
        }];
    }
    return image.CGImage ? image : nil;
}

+ (UIImage *)image:(UIImage *)source byApplyingOperation:(KayokoFingerEditOperation *)operation {
    if (!source || !operation || !isfinite(operation.lineWidth) || operation.lineWidth <= 0 || !operation.color ||
        operation.tool < kKayokoFingerToolPen || operation.tool > kKayokoFingerToolSticker) {
        return nil;
    }
    UIImage *image = KayokoFingerUprightImage(source);
    if (!image || !KayokoFingerValidSize(image.size)) {
        return nil;
    }
    CGSize size = image.size;
    NSMutableArray<NSValue *> *points = [[NSMutableArray alloc] initWithCapacity:operation.points.count];
    if (!KayokoFingerReadPoints(operation.points, size, points)) {
        return nil;
    }
    CGRect bounds = (CGRect){CGPointZero, size};
    CGRect rect = KayokoFingerOperationRect(points, size);
    CGFloat lineWidth = MIN(MAX(1, operation.lineWidth), MAX(size.width, size.height));
    KayokoFingerTool tool = operation.tool;
    BOOL region = tool == kKayokoFingerToolRectangle || tool == kKayokoFingerToolEllipse ||
                  tool == kKayokoFingerToolCover || tool == kKayokoFingerToolPixelate ||
                  tool == kKayokoFingerToolCrop || tool == kKayokoFingerToolSticker;
    if (region && CGRectIsNull(rect)) {
        return nil;
    }
    if (tool == kKayokoFingerToolCrop) {
        rect = CGRectIntersection(CGRectIntegral(rect), bounds);
        CGImageRef cropped = CGImageCreateWithImageInRect(image.CGImage, rect);
        if (!cropped) {
            return nil;
        }
        UIImage *result = [UIImage imageWithCGImage:cropped scale:1 orientation:UIImageOrientationUp];
        CGImageRelease(cropped);
        return result;
    }
    if (tool == kKayokoFingerToolArrow &&
        (points.count < 2 || hypot(points.lastObject.CGPointValue.x - points.firstObject.CGPointValue.x,
                                  points.lastObject.CGPointValue.y - points.firstObject.CGPointValue.y) < 1)) {
        return nil;
    }
    NSString *text = [operation.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (tool == kKayokoFingerToolText && text.length == 0) {
        return nil;
    }
    UIImage *sticker = nil;
    if (tool == kKayokoFingerToolSticker) {
        sticker = KayokoFingerUprightImage(operation.stickerImage);
        if (!sticker || !KayokoFingerValidSize(sticker.size)) {
            return nil;
        }
    }
    BOOL privacyBrush = tool == kKayokoFingerToolMosaic || tool == kKayokoFingerToolCoarseMosaic ||
                        tool == kKayokoFingerToolBlur;
    UIImage *processed = nil;
    UIBezierPath *brushOutline = nil;
    if (privacyBrush || tool == kKayokoFingerToolPixelate) {
        processed = KayokoFingerPrivacyImage(image, tool, lineWidth);
        if (!processed) {
            return nil;
        }
        if (privacyBrush) {
            brushOutline = KayokoFingerBrushOutline(points, lineWidth);
            if (!brushOutline) {
                return nil;
            }
        }
    }

    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size
                                                                            format:KayokoFingerRendererFormat()];
    UIImage *result = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [image drawInRect:bounds];
        [operation.color setStroke];
        [operation.color setFill];
        switch (tool) {
            case kKayokoFingerToolPen: {
                if (KayokoFingerStrokeIsDot(points)) {
                    [KayokoFingerBrushOutline(points, lineWidth) fill];
                } else {
                    [KayokoFingerStrokePath(points, lineWidth) stroke];
                }
                break;
            }
            case kKayokoFingerToolArrow: {
                CGPoint start = points.firstObject.CGPointValue;
                CGPoint end = points.lastObject.CGPointValue;
                CGFloat angle = atan2(end.y - start.y, end.x - start.x);
                CGFloat length = hypot(end.x - start.x, end.y - start.y);
                CGFloat head = MIN(MAX(16, lineWidth * 4.2), length * 0.6);
                UIBezierPath *path = KayokoFingerStrokePath(@[points.firstObject, points.lastObject], lineWidth);
                [path moveToPoint:CGPointMake(end.x - head * cos(angle - M_PI / 7), end.y - head * sin(angle - M_PI / 7))];
                [path addLineToPoint:end];
                [path addLineToPoint:CGPointMake(end.x - head * cos(angle + M_PI / 7), end.y - head * sin(angle + M_PI / 7))];
                [path stroke];
                break;
            }
            case kKayokoFingerToolRectangle:
            case kKayokoFingerToolEllipse: {
                UIBezierPath *path = tool == kKayokoFingerToolRectangle ? [UIBezierPath bezierPathWithRect:rect]
                                                                     : [UIBezierPath bezierPathWithOvalInRect:rect];
                path.lineWidth = lineWidth;
                [path stroke];
                break;
            }
            case kKayokoFingerToolText: {
                CGFloat fontSize = MAX(18, lineWidth * 2.6);
                NSDictionary *attributes = @{NSFontAttributeName: [UIFont systemFontOfSize:fontSize weight:UIFontWeightBold],
                                             NSForegroundColorAttributeName: operation.color};
                CGPoint point = points.firstObject.CGPointValue;
                CGSize textSize = [text sizeWithAttributes:attributes];
                point.x = MIN(point.x, MAX(0, size.width - textSize.width));
                point.y = MIN(point.y, MAX(0, size.height - textSize.height));
                [text drawAtPoint:point withAttributes:attributes];
                break;
            }
            case kKayokoFingerToolMosaic:
            case kKayokoFingerToolCoarseMosaic:
            case kKayokoFingerToolBlur:
                CGContextSaveGState(context.CGContext);
                [brushOutline addClip];
                [processed drawInRect:bounds];
                CGContextRestoreGState(context.CGContext);
                break;
            case kKayokoFingerToolCover:
                [context fillRect:rect];
                break;
            case kKayokoFingerToolPixelate:
                CGContextSaveGState(context.CGContext);
                CGContextClipToRect(context.CGContext, rect);
                [processed drawInRect:bounds];
                CGContextRestoreGState(context.CGContext);
                break;
            case kKayokoFingerToolSticker: {
                CGFloat scale = MIN(rect.size.width / sticker.size.width, rect.size.height / sticker.size.height);
                CGSize fitted = CGSizeMake(sticker.size.width * scale, sticker.size.height * scale);
                CGRect destination = CGRectMake(CGRectGetMidX(rect) - fitted.width / 2,
                                                 CGRectGetMidY(rect) - fitted.height / 2, fitted.width, fitted.height);
                [sticker drawInRect:destination];
                break;
            }
            case kKayokoFingerToolCrop:
                break; // Handled above without rendering unrelated pixels.
        }
    }];
    return result.CGImage ? result : nil;
}

@end
