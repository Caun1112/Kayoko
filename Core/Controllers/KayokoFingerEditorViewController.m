#import "KayokoFingerEditorViewController.h"
#import "KayokoFingerCanvasView.h"
#import "KayokoFingerEditorControlsView.h"
#import "KayokoFingerImageRenderer.h"
#import "KayokoImageTextRecognizer.h"
#import "KayokoPasteboardManager.h"
#import <PhotosUI/PhotosUI.h>
#import <math.h>

static NSString *KayokoFingerString(NSString *key) {
    return [[KayokoPasteboardManager localizationBundle] localizedStringForKey:key value:key table:@"Tweak"];
}

static NSError *KayokoFingerError(NSString *key) {
    return [NSError errorWithDomain:@"com.mlgm.kayoko.finger-editor" code:1
                          userInfo:@{NSLocalizedDescriptionKey: KayokoFingerString(key)}];
}

@interface KayokoFingerEditorViewController () <PHPickerViewControllerDelegate>
@property(nonatomic, strong) NSURL *inputURL;
@property(nonatomic, strong) NSURL *directoryURL;
@property(nonatomic, strong) NSMutableArray<NSURL *> *snapshots;
@property(nonatomic, strong, nullable) NSURL *originalSnapshotURL;
@property(nonatomic) NSUInteger snapshotIndex;
@property(nonatomic, strong) dispatch_queue_t processingQueue;
@property(nonatomic, copy, nullable) void (^saveHandler)(NSURL *, void (^)(NSError *_Nullable));
@property(nonatomic, copy, nullable) void (^didFinish)(BOOL);
@property(nonatomic) BOOL busy;
@property(nonatomic) BOOL saving;
@property(nonatomic) BOOL invalidated;
@property(nonatomic, strong) KayokoFingerCanvasView *canvas;
@property(nonatomic, strong) KayokoFingerEditorControlsView *controls;
@property(nonatomic, strong) UIButton *lockButton;
@property(nonatomic) NSInteger selectedMode;
@property(nonatomic) KayokoFingerTool annotationTool;
@property(nonatomic) KayokoFingerTool maskTool;
@property(nonatomic) BOOL imageNavigationUnlocked;
@property(nonatomic, strong) UIActivityIndicatorView *spinner;
@property(nonatomic, strong, nullable) UIImage *stickerImage;
@end

@implementation KayokoFingerEditorViewController

- (instancetype)initWithImageURL:(NSURL *)imageURL
                     saveHandler:(void (^)(NSURL *, void (^)(NSError *_Nullable)))saveHandler
                       didFinish:(void (^)(BOOL))didFinish {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _inputURL = imageURL;
        _saveHandler = [saveHandler copy];
        _didFinish = [didFinish copy];
        _snapshots = [NSMutableArray array];
        _processingQueue = dispatch_queue_create("com.mlgm.kayoko.finger-editor", DISPATCH_QUEUE_SERIAL);
        _directoryURL = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
            URLByAppendingPathComponent:[@"KayokoFingerEditing" stringByAppendingPathComponent:NSUUID.UUID.UUIDString]
                             isDirectory:YES];
        self.modalPresentationStyle = UIModalPresentationOverFullScreen;
        self.modalInPresentation = YES;
        self.modalPresentationCapturesStatusBarAppearance = YES;
    }
    return self;
}

