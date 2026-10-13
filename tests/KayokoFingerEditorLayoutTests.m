#import <XCTest/XCTest.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>
#import "KayokoFingerEditorViewController.h"
#import "KayokoFingerEditorControlsView.h"
#import "KayokoFingerCanvasView.h"
#import "KayokoPreviewViewController.h"
#import "KayokoPreviewView.h"
#import "KayokoHeaderView.h"
#import "KayokoPasteboardItem.h"

@interface KayokoFingerCanvasView (StrokeTestEntryPoints)
- (void)beginStrokeAtPoint:(CGPoint)point;
- (void)appendPoint:(CGPoint)point;
- (void)finishStroke;
@end

// Keep the real controller's lifecycle/layout, while making safe areas and
// device dimensions deterministic on whichever simulator GitHub provides.
@interface KayokoTestSafeAreaView : UIView
@property(nonatomic) UIEdgeInsets simulatedInsets;
@end
@implementation KayokoTestSafeAreaView
- (UIEdgeInsets)safeAreaInsets { return self.simulatedInsets; }
@end

@interface KayokoTestEditorController : KayokoFingerEditorViewController
@property(nonatomic) UIEdgeInsets simulatedInsets;
@end
@implementation KayokoTestEditorController
- (void)loadView {
    KayokoTestSafeAreaView *view = [[KayokoTestSafeAreaView alloc] init];
    view.simulatedInsets = self.simulatedInsets;
    self.view = view;
}
@end

@interface KayokoFingerEditorLayoutTests : XCTestCase
@property(nonatomic, strong) NSURL *imageURL;
@end

@implementation KayokoFingerEditorLayoutTests

- (void)setUp {
    [super setUp];
    XCTAssertTrue(NSThread.isMainThread);
    self.imageURL = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
        URLByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"png"]];
    // A readable, self-contained image fixture makes the screenshots useful
    // without publishing a user's clipboard content in CI artifacts.
    UIGraphicsImageRendererFormat *format = [[UIGraphicsImageRendererFormat alloc] init];
    format.scale = 1;
    UIImage *image = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(600, 850) format:format]
        imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [[UIColor colorWithRed:0.91 green:0.94 blue:0.97 alpha:1] setFill];
            [context fillRect:CGRectMake(0, 0, 600, 850)];
            [UIColor.whiteColor setFill];
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(35, 40, 530, 765) cornerRadius:26] fill];
            [@"图片编辑" drawAtPoint:CGPointMake(70, 82) withAttributes:@{
                NSFontAttributeName: [UIFont boldSystemFontOfSize:40], NSForegroundColorAttributeName: UIColor.blackColor}];
            [@"FingerEditor · Kayoko" drawAtPoint:CGPointMake(70, 145) withAttributes:@{
                NSFontAttributeName: [UIFont systemFontOfSize:24], NSForegroundColorAttributeName: UIColor.darkGrayColor}];
            for (NSInteger row = 0; row < 5; row++) {
                CGFloat y = 225 + row * 96;
                [[UIColor colorWithRed:0.87 green:0.9 blue:0.94 alpha:1] setFill];
                [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(70, y, 64, 64) cornerRadius:12] fill];
                [[NSString stringWithFormat:@"示例内容 %ld", (long)row + 1]
                    drawAtPoint:CGPointMake(160, y + 2) withAttributes:@{
                        NSFontAttributeName: [UIFont systemFontOfSize:24], NSForegroundColorAttributeName: UIColor.blackColor}];
                [@"标注、遮盖、识别、裁剪" drawAtPoint:CGPointMake(160, y + 38) withAttributes:@{
                    NSFontAttributeName: [UIFont systemFontOfSize:19], NSForegroundColorAttributeName: UIColor.grayColor}];
            }
        }];
    XCTAssertTrue([UIImagePNGRepresentation(image) writeToURL:self.imageURL atomically:YES]);
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtURL:self.imageURL error:nil];
    [super tearDown];
}

- (UIView *)find:(NSString *)identifier inView:(UIView *)view {
    if ([view.accessibilityIdentifier isEqualToString:identifier]) return view;
    for (UIView *child in view.subviews) {
        UIView *match = [self find:identifier inView:child];
        if (match) return match;
    }
    return nil;
}

