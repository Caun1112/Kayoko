#import "KayokoFingerEditorViewController.h"
#import "KayokoFingerCanvasView.h"
#import "KayokoFingerImageRenderer.h"
#import "KayokoImageTextRecognizer.h"
#import "KayokoPasteboardManager.h"
#import <PhotosUI/PhotosUI.h>

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
@property(nonatomic, strong) UIStackView *toolStack;
@property(nonatomic, strong) UIStackView *colorStack;
@property(nonatomic, strong) UIStackView *commandStack;
@property(nonatomic, strong) UISlider *widthSlider;
@property(nonatomic, strong) UILabel *hintLabel;
@property(nonatomic, strong) UIButton *cancelButton;
@property(nonatomic, strong) UIButton *doneButton;
@property(nonatomic, strong) UIButton *undoButton;
@property(nonatomic, strong) UIButton *redoButton;
@property(nonatomic, strong) UIButton *moveButton;
@property(nonatomic, strong) UIButton *ocrButton;
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
    }
    return self;
}

- (void)dealloc {
    [[NSFileManager defaultManager] removeItemAtURL:_directoryURL error:nil];
}

- (UIButton *)buttonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:KayokoFingerString(title) forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    button.contentEdgeInsets = UIEdgeInsetsMake(8, 10, 8, 10);
    button.layer.cornerRadius = 8;
    [button.heightAnchor constraintEqualToConstant:44].active = YES;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (UIScrollView *)scrollViewForStack:(UIStackView *)stack {
    UIScrollView *scrollView = [[UIScrollView alloc] init];
    scrollView.showsHorizontalScrollIndicator = NO;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scrollView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.leadingAnchor constant:8],
        [stack.trailingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.trailingAnchor constant:-8],
        [stack.topAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.bottomAnchor],
        [stack.heightAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.heightAnchor]
    ]];
    return scrollView;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.view.tintColor = UIColor.systemBlueColor;
    self.canvas = [[KayokoFingerCanvasView alloc] initWithFrame:CGRectZero];
    self.canvas.tool = kKayokoFingerToolArrow;
    self.canvas.strokeColor = UIColor.systemRedColor;
    self.canvas.strokeWidth = 5;
    __weak typeof(self) weakSelf = self;
    self.canvas.operationHandler = ^(KayokoFingerEditOperation *operation) {
        [weakSelf applyOperation:operation];
    };
    self.canvas.textPositionHandler = ^(CGPoint point) { [weakSelf requestTextAtPoint:point]; };

    self.cancelButton = [self buttonWithTitle:@"Cancel" action:@selector(cancel)];
    self.doneButton = [self buttonWithTitle:@"Done" action:@selector(save)];
    self.doneButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    UILabel *title = [[UILabel alloc] init];
    title.text = @"FingerEditor";
    title.font = [UIFont boldSystemFontOfSize:17];
    title.textAlignment = NSTextAlignmentCenter;
    [title setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:@[self.cancelButton, title, self.doneButton]];
    header.alignment = UIStackViewAlignmentCenter;
    self.undoButton = [self buttonWithTitle:@"Undo" action:@selector(undo)];
    self.redoButton = [self buttonWithTitle:@"Redo" action:@selector(redo)];
    self.moveButton = [self buttonWithTitle:@"Move Image" action:@selector(toggleMove)];
    self.ocrButton = [self buttonWithTitle:@"Recognize Text" action:@selector(recognizeText)];
    self.commandStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.undoButton, self.redoButton, self.moveButton, self.ocrButton]];
    UIScrollView *commands = [self scrollViewForStack:self.commandStack];

    self.toolStack = [[UIStackView alloc] init];
    self.toolStack.spacing = 4;
    NSArray *tools = @[@[@(kKayokoFingerToolArrow), @"Arrow"], @[@(kKayokoFingerToolRectangle), @"Rectangle"],
        @[@(kKayokoFingerToolEllipse), @"Ellipse"], @[@(kKayokoFingerToolText), @"Text"],
        @[@(kKayokoFingerToolPen), @"Pen"], @[@(kKayokoFingerToolMosaic), @"Fine Mosaic"],
        @[@(kKayokoFingerToolCoarseMosaic), @"Coarse Mosaic"], @[@(kKayokoFingerToolBlur), @"Blur"],
        @[@(kKayokoFingerToolCover), @"Solid Cover"], @[@(kKayokoFingerToolPixelate), @"Mosaic Cover"],
        @[@(kKayokoFingerToolCrop), @"Crop"], @[@(kKayokoFingerToolSticker), @"Image Overlay"]];
    for (NSArray *entry in tools) {
        UIButton *button = [self buttonWithTitle:entry[1] action:@selector(selectTool:)];
        button.tag = [entry[0] integerValue];
        [self.toolStack addArrangedSubview:button];
    }
    UIScrollView *toolsScroll = [self scrollViewForStack:self.toolStack];
    self.colorStack = [[UIStackView alloc] init];
    self.colorStack.spacing = 2;
    NSArray *colors = @[UIColor.blackColor, UIColor.systemRedColor, UIColor.systemYellowColor,
                        UIColor.systemBlueColor, UIColor.systemGreenColor, UIColor.whiteColor];
    NSArray *colorNames = @[@"Black", @"Red", @"Yellow", @"Blue", @"Green", @"White"];
    for (NSUInteger i = 0; i < colors.count; i++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.backgroundColor = colors[i];
        button.tag = i;
        button.layer.cornerRadius = 18;
        button.layer.borderColor = UIColor.systemGrayColor.CGColor;
        button.layer.borderWidth = 1;
        button.accessibilityLabel = KayokoFingerString(colorNames[i]);
        [button.widthAnchor constraintEqualToConstant:36].active = YES;
        [button.heightAnchor constraintEqualToConstant:36].active = YES;
        [button setTitle:i == 1 ? @"✓" : @"" forState:UIControlStateNormal];
        [button setTitleColor:(i == 2 || i == 5) ? UIColor.blackColor : UIColor.whiteColor forState:UIControlStateNormal];
        [button addTarget:self action:@selector(selectColor:) forControlEvents:UIControlEventTouchUpInside];
        [self.colorStack addArrangedSubview:button];
    }
    self.colorStack.alignment = UIStackViewAlignmentCenter;
    self.widthSlider = [[UISlider alloc] init];
    self.widthSlider.minimumValue = 2;
    self.widthSlider.maximumValue = 40;
    self.widthSlider.value = 5;
    self.widthSlider.accessibilityLabel = KayokoFingerString(@"Stroke Width");
    [self.widthSlider addTarget:self action:@selector(widthChanged) forControlEvents:UIControlEventValueChanged];
    UIStackView *options = [[UIStackView alloc] initWithArrangedSubviews:@[self.colorStack, self.widthSlider]];
    options.spacing = 12;
    options.alignment = UIStackViewAlignmentCenter;
    self.hintLabel = [[UILabel alloc] init];
    self.hintLabel.font = [UIFont systemFontOfSize:12];
    self.hintLabel.textColor = UIColor.secondaryLabelColor;
    self.hintLabel.textAlignment = NSTextAlignmentCenter;
    self.hintLabel.numberOfLines = 2;
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.spinner.hidesWhenStopped = YES;

    for (UIView *view in @[header, commands, self.canvas, toolsScroll, options, self.hintLabel, self.spinner]) {
        view.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:view];
    }
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [header.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:8],
        [header.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-8],
        [header.heightAnchor constraintEqualToConstant:48],
        [commands.topAnchor constraintEqualToAnchor:header.bottomAnchor],
        [commands.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [commands.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [commands.heightAnchor constraintEqualToConstant:44],
        [self.canvas.topAnchor constraintEqualToAnchor:commands.bottomAnchor constant:4],
        [self.canvas.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [self.canvas.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [self.canvas.bottomAnchor constraintEqualToAnchor:toolsScroll.topAnchor constant:-4],
        [toolsScroll.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [toolsScroll.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [toolsScroll.heightAnchor constraintEqualToConstant:44],
        [toolsScroll.bottomAnchor constraintEqualToAnchor:options.topAnchor constant:-4],
        [options.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:12],
        [options.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-12],
        [options.heightAnchor constraintEqualToConstant:44],
        [options.bottomAnchor constraintEqualToAnchor:self.hintLabel.topAnchor constant:-4],
        [self.hintLabel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:12],
        [self.hintLabel.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-12],
        [self.hintLabel.heightAnchor constraintEqualToConstant:34],
        [self.hintLabel.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-4],
        [self.spinner.centerXAnchor constraintEqualToAnchor:self.canvas.centerXAnchor],
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.canvas.centerYAnchor]
    ]];
    [self updateToolAppearance];
    [self loadImage];
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
                self.canvas.image = image;
                [self updateControls];
            });
        }
    });
}