- (void)dealloc {
    [[NSFileManager defaultManager] removeItemAtURL:_directoryURL error:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? [UIColor colorWithWhite:0.08 alpha:1] :
            [UIColor colorWithRed:0.985 green:0.985 blue:0.975 alpha:1];
    }];
    self.view.tintColor = UIColor.labelColor;
    self.annotationTool = kKayokoFingerToolArrow;
    self.maskTool = kKayokoFingerToolCover;
    self.canvas = [[KayokoFingerCanvasView alloc] initWithFrame:CGRectZero];
    self.canvas.accessibilityIdentifier = @"finger.canvas";
    self.canvas.tool = self.annotationTool;
    self.canvas.strokeColor = UIColor.systemRedColor;
    self.canvas.strokeWidth = 8;
    self.canvas.layer.cornerRadius = 8;
    self.canvas.layer.borderWidth = 0.5;
    self.canvas.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? [UIColor colorWithWhite:0.12 alpha:1] :
            [UIColor colorWithRed:0.918 green:0.924 blue:0.910 alpha:1];
    }];
    __weak typeof(self) weakSelf = self;
    self.canvas.operationHandler = ^(KayokoFingerEditOperation *operation) { [weakSelf applyOperation:operation]; };
    self.canvas.textPositionHandler = ^(CGPoint point) { [weakSelf requestTextAtPoint:point]; };
    [self.view addSubview:self.canvas];

    self.controls = [[KayokoFingerEditorControlsView alloc] initWithFrame:CGRectZero];
    self.controls.accessibilityIdentifier = @"finger.controls";
    self.controls.modeSelectionHandler = ^(NSInteger mode) { [weakSelf selectMode:mode]; };
    self.controls.toolSelectionHandler = ^(KayokoFingerTool tool) { [weakSelf selectToolValue:tool]; };
    self.controls.colorSelectionHandler = ^(NSInteger index) { [weakSelf selectColorIndex:index]; };
    [self.controls setStrokeWidth:8];
    [self.controls setSelectedColorIndex:1];
    [self.controls.cancelButton addTarget:self action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];
    [self.controls.doneButton addTarget:self action:@selector(save) forControlEvents:UIControlEventTouchUpInside];
    [self.controls.resetButton addTarget:self action:@selector(resetImage) forControlEvents:UIControlEventTouchUpInside];
    [self.controls.undoButton addTarget:self action:@selector(undo) forControlEvents:UIControlEventTouchUpInside];
    [self.controls.exportButton addTarget:self action:@selector(exportImage) forControlEvents:UIControlEventTouchUpInside];
    [self.controls.copyButton addTarget:self action:@selector(copyImage) forControlEvents:UIControlEventTouchUpInside];
    [self.controls.recognizeButton addTarget:self action:@selector(recognizeText) forControlEvents:UIControlEventTouchUpInside];
    [self.controls.importOverlayButton addTarget:self action:@selector(chooseSticker) forControlEvents:UIControlEventTouchUpInside];
    [self.controls.widthSlider addTarget:self action:@selector(widthChanged) forControlEvents:UIControlEventValueChanged];
    self.controls.undoButton.accessibilityHint = KayokoFingerString(@"Touch and hold to redo.");
    [self.view addSubview:self.controls];

    self.lockButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.lockButton.accessibilityIdentifier = @"finger.lock";
    self.lockButton.backgroundColor = UIColor.systemBackgroundColor;
    self.lockButton.tintColor = UIColor.labelColor;
    self.lockButton.layer.cornerRadius = 22;
    self.lockButton.layer.shadowColor = UIColor.blackColor.CGColor;
    self.lockButton.layer.shadowOpacity = 0.13;
    self.lockButton.layer.shadowRadius = 5;
    self.lockButton.layer.shadowOffset = CGSizeMake(0, 2);
    [self.lockButton addTarget:self action:@selector(toggleMove) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.lockButton];
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];
    [self updateToolAppearance];
    [self loadImage];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect safe = UIEdgeInsetsInsetRect(self.view.bounds, self.view.safeAreaInsets);
    CGRect content = CGRectInset(safe, 12, 8);
    BOOL landscape = content.size.width > content.size.height && content.size.width >= 600;
    [self.controls setCompactLayout:landscape];
    if (landscape) {
        CGFloat dockWidth = MIN(350, floor(content.size.width * 0.48));
        self.controls.frame = CGRectMake(CGRectGetMaxX(content) - dockWidth, content.origin.y,
                                         dockWidth, content.size.height);
        self.canvas.frame = CGRectMake(content.origin.x, content.origin.y,
                                       content.size.width - dockWidth - 10, content.size.height);
    } else {
        CGFloat height = MIN(self.controls.preferredHeight, MAX(220, content.size.height - 140));
        self.controls.frame = CGRectMake(content.origin.x, CGRectGetMaxY(content) - height, content.size.width, height);
        self.canvas.frame = CGRectMake(content.origin.x, content.origin.y, content.size.width,
                                       MAX(0, content.size.height - height - 10));
    }
    self.lockButton.frame = CGRectMake(CGRectGetMaxX(self.canvas.frame) - 54, CGRectGetMaxY(self.canvas.frame) - 54, 44, 44);
    self.spinner.center = self.canvas.center;
    self.canvas.layer.borderColor = [UIColor.separatorColor colorWithAlphaComponent:0.4].CGColor;
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? UIStatusBarStyleLightContent : UIStatusBarStyleDarkContent;
}