- (BOOL)isVisible:(UIView *)view relativeTo:(UIView *)root {
    for (UIView *ancestor = view; ancestor; ancestor = ancestor.superview) {
        if (ancestor.hidden || ancestor.alpha < 0.01) return NO;
        if (ancestor == root) return YES;
    }
    return NO;
}

- (void)assertVisibleControlsFit:(UIView *)view root:(UIView *)root {
    if (![self isVisible:view relativeTo:root]) return;
    if ([view isKindOfClass:UIControl.class] && [view.accessibilityIdentifier hasPrefix:@"finger."]) {
        CGRect rect = [view convertRect:view.bounds toView:root];
        XCTAssertGreaterThan(rect.size.width, 0, @"%@ must have width", view.accessibilityIdentifier);
        XCTAssertGreaterThan(rect.size.height, 0, @"%@ must have height", view.accessibilityIdentifier);
        XCTAssertTrue(CGRectContainsRect(CGRectInset(root.bounds, -0.5, -0.5), rect),
            @"%@ is outside viewport: %@ in %@", view.accessibilityIdentifier,
            NSStringFromCGRect(rect), NSStringFromCGRect(root.bounds));
        for (UIView *ancestor = view.superview; ancestor && ancestor != root; ancestor = ancestor.superview) {
            if (!ancestor.clipsToBounds) continue;
            CGRect clippingRect = [ancestor convertRect:ancestor.bounds toView:root];
            XCTAssertTrue(CGRectContainsRect(CGRectInset(clippingRect, -0.5, -0.5), rect),
                @"%@ is clipped by %@", view.accessibilityIdentifier, NSStringFromClass(ancestor.class));
        }
    }
    for (UIView *child in view.subviews) [self assertVisibleControlsFit:child root:root];
}

- (void)layoutEditor:(UIViewController *)editor {
    [editor.view setNeedsLayout];
    [editor.view layoutIfNeeded];
    // Offscreen containment still executes the controller's layout hooks. The
    // explicit layout pass also settles the canvas after asynchronous decoding.
    [editor viewDidLayoutSubviews];
    [editor.view layoutIfNeeded];
    for (UIView *child in editor.view.subviews) [child layoutIfNeeded];
}

- (KayokoTestEditorController *)editorInHost:(UIViewController *)host size:(CGSize)size insets:(UIEdgeInsets)insets {
    return [self editorInHost:host size:size insets:insets
        saveHandler:^(__unused NSURL *url, void (^completion)(NSError *)) { completion(nil); }
        didFinish:^(__unused BOOL saved) {}];
}

- (KayokoTestEditorController *)editorInHost:(UIViewController *)host size:(CGSize)size insets:(UIEdgeInsets)insets
                               saveHandler:(void (^)(NSURL *, void (^)(NSError *)))saveHandler
                                 didFinish:(void (^)(BOOL))didFinish {
    KayokoTestEditorController *editor = [[KayokoTestEditorController alloc] initWithImageURL:self.imageURL
        saveHandler:saveHandler didFinish:didFinish];
    editor.simulatedInsets = insets;
    editor.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
    host.view.frame = (CGRect){CGPointZero, size};
    [host addChildViewController:editor];
    editor.view.frame = host.view.bounds;
    [host.view addSubview:editor.view];
    [editor didMoveToParentViewController:host];
    [self layoutEditor:editor];
    NSPredicate *loaded = [NSPredicate predicateWithBlock:^BOOL(__unused id object, __unused NSDictionary *bindings) {
        KayokoFingerCanvasView *canvas = (id)[self find:@"finger.canvas" inView:editor.view];
        UIButton *done = (id)[self find:@"finger.done" inView:editor.view];
        return canvas.image != nil && done.enabled;
    }];
    XCTNSPredicateExpectation *ready = [[XCTNSPredicateExpectation alloc] initWithPredicate:loaded object:nil];
    XCTAssertEqual([XCTWaiter waitForExpectations:@[ready] timeout:10], XCTWaiterResultCompleted,
                   @"The actual image decoder must complete before checking layout");
    UIButton *cancel = (id)[self find:@"finger.cancel" inView:editor.view];
    XCTAssertEqualObjects(cancel.currentTitle, @"取消", @"Screenshots must load the shipped Chinese localization");
    [self layoutEditor:editor];
    return editor;
}