- (void)setProcessing:(BOOL)processing {
    self.busy = processing;
    processing ? [self.spinner startAnimating] : [self.spinner stopAnimating];
    [self updateControls];
}

- (void)updateControls {
    BOOL ready = !self.busy && !self.invalidated && self.snapshots.count > 0;
    self.canvas.userInteractionEnabled = ready;
    self.toolStack.userInteractionEnabled = ready;
    self.colorStack.userInteractionEnabled = ready;
    self.widthSlider.enabled = ready;
    self.doneButton.enabled = ready;
    self.cancelButton.enabled = !self.busy;
    self.undoButton.enabled = ready && self.snapshotIndex > 0;
    self.redoButton.enabled = ready && self.snapshotIndex + 1 < self.snapshots.count;
    self.ocrButton.enabled = ready;
    self.moveButton.enabled = ready;
}

- (void)updateToolAppearance {
    for (UIButton *button in self.toolStack.arrangedSubviews) {
        BOOL selected = !self.canvas.navigationMode && button.tag == self.canvas.tool;
        button.backgroundColor = selected ? [UIColor.systemBlueColor colorWithAlphaComponent:0.15] : UIColor.clearColor;
        button.accessibilityTraits = UIAccessibilityTraitButton | (selected ? UIAccessibilityTraitSelected : 0);
    }
    self.moveButton.backgroundColor = self.canvas.navigationMode ?
        [UIColor.systemBlueColor colorWithAlphaComponent:0.15] : UIColor.clearColor;
    NSString *hint = @"Draw with one finger. Pinch to zoom or drag with two fingers to move.";
    if (self.canvas.navigationMode) hint = @"Drag to move the image. Select a tool to continue editing.";
    else if (self.canvas.tool == kKayokoFingerToolText) hint = @"Tap the image to add text.";
    else if (self.canvas.tool == kKayokoFingerToolCrop) hint = @"Drag a rectangle to crop. Undo restores the previous image.";
    else if (self.canvas.tool == kKayokoFingerToolCover || self.canvas.tool == kKayokoFingerToolPixelate ||
             self.canvas.tool == kKayokoFingerToolSticker) hint = @"Drag a rectangle over the area to cover.";
    self.hintLabel.text = KayokoFingerString(hint);
}