- (NSURL *)newSnapshotURL {
    return [self.directoryURL URLByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"png"]];
}

- (void)loadImage {
    [self setProcessing:YES];
    dispatch_async(self.processingQueue, ^{
        @autoreleasepool {
            UIImage *image = [KayokoFingerImageRenderer preparedImageAtURL:self.inputURL];
            NSURL *URL = [self newSnapshotURL];
            NSError *error = nil;
            BOOL created = [[NSFileManager defaultManager] createDirectoryAtURL:self.directoryURL
                withIntermediateDirectories:YES attributes:nil error:&error];
            NSData *data = image ? UIImagePNGRepresentation(image) : nil;
            BOOL written = created && data.length && [data writeToURL:URL options:NSDataWritingAtomic error:&error];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.invalidated) return;
                [self setProcessing:NO];
                if (!written) {
                    [self showError:KayokoFingerError(@"Unable to Open Image")];
                    return;
                }
                [self.snapshots addObject:URL];
                self.originalSnapshotURL = URL;
                [self setStatusText:@"Image Ready"];
                self.canvas.image = image;
                [self updateControls];
            });
        }
    });
}

- (void)setStatusText:(NSString *)key {
    self.controls.statusLabel.text = KayokoFingerString(key);
    [self.controls setNeedsLayout];
}

- (void)setProcessing:(BOOL)processing {
    self.busy = processing;
    processing ? [self.spinner startAnimating] : [self.spinner stopAnimating];
    [self updateControls];
}

- (void)updateControls {
    BOOL ready = !self.busy && !self.invalidated && self.snapshots.count > 0;
    self.canvas.userInteractionEnabled = ready;
    self.controls.userInteractionEnabled = !self.busy && !self.invalidated;
    self.controls.alpha = self.busy ? 0.55 : 1;
    self.controls.widthSlider.enabled = ready;
    self.controls.doneButton.enabled = ready;
    self.controls.cancelButton.enabled = !self.busy && !self.invalidated;
    self.controls.resetButton.enabled = ready && ![self.snapshots[self.snapshotIndex] isEqual:self.originalSnapshotURL];
    self.controls.exportButton.enabled = ready;
    self.controls.copyButton.enabled = ready;
    BOOL canUndo = ready && self.snapshotIndex > 0;
    BOOL canRedo = ready && self.snapshotIndex + 1 < self.snapshots.count;
    self.controls.undoButton.enabled = canUndo || canRedo;
    self.controls.undoButton.showsMenuAsPrimaryAction = !canUndo && canRedo;
    __weak typeof(self) weakSelf = self;
    UIAction *redo = [UIAction actionWithTitle:KayokoFingerString(@"Redo") image:[UIImage systemImageNamed:@"arrow.uturn.forward"]
        identifier:nil handler:^(__unused UIAction *action) { [weakSelf redo]; }];
    redo.attributes = canRedo ? 0 : UIMenuElementAttributesDisabled;
    self.controls.undoButton.menu = [UIMenu menuWithChildren:@[redo]];
    self.controls.recognizeButton.enabled = ready;
    self.controls.importOverlayButton.enabled = ready;
    self.lockButton.enabled = ready && self.selectedMode != 2;
}