- (void)selectSegment:(NSInteger)index identifier:(NSString *)identifier editor:(UIViewController *)editor {
    UISegmentedControl *control = (id)[self find:identifier inView:editor.view];
    XCTAssertTrue([control isKindOfClass:UISegmentedControl.class], @"Missing %@", identifier);
    XCTAssertTrue([self isVisible:control relativeTo:editor.view], @"%@ must be visible", identifier);
    XCTAssertLessThan(index, control.numberOfSegments);
    control.selectedSegmentIndex = index;
    [control sendActionsForControlEvents:UIControlEventValueChanged];
    [self layoutEditor:editor];
}

- (void)attachEditor:(UIViewController *)editor name:(NSString *)name {
    UIGraphicsImageRendererFormat *format = [[UIGraphicsImageRendererFormat alloc] init];
    format.scale = 2;
    UIImage *image = [[[UIGraphicsImageRenderer alloc] initWithSize:editor.view.bounds.size format:format]
        imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [editor.view.layer renderInContext:context.CGContext];
        }];
    XCTAttachment *attachment = [XCTAttachment attachmentWithImage:image];
    attachment.name = name;
    attachment.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:attachment];
}

- (void)assertDockLayout:(UIViewController *)editor size:(CGSize)size insets:(UIEdgeInsets)insets {
    UIView *root = editor.view;
    UIView *canvas = [self find:@"finger.canvas" inView:root];
    UIView *controls = [self find:@"finger.controls" inView:root];
    UIView *lock = [self find:@"finger.lock" inView:root];
    XCTAssertNotNil(canvas);
    XCTAssertNotNil(controls);
    XCTAssertNotNil(lock);
    CGRect safe = UIEdgeInsetsInsetRect(root.bounds, insets);
    CGRect canvasRect = [canvas convertRect:canvas.bounds toView:root];
    CGRect dockRect = [controls convertRect:controls.bounds toView:root];
    CGRect lockRect = [lock convertRect:lock.bounds toView:root];
    XCTAssertTrue(CGRectContainsRect(CGRectInset(safe, -0.5, -0.5), canvasRect));
    XCTAssertTrue(CGRectContainsRect(CGRectInset(safe, -0.5, -0.5), dockRect));
    XCTAssertTrue(CGRectContainsRect(CGRectInset(canvasRect, -0.5, -0.5), lockRect), @"Move lock stays on the canvas");
    XCTAssertGreaterThanOrEqual(lockRect.size.width, 44);
    XCTAssertGreaterThanOrEqual(lockRect.size.height, 44);
    XCTAssertLessThanOrEqual(CGRectGetMaxY(safe) - CGRectGetMaxY(dockRect), 16);
    if (size.width < size.height) {
        XCTAssertEqualWithAccuracy(CGRectGetMinX(dockRect), CGRectGetMinX(safe) + 12, 0.5);
        XCTAssertEqualWithAccuracy(CGRectGetMaxX(dockRect), CGRectGetMaxX(safe) - 12, 0.5);
        XCTAssertLessThanOrEqual(CGRectGetMaxY(canvasRect), CGRectGetMinY(dockRect));
        XCTAssertGreaterThan(canvasRect.size.height, 100);
    } else {
        CGFloat contentWidth = safe.size.width - 24;
        XCTAssertEqualWithAccuracy(dockRect.size.width, MIN(350, floor(contentWidth * 0.48)), 0.5);
        XCTAssertLessThanOrEqual(CGRectGetMaxX(canvasRect), CGRectGetMinX(dockRect));
        XCTAssertGreaterThan(canvasRect.size.width, 200);
    }
    for (NSString *identifier in @[@"finger.cancel", @"finger.reset", @"finger.undo", @"finger.export", @"finger.copy", @"finger.done", @"finger.modes"]) {
        UIView *control = [self find:identifier inView:root];
        XCTAssertNotNil(control, @"Missing reachable action %@", identifier);
        XCTAssertTrue([self isVisible:control relativeTo:root]);
        CGRect rect = [control convertRect:control.bounds toView:root];
        if (size.width < size.height) {
            XCTAssertGreaterThan(CGRectGetMinY(rect), size.height * 0.5, @"%@ must stay in thumb reach", identifier);
        } else {
            XCTAssertGreaterThan(CGRectGetMinX(rect), size.width * 0.5, @"%@ must stay on the right", identifier);
        }
    }
    [self assertVisibleControlsFit:root root:root];
}

