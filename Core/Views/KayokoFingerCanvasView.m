#import "KayokoFingerCanvasView.h"
#import "KayokoPasteboardManager.h"
#import <QuartzCore/QuartzCore.h>
#import <math.h>

static CGFloat const kKayokoFingerMaximumZoom = 8.0;
static CGFloat const kKayokoFingerMinimumDrag = 6.0;

@interface KayokoFingerCanvasView () <UIScrollViewDelegate, UIGestureRecognizerDelegate>
@property(nonatomic, strong) UIScrollView *scrollView;
@property(nonatomic, strong) UIImageView *imageView;
@property(nonatomic, strong) CAShapeLayer *previewLayer;
@property(nonatomic, strong) UIPanGestureRecognizer *drawingGesture;
@property(nonatomic, strong) UITapGestureRecognizer *tapGesture;
@property(nonatomic, strong, nullable) NSMutableArray<NSValue *> *drawingPoints;
@property(nonatomic, strong, nullable) UIBezierPath *brushPreviewPath;
@property(nonatomic, assign) KayokoFingerTool drawingTool;
@property(nonatomic, strong, nullable) UIColor *drawingColor;
@property(nonatomic, assign) CGFloat drawingWidth;
@property(nonatomic, assign) CGSize layoutSize;
@property(nonatomic, assign) BOOL needsFit;
@end

@implementation KayokoFingerCanvasView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _strokeColor = [UIColor systemRedColor];
        _strokeWidth = 6.0;
        _tool = kKayokoFingerToolPen;
        _needsFit = YES;
        self.clipsToBounds = YES;
        self.backgroundColor = [UIColor secondarySystemBackgroundColor];

        _scrollView = [[UIScrollView alloc] initWithFrame:self.bounds];
        _scrollView.delegate = self;
        _scrollView.minimumZoomScale = 1.0;
        _scrollView.maximumZoomScale = kKayokoFingerMaximumZoom;
        _scrollView.bounces = NO;
        _scrollView.bouncesZoom = NO;
        _scrollView.showsHorizontalScrollIndicator = NO;
        _scrollView.showsVerticalScrollIndicator = NO;
        _scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
        _scrollView.panGestureRecognizer.minimumNumberOfTouches = 2;
        [self addSubview:_scrollView];

        _imageView = [[UIImageView alloc] init];
        _imageView.contentMode = UIViewContentModeScaleToFill;
        _imageView.userInteractionEnabled = YES;
        _imageView.clipsToBounds = YES;
        _imageView.isAccessibilityElement = YES;
        _imageView.accessibilityTraits = UIAccessibilityTraitImage | UIAccessibilityTraitAllowsDirectInteraction;
        NSBundle *bundle = [KayokoPasteboardManager localizationBundle];
        _imageView.accessibilityLabel = [bundle localizedStringForKey:@"Image canvas" value:nil table:@"Tweak"];
        _imageView.accessibilityHint = [bundle localizedStringForKey:@"Draw with one finger. Pinch to zoom or drag with two fingers to move."
                                                             value:nil table:@"Tweak"];
        [_scrollView addSubview:_imageView];

        _previewLayer = [CAShapeLayer layer];
        _previewLayer.lineCap = kCALineCapRound;
        _previewLayer.lineJoin = kCALineJoinRound;
        _previewLayer.fillColor = nil;
        _previewLayer.actions = @{@"path": [NSNull null], @"bounds": [NSNull null], @"position": [NSNull null],
                                  @"lineWidth": [NSNull null], @"strokeColor": [NSNull null], @"fillColor": [NSNull null]};
        [_imageView.layer addSublayer:_previewLayer];

        _drawingGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleDrawing:)];
        _drawingGesture.minimumNumberOfTouches = 1;
        _drawingGesture.maximumNumberOfTouches = 1;
        _drawingGesture.delegate = self;
        [_imageView addGestureRecognizer:_drawingGesture];

        _tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
        _tapGesture.delegate = self;
        [_tapGesture requireGestureRecognizerToFail:_drawingGesture];
        [_imageView addGestureRecognizer:_tapGesture];

        // Cancel a preview as soon as navigation starts, including when a second
        // finger is added to a stroke that has already begun.
        [_scrollView.panGestureRecognizer addTarget:self action:@selector(handleNavigationGesture:)];
        [_scrollView.pinchGestureRecognizer addTarget:self action:@selector(handleNavigationGesture:)];
    }
    return self;
}