- (void)updateToolAppearance {
    [self.controls setSelectedMode:self.selectedMode tool:self.canvas.tool];
    BOOL navigation = self.imageNavigationUnlocked || self.selectedMode == 2;
    self.canvas.navigationMode = navigation;
    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:19 weight:UIImageSymbolWeightSemibold];
    [self.lockButton setImage:[UIImage systemImageNamed:navigation ? @"lock.open.fill" : @"lock.fill" withConfiguration:configuration]
                     forState:UIControlStateNormal];
    self.lockButton.accessibilityLabel = KayokoFingerString(navigation ? @"Lock Image" : @"Unlock Image");
    self.lockButton.accessibilityHint = KayokoFingerString(@"Unlock to move and zoom; lock to draw.");
    NSString *hint = @"Draw on the image with one finger.";
    if (navigation) hint = @"Move or zoom the image, then tap the lock to edit.";
    if (self.selectedMode == 2) hint = @"Recognize text in the current image.";
    else if (!navigation && self.canvas.tool == kKayokoFingerToolText) hint = @"Tap the image to add text.";
    else if (!navigation && self.canvas.tool == kKayokoFingerToolCrop) hint = @"Drag a rectangle to crop. Undo restores the previous image.";
    else if (!navigation && (self.canvas.tool == kKayokoFingerToolCover || self.canvas.tool == kKayokoFingerToolPixelate ||
                            self.canvas.tool == kKayokoFingerToolSticker)) hint = @"Drag a rectangle over the area to cover.";
    self.controls.hintLabel.text = KayokoFingerString(hint);
    [self updateControls];
}

- (void)selectMode:(NSInteger)mode {
    if (self.busy || self.invalidated || mode < 0 || mode > 3) return;
    self.selectedMode = mode;
    if (mode == 0) self.canvas.tool = self.annotationTool;
    else if (mode == 1) self.canvas.tool = self.maskTool;
    else if (mode == 3) self.canvas.tool = kKayokoFingerToolCrop;
    [self updateToolAppearance];
}

- (void)selectToolValue:(KayokoFingerTool)tool {
    if (self.busy || self.invalidated) return;
    self.canvas.tool = tool;
    self.imageNavigationUnlocked = NO;
    if (self.selectedMode == 0) self.annotationTool = tool;
    else if (self.selectedMode == 1) self.maskTool = tool;
    [self updateToolAppearance];
}

- (void)selectColorIndex:(NSInteger)index {
    NSArray<UIColor *> *colors = @[UIColor.blackColor, UIColor.systemRedColor, UIColor.systemYellowColor,
                                  UIColor.systemBlueColor, UIColor.systemGreenColor, UIColor.whiteColor];
    if (self.busy || self.invalidated || index < 0 || index >= (NSInteger)colors.count) return;
    self.canvas.strokeColor = colors[index];
    [self.controls setSelectedColorIndex:index];
}

- (void)widthChanged {
    self.canvas.strokeWidth = self.controls.widthSlider.value;
    [self.controls setStrokeWidth:self.canvas.strokeWidth];
}

- (void)toggleMove {
    if (self.busy || self.invalidated || self.selectedMode == 2) return;
    self.imageNavigationUnlocked = !self.imageNavigationUnlocked;
    [self updateToolAppearance];
}