- (void)testAllModesRemainReachableOnSmallLargeAndLandscapePhones {
    NSArray<NSDictionary *> *fixtures = @[
        @{@"size": [NSValue valueWithCGSize:CGSizeMake(430, 932)], @"insets": [NSValue valueWithUIEdgeInsets:UIEdgeInsetsMake(59, 0, 34, 0)]},
        @{@"size": [NSValue valueWithCGSize:CGSizeMake(375, 667)], @"insets": [NSValue valueWithUIEdgeInsets:UIEdgeInsetsMake(20, 0, 0, 0)]},
        @{@"size": [NSValue valueWithCGSize:CGSizeMake(320, 568)], @"insets": [NSValue valueWithUIEdgeInsets:UIEdgeInsetsMake(20, 0, 0, 0)]},
        @{@"size": [NSValue valueWithCGSize:CGSizeMake(844, 390)], @"insets": [NSValue valueWithUIEdgeInsets:UIEdgeInsetsMake(0, 44, 21, 44)]}
    ];
    NSArray<NSString *> *modeNames = @[@"annotate", @"mask", @"ocr", @"crop"];
    for (NSDictionary *fixture in fixtures) {
        @autoreleasepool {
            CGSize size = [fixture[@"size"] CGSizeValue];
            UIEdgeInsets insets = [fixture[@"insets"] UIEdgeInsetsValue];
            UIViewController *host = [[UIViewController alloc] init];
            KayokoTestEditorController *editor = [self editorInHost:host size:size insets:insets];
            KayokoFingerCanvasView *canvas = (id)[self find:@"finger.canvas" inView:editor.view];
            for (NSInteger mode = 0; mode < 4; mode++) {
                [self selectSegment:mode identifier:@"finger.modes" editor:editor];
                [self assertDockLayout:editor size:size insets:insets];
                if (mode == 1) XCTAssertEqual(canvas.tool, kKayokoFingerToolCover);
                if (mode == 3) XCTAssertEqual(canvas.tool, kKayokoFingerToolCrop);
                if (mode == 2) {
                    UIView *recognize = [self find:@"finger.recognize" inView:editor.view];
                    XCTAssertTrue([self isVisible:recognize relativeTo:editor.view]);
                }
                [self attachEditor:editor name:[NSString stringWithFormat:@"editor-%.0fx%.0f-%@", size.width, size.height, modeNames[mode]]];
            }
            [editor invalidate];
            [editor willMoveToParentViewController:nil];
            [editor.view removeFromSuperview];
            [editor removeFromParentViewController];
        }
    }
}