- (void)setImage:(UIImage *)image {
    CGSize oldSize = CGSizeMake(_image.size.width * _image.scale, _image.size.height * _image.scale);
    CGSize newSize = CGSizeMake(image.size.width * image.scale, image.size.height * image.scale);
    _image = image;
    self.imageView.image = image;
    [self clearPreview];
    if (!CGSizeEqualToSize(oldSize, newSize)) {
        self.needsFit = YES;
        [self setNeedsLayout];
    }
}

- (void)setTool:(KayokoFingerTool)tool {
    if (_tool == tool) return;
    _tool = tool;
    [self clearPreview];
}

- (CGFloat)imageLineWidth {
    [self layoutIfNeeded];
    CGFloat pixelsPerPoint = self.image.size.width * self.image.scale /
                             MAX(1.0, self.imageView.bounds.size.width);
    return MAX(1.0, self.strokeWidth) * pixelsPerPoint / MAX(1.0, self.scrollView.zoomScale);
}

- (void)setNavigationMode:(BOOL)navigationMode {
    _navigationMode = navigationMode;
    [self clearPreview];
    self.drawingGesture.enabled = !navigationMode;
    self.tapGesture.enabled = !navigationMode;
    self.scrollView.panGestureRecognizer.minimumNumberOfTouches = navigationMode ? 1 : 2;
}

- (void)resetZoom {
    [self clearPreview];
    self.needsFit = YES;
    [self setNeedsLayout];
    [self layoutIfNeeded];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize viewport = self.bounds.size;
    if (CGSizeEqualToSize(self.layoutSize, viewport) && !self.needsFit) return;

    CGPoint normalizedCenter = CGPointMake(0.5, 0.5);
    CGFloat zoom = self.needsFit ? 1.0 : self.scrollView.zoomScale;
    if (!self.needsFit && self.imageView.bounds.size.width > 0 && self.imageView.bounds.size.height > 0) {
        CGPoint oldCenter = CGPointMake(CGRectGetMidX(self.scrollView.bounds), CGRectGetMidY(self.scrollView.bounds));
        normalizedCenter = [self normalizedPoint:[self.imageView convertPoint:oldCenter fromView:self.scrollView]];
    }
    [self clearPreview];
    self.scrollView.frame = self.bounds;
    self.layoutSize = viewport;
    if (!self.image || viewport.width <= 0 || viewport.height <= 0 ||
        self.image.size.width <= 0 || self.image.size.height <= 0) {
        self.scrollView.zoomScale = 1.0;
        self.imageView.frame = CGRectZero;
        self.scrollView.contentSize = CGSizeZero;
        return;
    }

    CGFloat fit = MIN(viewport.width / self.image.size.width, viewport.height / self.image.size.height);
    CGSize baseSize = CGSizeMake(self.image.size.width * fit, self.image.size.height * fit);
    self.scrollView.zoomScale = 1.0;
    self.imageView.frame = (CGRect){CGPointZero, baseSize};
    self.previewLayer.frame = self.imageView.bounds;
    self.scrollView.contentSize = baseSize;
    self.scrollView.zoomScale = MIN(kKayokoFingerMaximumZoom, MAX(1.0, zoom));
    [self centerImage];

    CGPoint center = [self.imageView convertPoint:CGPointMake(normalizedCenter.x * baseSize.width,
                                                             normalizedCenter.y * baseSize.height)
                                         toView:self.scrollView];
    CGPoint offset = CGPointMake(center.x - viewport.width / 2.0, center.y - viewport.height / 2.0);
    offset.x = MAX(0, MIN(offset.x, self.scrollView.contentSize.width - viewport.width));
    offset.y = MAX(0, MIN(offset.y, self.scrollView.contentSize.height - viewport.height));
    self.scrollView.contentOffset = offset;
    self.needsFit = NO;
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return self.imageView;
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView {
    [self centerImage];
}

- (void)centerImage {
    CGSize viewport = self.scrollView.bounds.size;
    CGSize content = self.scrollView.contentSize;
    self.imageView.center = CGPointMake(MAX(viewport.width, content.width) / 2.0,
                                       MAX(viewport.height, content.height) / 2.0);
}

- (void)handleNavigationGesture:(UIGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged) {
        [self clearPreview];
    }
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (self.navigationMode || !self.image || self.scrollView.isZooming || self.scrollView.isDragging) return NO;
    if (gestureRecognizer == self.drawingGesture && self.tool == kKayokoFingerToolText) return NO;
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
        shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    // Allow UIScrollView to take over a drawing gesture when two fingers arrive.
    // Its two-finger pan/pinch targets clear the transient stroke before commit.
    return otherGestureRecognizer == self.scrollView.panGestureRecognizer ||
           otherGestureRecognizer == self.scrollView.pinchGestureRecognizer;
}