- (void)selectTool:(UIButton *)sender {
    if (self.busy) return;
    self.canvas.tool = sender.tag;
    self.canvas.navigationMode = NO;
    if (sender.tag == kKayokoFingerToolMosaic || sender.tag == kKayokoFingerToolCoarseMosaic || sender.tag == kKayokoFingerToolBlur) {
        if (self.widthSlider.value < 16) self.widthSlider.value = 24;
    } else if (self.widthSlider.value > 16) {
        self.widthSlider.value = 5;
    }
    [self widthChanged];
    [self updateToolAppearance];
    if (sender.tag == kKayokoFingerToolSticker) [self chooseSticker];
}

- (void)selectColor:(UIButton *)sender {
    self.canvas.strokeColor = sender.backgroundColor;
    for (UIButton *button in self.colorStack.arrangedSubviews) {
        [button setTitle:button == sender ? @"✓" : @"" forState:UIControlStateNormal];
        button.accessibilityTraits = UIAccessibilityTraitButton | (button == sender ? UIAccessibilityTraitSelected : 0);
    }
}

- (void)widthChanged { self.canvas.strokeWidth = self.widthSlider.value; }
- (void)toggleMove {
    self.canvas.navigationMode = !self.canvas.navigationMode;
    [self updateToolAppearance];
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
                while (self.snapshots.count > self.snapshotIndex + 1) {
                    [[NSFileManager defaultManager] removeItemAtURL:self.snapshots.lastObject error:nil];
                    [self.snapshots removeLastObject];
                }
                [self.snapshots addObject:URL];
                // Undo images live on disk; retain only the current decoded bitmap.
                if (self.snapshots.count > 13) {
                    [[NSFileManager defaultManager] removeItemAtURL:self.snapshots.firstObject error:nil];
                    [self.snapshots removeObjectAtIndex:0];
                }
                self.snapshotIndex = self.snapshots.count - 1;
                self.canvas.image = result;
                [self updateControls];
            });
        }
    });
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
                        if (image) self.stickerImage = image;
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
            UIViewController *result = [[UIViewController alloc] init];
            result.title = KayokoFingerString(@"Recognized Text");
            result.view.backgroundColor = UIColor.systemBackgroundColor;
            UITextView *textView = [[UITextView alloc] init];
            textView.text = text;
            textView.editable = NO;
            textView.selectable = YES;
            textView.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
            textView.textContainerInset = UIEdgeInsetsMake(16, 16, 16, 16);
            textView.translatesAutoresizingMaskIntoConstraints = NO;
            [result.view addSubview:textView];
            UILayoutGuide *safe = result.view.safeAreaLayoutGuide;
            [NSLayoutConstraint activateConstraints:@[
                [textView.topAnchor constraintEqualToAnchor:safe.topAnchor],
                [textView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
                [textView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
                [textView.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor]
            ]];
            __weak typeof(self) weakSelf = self;
            result.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithPrimaryAction:
                [UIAction actionWithTitle:KayokoFingerString(@"Done") image:nil identifier:nil handler:^(__unused UIAction *action) {
                    [weakSelf dismissViewControllerAnimated:YES completion:nil];
                }]];
            result.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithPrimaryAction:
                [UIAction actionWithTitle:KayokoFingerString(@"Copy All") image:nil identifier:nil handler:^(__unused UIAction *action) {
                    UIPasteboard.generalPasteboard.string = text;
                    [weakSelf dismissViewControllerAnimated:YES completion:nil];
                }]];
            UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:result];
            [self presentViewController:navigation animated:YES completion:nil];
        }];
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
}

@end