- (void)testToolSelectionsColorsWidthAndMoveLockReachActualCanvas {
    UIViewController *host = [[UIViewController alloc] init];
    KayokoTestEditorController *editor = [self editorInHost:host size:CGSizeMake(430, 932)
                                                  insets:UIEdgeInsetsMake(59, 0, 34, 0)];
    KayokoFingerCanvasView *canvas = (id)[self find:@"finger.canvas" inView:editor.view];
    NSArray<NSNumber *> *annotationTools = @[@(kKayokoFingerToolArrow), @(kKayokoFingerToolRectangle),
        @(kKayokoFingerToolEllipse), @(kKayokoFingerToolText), @(kKayokoFingerToolPen), @(kKayokoFingerToolMosaic)];
    [self selectSegment:0 identifier:@"finger.modes" editor:editor];
    for (NSInteger index = 0; index < annotationTools.count; index++) {
        [self selectSegment:index identifier:@"finger.tool" editor:editor];
        XCTAssertEqual(canvas.tool, annotationTools[index].integerValue);
        XCTAssertFalse(canvas.navigationMode);
    }
    NSArray<NSNumber *> *mosaicTools = @[@(kKayokoFingerToolMosaic), @(kKayokoFingerToolCoarseMosaic), @(kKayokoFingerToolBlur)];
    for (NSInteger index = 0; index < mosaicTools.count; index++) {
        [self selectSegment:index identifier:@"finger.mosaic" editor:editor];
        XCTAssertEqual(canvas.tool, mosaicTools[index].integerValue);
        [self assertVisibleControlsFit:editor.view root:editor.view];
    }
    [self attachEditor:editor name:@"editor-430x932-mosaic-options"];
    [self selectSegment:1 identifier:@"finger.modes" editor:editor];
    [self selectSegment:1 identifier:@"finger.mask" editor:editor];
    XCTAssertEqual(canvas.tool, kKayokoFingerToolPixelate);
    [self selectSegment:0 identifier:@"finger.mask" editor:editor];
    XCTAssertEqual(canvas.tool, kKayokoFingerToolCover);
    UIButton *blue = (id)[self find:@"finger.color.3" inView:editor.view];
    [blue sendActionsForControlEvents:UIControlEventTouchUpInside];
    XCTAssertEqualObjects(canvas.strokeColor, UIColor.systemBlueColor);
    [self selectSegment:0 identifier:@"finger.modes" editor:editor];
    [self selectSegment:4 identifier:@"finger.tool" editor:editor];
    UISlider *width = (id)[self find:@"finger.width" inView:editor.view];
    width.value = 12;
    [width sendActionsForControlEvents:UIControlEventValueChanged];
    XCTAssertEqualWithAccuracy(canvas.strokeWidth, 12, 0.01);
    UIButton *lock = (id)[self find:@"finger.lock" inView:editor.view];
    [lock sendActionsForControlEvents:UIControlEventTouchUpInside];
    XCTAssertTrue(canvas.navigationMode);
    [lock sendActionsForControlEvents:UIControlEventTouchUpInside];
    XCTAssertFalse(canvas.navigationMode);
    [editor invalidate];
}

- (void)testBottomDonePersistsEditedImageAndWaitsForSaveCompletion {
    UIViewController *host = [[UIViewController alloc] init];
    __block void (^completeSave)(NSError *);
    __block NSData *savedImage;
    __block BOOL finished = NO;
    XCTestExpectation *didFinish = [self expectationWithDescription:@"Finish only after caller persists the PNG"];
    KayokoTestEditorController *editor = [self editorInHost:host size:CGSizeMake(375, 667)
        insets:UIEdgeInsetsMake(20, 0, 0, 0)
        saveHandler:^(NSURL *url, void (^completion)(NSError *)) {
            savedImage = [NSData dataWithContentsOfURL:url];
            completeSave = [completion copy];
        } didFinish:^(BOOL saved) {
            XCTAssertTrue(saved);
            finished = YES;
            [didFinish fulfill];
        }];
    KayokoFingerCanvasView *canvas = (id)[self find:@"finger.canvas" inView:editor.view];
    UIImage *original = canvas.image;
    KayokoFingerEditOperation *operation = [[KayokoFingerEditOperation alloc] init];
    operation.tool = kKayokoFingerToolCover;
    operation.points = @[[NSValue valueWithCGPoint:CGPointMake(0.2, 0.2)], [NSValue valueWithCGPoint:CGPointMake(0.8, 0.4)]];
    operation.color = UIColor.redColor;
    canvas.operationHandler(operation);
    NSPredicate *edited = [NSPredicate predicateWithBlock:^BOOL(__unused id object, __unused NSDictionary *bindings) {
        UIButton *reset = (id)[self find:@"finger.reset" inView:editor.view];
        return canvas.image != original && reset.enabled;
    }];
    XCTNSPredicateExpectation *ready = [[XCTNSPredicateExpectation alloc] initWithPredicate:edited object:nil];
    XCTAssertEqual([XCTWaiter waitForExpectations:@[ready] timeout:10], XCTWaiterResultCompleted);
    UIButton *done = (id)[self find:@"finger.done" inView:editor.view];
    [done sendActionsForControlEvents:UIControlEventTouchUpInside];
    XCTAssertNotNil([UIImage imageWithData:savedImage]);
    XCTAssertNotNil(completeSave);
    XCTAssertFalse(done.enabled, @"Repeated Done taps must be disabled while persistence is pending");
    XCTAssertFalse(finished, @"The editor must not report success before its caller saves the image");
    if (completeSave) completeSave(nil);
    [self waitForExpectations:@[didFinish] timeout:5];
    [editor invalidate];
}