- (CGPoint)normalizedPoint:(CGPoint)point {
    CGSize size = self.imageView.bounds.size;
    return CGPointMake(MAX(0.0, MIN(1.0, point.x / MAX(size.width, 1.0))),
                       MAX(0.0, MIN(1.0, point.y / MAX(size.height, 1.0))));
}

- (CGPoint)displayPoint:(CGPoint)normalizedPoint {
    return CGPointMake(normalizedPoint.x * self.imageView.bounds.size.width,
                       normalizedPoint.y * self.imageView.bounds.size.height);
}

- (BOOL)isBrushTool:(KayokoFingerTool)tool {
    return tool == kKayokoFingerToolPen || tool == kKayokoFingerToolMosaic ||
           tool == kKayokoFingerToolCoarseMosaic || tool == kKayokoFingerToolBlur;
}

- (void)beginStrokeAtPoint:(CGPoint)point {
    self.drawingTool = self.tool;
    self.drawingColor = self.strokeColor;
    self.drawingWidth = MAX(1.0, self.strokeWidth) / MAX(1.0, self.scrollView.zoomScale);
    self.drawingPoints = [NSMutableArray arrayWithObject:[NSValue valueWithCGPoint:[self normalizedPoint:point]]];
    self.brushPreviewPath = [UIBezierPath bezierPath];
    [self.brushPreviewPath moveToPoint:point];
    self.previewLayer.lineWidth = self.drawingWidth;
    self.previewLayer.fillColor = nil;
    self.previewLayer.lineDashPattern = nil;
    self.previewLayer.strokeColor = self.drawingColor.CGColor;
    if (self.drawingTool == kKayokoFingerToolCrop) {
        self.previewLayer.strokeColor = [UIColor whiteColor].CGColor;
        self.previewLayer.lineWidth = 2.0 / self.scrollView.zoomScale;
        self.previewLayer.lineDashPattern = @[@(6.0 / self.scrollView.zoomScale), @(4.0 / self.scrollView.zoomScale)];
    } else if (self.drawingTool == kKayokoFingerToolCover || self.drawingTool == kKayokoFingerToolSticker) {
        self.previewLayer.fillColor = [self.drawingColor colorWithAlphaComponent:0.5].CGColor;
    } else if (self.drawingTool == kKayokoFingerToolPixelate) {
        self.previewLayer.fillColor = [[UIColor systemGrayColor] colorWithAlphaComponent:0.45].CGColor;
    } else if (self.drawingTool == kKayokoFingerToolMosaic || self.drawingTool == kKayokoFingerToolCoarseMosaic ||
               self.drawingTool == kKayokoFingerToolBlur) {
        self.previewLayer.strokeColor = [[UIColor systemGrayColor] colorWithAlphaComponent:0.65].CGColor;
    }
}

- (void)handleDrawing:(UIPanGestureRecognizer *)gesture {
    CGPoint point = [gesture locationInView:self.imageView];
    if (gesture.state == UIGestureRecognizerStateBegan) {
        CGPoint translation = [gesture translationInView:self.imageView];
        CGPoint start = CGPointMake(point.x - translation.x, point.y - translation.y);
        if (!CGRectContainsPoint(self.imageView.bounds, start)) return;
        [self beginStrokeAtPoint:start];
        [self appendPoint:point];
    } else if (gesture.state == UIGestureRecognizerStateChanged) {
        if (gesture.numberOfTouches != 1 || self.scrollView.isZooming || self.scrollView.isDragging) {
            [self clearPreview];
            return;
        }
        [self appendPoint:point];
    } else if (gesture.state == UIGestureRecognizerStateEnded) {
        [self appendPoint:point];
        [self finishStroke];
    } else if (gesture.state == UIGestureRecognizerStateCancelled || gesture.state == UIGestureRecognizerStateFailed) {
        [self clearPreview];
    }
}