- (void)resetImage {
    if (self.busy || self.invalidated || !self.originalSnapshotURL) return;
    [self setProcessing:YES];
    dispatch_async(self.processingQueue, ^{
        @autoreleasepool {
            UIImage *image = [KayokoFingerImageRenderer preparedImageAtURL:self.originalSnapshotURL];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.invalidated) return;
                [self setProcessing:NO];
                if (!image) { [self showError:KayokoFingerError(@"Unable to Open Image")]; return; }
                [self appendSnapshotURL:self.originalSnapshotURL image:image];
                [self.canvas resetZoom];
                [self setStatusText:@"Image Reset"];
                [self updateControls];
            });
        }
    });
}

- (void)copyImage {
    if (self.busy || self.invalidated || !self.snapshots.count) return;
    NSURL *URL = self.snapshots[self.snapshotIndex];
    [self setProcessing:YES];
    dispatch_async(self.processingQueue, ^{
        NSData *data = [NSData dataWithContentsOfURL:URL];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.invalidated) return;
            [self setProcessing:NO];
            if (!data.length) { [self showError:KayokoFingerError(@"Unable to Open Image")]; return; }
            [UIPasteboard.generalPasteboard setData:data forPasteboardType:@"public.png"];
            [self setStatusText:@"Image Copied"];
        });
    });
}

- (void)exportImage {
    if (self.busy || self.invalidated || !self.canvas.image || self.presentedViewController) return;
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[self.canvas.image] applicationActivities:nil];
    activity.popoverPresentationController.sourceView = self.controls.exportButton;
    activity.popoverPresentationController.sourceRect = self.controls.exportButton.bounds;
    [self presentViewController:activity animated:YES completion:nil];
}

- (void)applyOperation:(KayokoFingerEditOperation *)operation {
    if (self.busy || self.invalidated || !self.canvas.image) return;
    KayokoFingerEditOperation *edit = [operation copy];
    if (edit.tool == kKayokoFingerToolSticker) {
        if (!self.stickerImage) { [self chooseSticker]; return; }
        edit.stickerImage = self.stickerImage;
    }
    UIImage *input = self.canvas.image;
    [self setProcessing:YES];
    dispatch_async(self.processingQueue, ^{
        @autoreleasepool {
            UIImage *result = [KayokoFingerImageRenderer image:input byApplyingOperation:edit];
            NSURL *URL = [self newSnapshotURL];
            NSData *data = result ? UIImagePNGRepresentation(result) : nil;
            BOOL written = data.length && [data writeToURL:URL options:NSDataWritingAtomic error:nil];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.invalidated) return;
                [self setProcessing:NO];
                if (!written) { [self showError:KayokoFingerError(@"Unable to Apply Edit")]; return; }
                [self appendSnapshotURL:URL image:result];
                [self setStatusText:@"Image Edited"];
                [self updateControls];
            });
        }
    });
}

- (void)removeSnapshotFileIfUnused:(NSURL *)URL {
    if (![URL isEqual:self.originalSnapshotURL] && ![self.snapshots containsObject:URL]) {
        [[NSFileManager defaultManager] removeItemAtURL:URL error:nil];
    }
}

- (void)appendSnapshotURL:(NSURL *)URL image:(UIImage *)image {
    while (self.snapshots.count > self.snapshotIndex + 1) {
        NSURL *discarded = self.snapshots.lastObject;
        [self.snapshots removeLastObject];
        [self removeSnapshotFileIfUnused:discarded];
    }
    [self.snapshots addObject:URL];
    // Keep Reset reversible without deleting the immutable session original,
    // even when it appears in more than one undo/redo slot.
    if (self.snapshots.count > 13) {
        NSURL *discarded = self.snapshots.firstObject;
        [self.snapshots removeObjectAtIndex:0];
        [self removeSnapshotFileIfUnused:discarded];
    }
    self.snapshotIndex = self.snapshots.count - 1;
    self.canvas.image = image;
}