- (void)waitUntilIdle:(UIViewController *)editor {
    NSPredicate *idle = [NSPredicate predicateWithBlock:^BOOL(__unused id object, __unused NSDictionary *bindings) {
        return ![[editor valueForKey:@"busy"] boolValue];
    }];
    XCTNSPredicateExpectation *ready = [[XCTNSPredicateExpectation alloc] initWithPredicate:idle object:nil];
    XCTAssertEqual([XCTWaiter waitForExpectations:@[ready] timeout:10], XCTWaiterResultCompleted);
}

- (void)testResetIsUndoableAndOriginalSurvivesRedoBranchAndHistoryLimit {
    UIViewController *host = [[UIViewController alloc] init];
    KayokoTestEditorController *editor = [self editorInHost:host size:CGSizeMake(375, 667)
                                                  insets:UIEdgeInsetsMake(20, 0, 0, 0)];
    KayokoFingerCanvasView *canvas = (id)[self find:@"finger.canvas" inView:editor.view];
    NSData *original = UIImagePNGRepresentation(canvas.image);
    KayokoFingerEditOperation *operation = [[KayokoFingerEditOperation alloc] init];
    operation.tool = kKayokoFingerToolCover;
    operation.points = @[[NSValue valueWithCGPoint:CGPointMake(0.2, 0.2)], [NSValue valueWithCGPoint:CGPointMake(0.8, 0.4)]];
    for (NSUInteger index = 0; index < 14; index++) {
        operation.color = index % 2 ? UIColor.redColor : UIColor.blueColor;
        canvas.operationHandler(operation);
        [self waitUntilIdle:editor];
    }
    NSData *edited = UIImagePNGRepresentation(canvas.image);
    XCTAssertNotEqualObjects(edited, original);
    UIButton *reset = (id)[self find:@"finger.reset" inView:editor.view];
    [reset sendActionsForControlEvents:UIControlEventTouchUpInside];
    [self waitUntilIdle:editor];
    XCTAssertEqualObjects(UIImagePNGRepresentation(canvas.image), original);
    UIButton *undo = (id)[self find:@"finger.undo" inView:editor.view];
    [undo sendActionsForControlEvents:UIControlEventTouchUpInside];
    [self waitUntilIdle:editor];
    XCTAssertEqualObjects(UIImagePNGRepresentation(canvas.image), edited, @"Reset must be undoable");
    operation.color = UIColor.greenColor;
    canvas.operationHandler(operation); // Removes the reset entry from the redo branch.
    [self waitUntilIdle:editor];
    [reset sendActionsForControlEvents:UIControlEventTouchUpInside];
    [self waitUntilIdle:editor];
    XCTAssertEqualObjects(UIImagePNGRepresentation(canvas.image), original, @"Original file must survive branch deletion");
    [editor invalidate];
}

- (NSData *)pixelsForView:(UIView *)view {
    UIGraphicsImageRendererFormat *format = [[UIGraphicsImageRendererFormat alloc] init];
    format.scale = 1;
    UIImage *image = [[[UIGraphicsImageRenderer alloc] initWithSize:view.bounds.size format:format]
        imageWithActions:^(UIGraphicsImageRendererContext *context) { [view.layer renderInContext:context.CGContext]; }];
    return UIImagePNGRepresentation(image);
}