- (void)handleTap:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateRecognized || self.navigationMode) return;
    CGPoint point = [gesture locationInView:self.imageView];
    if (!CGRectContainsPoint(self.imageView.bounds, point)) return;
    if (self.tool == kKayokoFingerToolText) {
        if (self.textPositionHandler) self.textPositionHandler([self normalizedPoint:point]);
    } else if ([self isBrushTool:self.tool]) {
        [self beginStrokeAtPoint:point];
        [self finishStroke];
    }
}

- (void)appendPoint:(CGPoint)point {
    if (!self.drawingPoints) return;
    CGPoint normalized = [self normalizedPoint:point];
    CGPoint clamped = [self displayPoint:normalized];
    if ([self isBrushTool:self.drawingTool]) {
        CGPoint previous = [self displayPoint:self.drawingPoints.lastObject.CGPointValue];
        if (hypot(clamped.x - previous.x, clamped.y - previous.y) * self.scrollView.zoomScale < 0.5) return;
        [self.drawingPoints addObject:[NSValue valueWithCGPoint:normalized]];
        [self.brushPreviewPath addLineToPoint:clamped];
        self.previewLayer.path = self.brushPreviewPath.CGPath;
        return;
    }
    if (self.drawingPoints.count == 1) [self.drawingPoints addObject:[NSValue valueWithCGPoint:normalized]];
    else self.drawingPoints[1] = [NSValue valueWithCGPoint:normalized];
    CGPoint start = [self displayPoint:self.drawingPoints.firstObject.CGPointValue];
    CGRect rect = CGRectMake(MIN(start.x, clamped.x), MIN(start.y, clamped.y),
                             fabs(start.x - clamped.x), fabs(start.y - clamped.y));
    UIBezierPath *path;
    if (self.drawingTool == kKayokoFingerToolArrow) {
        path = [UIBezierPath bezierPath];
        [path moveToPoint:start];
        [path addLineToPoint:clamped];
        CGFloat angle = atan2(clamped.y - start.y, clamped.x - start.x);
        CGFloat head = MIN(hypot(clamped.x - start.x, clamped.y - start.y) * 0.45,
                           MAX(12.0 / self.scrollView.zoomScale, self.drawingWidth * 3.0));
        [path moveToPoint:CGPointMake(clamped.x - head * cos(angle - M_PI / 6.0),
                                     clamped.y - head * sin(angle - M_PI / 6.0))];
        [path addLineToPoint:clamped];
        [path addLineToPoint:CGPointMake(clamped.x - head * cos(angle + M_PI / 6.0),
                                        clamped.y - head * sin(angle + M_PI / 6.0))];
    } else if (self.drawingTool == kKayokoFingerToolEllipse) {
        path = [UIBezierPath bezierPathWithOvalInRect:rect];
    } else {
        path = [UIBezierPath bezierPathWithRect:rect];
    }
    self.previewLayer.path = path.CGPath;
}

- (void)finishStroke {
    if (!self.drawingPoints.count) return;
    if (![self isBrushTool:self.drawingTool]) {
        CGPoint start = [self displayPoint:self.drawingPoints.firstObject.CGPointValue];
        CGPoint end = [self displayPoint:self.drawingPoints.lastObject.CGPointValue];
        CGFloat width = fabs(end.x - start.x) * self.scrollView.zoomScale;
        CGFloat height = fabs(end.y - start.y) * self.scrollView.zoomScale;
        BOOL tooSmall = self.drawingTool == kKayokoFingerToolArrow ? hypot(width, height) < kKayokoFingerMinimumDrag :
                        (width < kKayokoFingerMinimumDrag || height < kKayokoFingerMinimumDrag);
        if (tooSmall) {
            [self clearPreview];
            return;
        }
    }
    KayokoFingerEditOperation *operation = [[KayokoFingerEditOperation alloc] init];
    operation.tool = self.drawingTool;
    operation.points = [self.drawingPoints copy];
    operation.color = self.drawingColor ?: self.strokeColor;
    operation.lineWidth = self.drawingWidth * (self.image.size.width * self.image.scale) /
                          MAX(1.0, self.imageView.bounds.size.width);
    [self clearPreview];
    if (self.operationHandler) self.operationHandler(operation);
}

- (void)clearPreview {
    self.drawingPoints = nil;
    self.brushPreviewPath = nil;
    self.previewLayer.path = nil;
}

@end