- (void)undo { if (self.snapshotIndex > 0) [self loadSnapshot:self.snapshotIndex - 1]; }
- (void)redo { if (self.snapshotIndex + 1 < self.snapshots.count) [self loadSnapshot:self.snapshotIndex + 1]; }
- (void)loadSnapshot:(NSUInteger)index {
    if (self.busy || self.invalidated || index >= self.snapshots.count) return;
    NSURL *URL = self.snapshots[index];
    [self setProcessing:YES];
    dispatch_async(self.processingQueue, ^{
        @autoreleasepool {
            UIImage *image = [KayokoFingerImageRenderer preparedImageAtURL:URL];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.invalidated) return;
                [self setProcessing:NO];
                if (!image) { [self showError:KayokoFingerError(@"Unable to Open Image")]; return; }
                self.snapshotIndex = index;
                [self setStatusText:@"Image Ready"];
                self.canvas.image = image;
                [self updateControls];
            });
        }
    });
}

- (void)requestTextAtPoint:(CGPoint)point {
    if (self.busy || self.invalidated || self.presentedViewController) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:KayokoFingerString(@"Add Text")
        message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = KayokoFingerString(@"Text"); }];
    __weak typeof(self) weakSelf = self;
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:KayokoFingerString(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:KayokoFingerString(@"Add") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        KayokoFingerEditorViewController *strongSelf = weakSelf;
        NSString *text = [weakAlert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!text.length || !strongSelf || strongSelf.invalidated) return;
        KayokoFingerEditOperation *operation = [[KayokoFingerEditOperation alloc] init];
        operation.tool = kKayokoFingerToolText;
        operation.points = @[[NSValue valueWithCGPoint:point]];
        operation.text = text;
        operation.color = strongSelf.canvas.strokeColor;
        // Ask the canvas for the same pixel width used by drawn operations.
        operation.lineWidth = strongSelf.canvas.imageLineWidth;
        [strongSelf applyOperation:operation];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)chooseSticker {
    if (self.presentedViewController || self.busy || self.invalidated) return;
    PHPickerConfiguration *configuration = [[PHPickerConfiguration alloc] init];
    configuration.filter = PHPickerFilter.imagesFilter;
    configuration.selectionLimit = 1;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:^{
        if (self.invalidated || !results.count) return;
        [self setProcessing:YES];
        NSItemProvider *provider = results.firstObject.itemProvider;
        // File representation avoids fully decoding a large photograph in SpringBoard.
        [provider loadFileRepresentationForTypeIdentifier:@"public.image" completionHandler:^(NSURL *URL, NSError *error) {
            NSURL *copyURL = [self.directoryURL URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
            BOOL copied = URL && [[NSFileManager defaultManager] copyItemAtURL:URL toURL:copyURL error:nil];
            dispatch_async(self.processingQueue, ^{
                @autoreleasepool {
                    UIImage *image = copied ? [KayokoFingerImageRenderer preparedImageAtURL:copyURL] : nil;
                    [[NSFileManager defaultManager] removeItemAtURL:copyURL error:nil];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (self.invalidated) return;
                        [self setProcessing:NO];
                        if (image) {
                            self.stickerImage = image;
                            [self setStatusText:@"Overlay Ready"];
                        }
                        else [self showError:error ?: KayokoFingerError(@"Unable to Open Image")];
                    });
                }
            });
        }];
    }];
}

- (void)recognizeText {
    if (self.busy || self.invalidated || !self.snapshots.count) return;
    [self setProcessing:YES];
    [[KayokoImageTextRecognizer sharedRecognizer] recognizeTextInImageAtPath:self.snapshots[self.snapshotIndex].path
        completion:^(NSString *text) {
            if (self.invalidated) return;
            [self setProcessing:NO];
            if (!text.length) { [self showError:KayokoFingerError(@"No Text Recognized")]; return; }
            [self presentRecognizedText:text];
        }];
}