- (void)testFingerUpKeepsStrokeAndToolbarStableUntilRasterIsReady {
    UIViewController *host = [[UIViewController alloc] init];
    KayokoTestEditorController *editor = [self editorInHost:host size:CGSizeMake(430, 932)
                                                  insets:UIEdgeInsetsMake(59, 0, 34, 0)];
    KayokoFingerCanvasView *canvas = (id)[self find:@"finger.canvas" inView:editor.view];
    KayokoFingerEditorControlsView *controls = (id)[self find:@"finger.controls" inView:editor.view];
    UIActivityIndicatorView *spinner = [editor valueForKey:@"spinner"];
    UIImageView *imageView = [canvas valueForKey:@"imageView"];
    UIScrollView *scroll = [canvas valueForKey:@"scrollView"];
    [scroll setZoomScale:2 animated:NO];
    CGPoint previousOffset = scroll.contentOffset;
    CGFloat zoom = scroll.zoomScale;
    canvas.tool = kKayokoFingerToolPen;
    UIImage *base = canvas.image;
    NSData *blankPixels = [self pixelsForView:imageView];
    dispatch_semaphore_t gate = dispatch_semaphore_create(0);
    dispatch_queue_t queue = [editor valueForKey:@"processingQueue"];
    dispatch_async(queue, ^{ dispatch_semaphore_wait(gate, dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC)); });
    @try {
        [canvas beginStrokeAtPoint:CGPointMake(imageView.bounds.size.width * 0.3, imageView.bounds.size.height * 0.4)];
        [canvas appendPoint:CGPointMake(imageView.bounds.size.width * 0.7, imageView.bounds.size.height * 0.6)];
        NSData *drawing = [self pixelsForView:imageView];
        XCTAssertNotEqualObjects(drawing, blankPixels);
        NSData *toolbarBefore = [self pixelsForView:controls];
        [self attachEditor:editor name:@"stroke-before-finger-up"];
        [canvas finishStroke];
        XCTAssertTrue(canvas.hasPendingOperation);
        XCTAssertEqual(canvas.image, base, @"The processing queue is deliberately held");
        XCTAssertEqualObjects(drawing, [self pixelsForView:imageView], @"No disappearing stroke at finger-up");
        XCTAssertEqualObjects(toolbarBefore, [self pixelsForView:controls], @"No dimmed or disabled-looking toolbar flash");
        XCTAssertFalse(spinner.animating);
        XCTAssertEqualWithAccuracy(controls.alpha, 1, 0.001);
        [self attachEditor:editor name:@"stroke-awaiting-raster"];
    } @finally {
        dispatch_semaphore_signal(gate);
    }
    [self waitUntilIdle:editor];
    XCTAssertFalse(canvas.hasPendingOperation);
    XCTAssertNotEqual(canvas.image, base);
    XCTAssertTrue(((CAShapeLayer *)[canvas valueForKey:@"previewLayer"]).path == NULL);
    XCTAssertNotEqualObjects([self pixelsForView:imageView], blankPixels);
    XCTAssertEqualWithAccuracy(scroll.zoomScale, zoom, 0.001);
    XCTAssertTrue(CGPointEqualToPoint(scroll.contentOffset, previousOffset));
    XCTAssertTrue(canvas.userInteractionEnabled);
    XCTAssertTrue(controls.userInteractionEnabled);
    [self attachEditor:editor name:@"stroke-committed"];
    [editor invalidate];
}

- (void)testFailedStrokeWriteClearsOverlayAndPreservesOriginal {
    UIViewController *host = [[UIViewController alloc] init];
    KayokoTestEditorController *editor = [self editorInHost:host size:CGSizeMake(375, 667)
                                                  insets:UIEdgeInsetsMake(20, 0, 0, 0)];
    KayokoFingerCanvasView *canvas = (id)[self find:@"finger.canvas" inView:editor.view];
    UIImageView *imageView = [canvas valueForKey:@"imageView"];
    UIImage *base = canvas.image;
    NSURL *directory = [editor valueForKey:@"directoryURL"];
    // Point future snapshot writes at a missing directory, without removing the current image.
    [editor setValue:[directory URLByAppendingPathComponent:@"unavailable"] forKey:@"directoryURL"];
    canvas.tool = kKayokoFingerToolPen;
    [canvas beginStrokeAtPoint:CGPointMake(30, 30)];
    [canvas appendPoint:CGPointMake(90, 90)];
    [canvas finishStroke];
    [self waitUntilIdle:editor];
    XCTAssertEqual(canvas.image, base);
    XCTAssertFalse(canvas.hasPendingOperation);
    XCTAssertTrue(((CAShapeLayer *)[canvas valueForKey:@"previewLayer"]).path == NULL);
    XCTAssertTrue(canvas.userInteractionEnabled);
    XCTAssertFalse(((UIActivityIndicatorView *)[editor valueForKey:@"spinner"]).animating);
    [editor setValue:directory forKey:@"directoryURL"];
    [editor invalidate];
    (void)imageView;
}

- (void)testImagePreviewHasOnlyNewEditorAndRightmostBackWhileTextKeepsEdit {
    for (NSNumber *widthValue in @[@320, @430]) {
        CGFloat width = widthValue.doubleValue;
        KayokoPreviewViewController *preview = [[KayokoPreviewViewController alloc] init];
        preview.view.frame = CGRectMake(0, 0, width, 600);
        preview.view.backgroundColor = UIColor.secondarySystemBackgroundColor;
        KayokoHeaderView *header = preview.previewView.headerView;
        [NSLayoutConstraint activateConstraints:@[
            [header.topAnchor constraintEqualToAnchor:preview.view.topAnchor],
            [header.leadingAnchor constraintEqualToAnchor:preview.view.leadingAnchor],
            [header.trailingAnchor constraintEqualToAnchor:preview.view.trailingAnchor]
        ]];
        KayokoPasteboardItem *image = [[KayokoPasteboardItem alloc] initWithBundleIdentifier:@"test"
            andContent:self.imageURL.lastPathComponent withImageNamed:self.imageURL.lastPathComponent];
        [preview showPreviewWithItem:image sourceHistoryKey:@"history"];
        [preview.view layoutIfNeeded];
        XCTAssertTrue(header.editButton.hidden, @"The retired simple image editor must not reappear");
        XCTAssertFalse(header.editButton.enabled);
        XCTAssertFalse(header.imageToolsButton.hidden);
        XCTAssertTrue(header.imageToolsButton.enabled);
        XCTAssertTrue(header.leadingButtonOnTrailingSide);
        XCTAssertTrue(((NSLayoutConstraint *)[header valueForKey:@"leadingButtonRightConstraint"]).active);
        XCTAssertFalse(((NSLayoutConstraint *)[header valueForKey:@"leadingButtonLeftConstraint"]).active);
        XCTAssertEqualWithAccuracy(((NSLayoutConstraint *)[header valueForKey:@"trailingStackTrailingConstraint"]).constant, -64, 0.01);
        CGRect back = [header.leadingButton convertRect:header.leadingButton.bounds toView:header];
        for (UIButton *button in @[header.imageToolsButton, header.shareButton, header.trailingButton]) {
            CGRect action = [button convertRect:button.bounds toView:header];
            XCTAssertLessThan(CGRectGetMaxX(action), CGRectGetMinX(back));
        }
        XCTAssertGreaterThan(CGRectGetMidX(back), width - 50);
        [self attachEditor:preview name:[NSString stringWithFormat:@"image-preview-right-back-%.0f", width]];
        KayokoPasteboardItem *text = [[KayokoPasteboardItem alloc] initWithBundleIdentifier:@"test" andContent:@"Editable text" withImageNamed:@""];
        [preview showPreviewWithItem:text sourceHistoryKey:@"history"];
        [preview.view layoutIfNeeded];
        XCTAssertFalse(header.editButton.hidden);
        XCTAssertTrue(header.editButton.enabled);
        XCTAssertTrue(header.imageToolsButton.hidden);
        XCTAssertFalse(header.leadingButtonOnTrailingSide);
        XCTAssertLessThan(CGRectGetMidX(header.leadingButton.frame), 60);
    }
}

@end