- (void)presentRecognizedText:(NSString *)text {
    UIViewController *result = [[UIViewController alloc] init];
    result.view.backgroundColor = self.view.backgroundColor;
    UILabel *title = [[UILabel alloc] init];
    title.text = KayokoFingerString(@"Recognized Text");
    title.font = [UIFont boldSystemFontOfSize:20];
    title.textAlignment = NSTextAlignmentCenter;
    UITextView *textView = [[UITextView alloc] init];
    textView.text = text;
    textView.editable = NO;
    textView.selectable = YES;
    textView.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    textView.backgroundColor = UIColor.clearColor;
    textView.textContainerInset = UIEdgeInsetsMake(16, 16, 16, 16);
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButton *copy = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setTitle:KayokoFingerString(@"Done") forState:UIControlStateNormal];
    [copy setTitle:KayokoFingerString(@"Copy All") forState:UIControlStateNormal];
    __weak typeof(self) weakSelf = self;
    [close addAction:[UIAction actionWithHandler:^(__unused UIAction *action) {
        [weakSelf dismissViewControllerAnimated:YES completion:nil];
    }] forControlEvents:UIControlEventTouchUpInside];
    [copy addAction:[UIAction actionWithHandler:^(__unused UIAction *action) {
        UIPasteboard.generalPasteboard.string = text;
        [weakSelf dismissViewControllerAnimated:YES completion:nil];
    }] forControlEvents:UIControlEventTouchUpInside];
    UIStackView *footer = [[UIStackView alloc] initWithArrangedSubviews:@[close, copy]];
    footer.distribution = UIStackViewDistributionFillEqually;
    footer.tintColor = UIColor.labelColor;
    for (UIView *view in @[title, textView, footer]) {
        view.translatesAutoresizingMaskIntoConstraints = NO;
        [result.view addSubview:view];
    }
    UILayoutGuide *safe = result.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:safe.topAnchor constant:12],
        [title.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],
        [textView.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:8],
        [textView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [textView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [textView.bottomAnchor constraintEqualToAnchor:footer.topAnchor constant:-8],
        [footer.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:12],
        [footer.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-12],
        [footer.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-8],
        [footer.heightAnchor constraintEqualToConstant:48]
    ]];
    [self presentViewController:result animated:YES completion:nil];
}

- (void)showError:(NSError *)error {
    if (self.invalidated || self.presentedViewController) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:KayokoFingerString(@"FingerEditor")
        message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:KayokoFingerString(@"OK") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)save {
    if (self.busy || self.invalidated || !self.snapshots.count) return;
    if ([self.snapshots[self.snapshotIndex] isEqual:self.originalSnapshotURL]) { [self finish:NO]; return; }
    self.saving = YES;
    [self setProcessing:YES];
    self.saveHandler(self.snapshots[self.snapshotIndex], ^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.saving = NO;
            if (self.invalidated) return;
            [self setProcessing:NO];
            if (error) [self showError:error];
            else [self finish:YES];
        });
    });
}

- (void)cancel {
    if (self.busy || self.invalidated) return;
    if (!self.snapshots.count || [self.snapshots[self.snapshotIndex] isEqual:self.originalSnapshotURL]) {
        [self finish:NO]; return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:KayokoFingerString(@"Discard Edits?")
        message:KayokoFingerString(@"The original clipboard image will remain unchanged.") preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:KayokoFingerString(@"Keep Editing") style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:KayokoFingerString(@"Discard") style:UIAlertActionStyleDestructive
        handler:^(__unused UIAlertAction *action) { [weakSelf finish:NO]; }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)finish:(BOOL)saved {
    void (^completion)(BOOL) = self.didFinish;
    self.didFinish = nil;
    if (completion && !self.invalidated) completion(saved);
}

- (void)invalidate {
    self.invalidated = YES;
    self.didFinish = nil;
    self.saveHandler = nil;
    self.canvas.operationHandler = nil;
    self.canvas.textPositionHandler = nil;
    self.canvas.userInteractionEnabled = NO;
    self.controls.userInteractionEnabled = NO;
    self.lockButton.enabled = NO;
}

@end
