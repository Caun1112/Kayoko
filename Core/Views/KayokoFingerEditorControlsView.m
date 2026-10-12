#import "KayokoFingerEditorControlsView.h"
#import "KayokoPasteboardManager.h"

static NSString *KayokoFingerControlString(NSString *key) {
    return [[KayokoPasteboardManager localizationBundle] localizedStringForKey:key value:key table:@"Tweak"];
}

static UIColor *KayokoFingerPanelColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark ?
            [UIColor colorWithWhite:0.13 alpha:1] :
            [UIColor colorWithRed:0.955 green:0.958 blue:0.948 alpha:1];
    }];
}

/// Keep the native segmented appearance while extending its touch area to 44 pt.
@interface KayokoFingerSegmentedControl : UISegmentedControl
@end
@implementation KayokoFingerSegmentedControl
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    CGFloat expansion = MAX(0, (44 - CGRectGetHeight(self.bounds)) / 2);
    return CGRectContainsPoint(CGRectInset(self.bounds, 0, -expansion), point);
}
@end

/// A 26 pt swatch inside a separate 44 pt accessible button.
@interface KayokoFingerColorButton : UIButton
@property(nonatomic, strong) UIView *swatch;
@property(nonatomic, strong) UIImageView *checkmark;
@end
@implementation KayokoFingerColorButton
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _swatch = [[UIView alloc] init];
        _swatch.userInteractionEnabled = NO;
        _swatch.layer.cornerRadius = 13;
        _swatch.clipsToBounds = YES;
        _swatch.layer.borderWidth = 1;
        [self addSubview:_swatch];
        _checkmark = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark"
            withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightBold]]];
        _checkmark.contentMode = UIViewContentModeCenter;
        [self addSubview:_checkmark];
        self.accessibilityTraits = UIAccessibilityTraitButton;
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect dot = CGRectMake((CGRectGetWidth(self.bounds) - 26) / 2, (CGRectGetHeight(self.bounds) - 26) / 2, 26, 26);
    self.swatch.frame = dot;
    self.checkmark.frame = dot;
    self.swatch.layer.borderColor = [UIColor.labelColor colorWithAlphaComponent:self.tag == 5 ? 0.34 : 0.16].CGColor;
}
- (void)setSelected:(BOOL)selected {
    [super setSelected:selected];
    self.checkmark.hidden = !selected;
    self.accessibilityTraits = UIAccessibilityTraitButton | (selected ? UIAccessibilityTraitSelected : 0);
}
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.alpha = highlighted ? 0.55 : 1;
}
@end

/// An icon above a caption, with a full-height hit region for the bottom dock.
@interface KayokoFingerActionButton : UIButton
@end
@implementation KayokoFingerActionButton
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat top = MAX(0, (CGRectGetHeight(self.bounds) - 42) / 2);
    self.imageView.frame = CGRectMake((width - 23) / 2, top, 23, 23);
    self.imageView.contentMode = UIViewContentModeScaleAspectFit;
    self.titleLabel.frame = CGRectMake(1, top + 26, MAX(0, width - 2), 16);
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
}
- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    self.alpha = enabled ? 1 : 0.3;
}
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.alpha = !self.enabled ? 0.3 : (highlighted ? 0.5 : 1);
}
@end

@interface KayokoFingerEditorControlsView ()
@property(nonatomic, strong, readwrite) UIButton *cancelButton;
@property(nonatomic, strong, readwrite) UIButton *resetButton;
@property(nonatomic, strong, readwrite) UIButton *undoButton;
@property(nonatomic, strong, readwrite) UIButton *exportButton;
@property(nonatomic, strong, readwrite) UIButton *copyButton;
@property(nonatomic, strong, readwrite) UIButton *doneButton;
@property(nonatomic, strong, readwrite) UIButton *recognizeButton;
@property(nonatomic, strong, readwrite) UIButton *importOverlayButton;
@property(nonatomic, strong, readwrite) UISlider *widthSlider;
@property(nonatomic, strong, readwrite) UILabel *hintLabel;
@property(nonatomic, strong, readwrite) UILabel *statusLabel;
@property(nonatomic, copy, readwrite) NSArray<UIButton *> *colorButtons;
@property(nonatomic, strong) UIView *settingsCard;
@property(nonatomic, strong) UIView *modeCard;
@property(nonatomic, strong) UIView *actionCard;
@property(nonatomic, strong) UIScrollView *settingsScrollView;
@property(nonatomic, strong) UIView *settingsContent;
@property(nonatomic, strong) UIScrollView *colorScrollView;
@property(nonatomic, strong) UISegmentedControl *toolControl;
@property(nonatomic, strong) UISegmentedControl *mosaicControl;
@property(nonatomic, strong) UISegmentedControl *maskControl;
@property(nonatomic, strong) UISegmentedControl *modeControl;
@property(nonatomic, strong) UILabel *colorLabel;
@property(nonatomic, strong) UILabel *styleLabel;
@property(nonatomic, strong) UILabel *widthLabel;
@property(nonatomic, strong) UILabel *widthValueLabel;
@property(nonatomic) NSInteger selectedMode;
@property(nonatomic) KayokoFingerTool selectedTool;
@property(nonatomic) KayokoFingerTool mosaicTool;
@property(nonatomic) BOOL compactLayout;
@end

@implementation KayokoFingerEditorControlsView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _selectedTool = kKayokoFingerToolArrow;
        _mosaicTool = kKayokoFingerToolMosaic;
        self.tintColor = UIColor.labelColor;
        self.backgroundColor = UIColor.clearColor;
        _settingsCard = [self makeCard:@"finger.settings"];
        _modeCard = [self makeCard:@"finger.modeCard"];
        _actionCard = [self makeCard:@"finger.actions"];

        _settingsScrollView = [[UIScrollView alloc] init];
        _settingsScrollView.alwaysBounceVertical = NO;
        _settingsScrollView.showsHorizontalScrollIndicator = NO;
        _settingsScrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
        [_settingsCard addSubview:_settingsScrollView];
        _settingsContent = [[UIView alloc] init];
        [_settingsScrollView addSubview:_settingsContent];

        _toolControl = [self segmentedControlWithKeys:@[@"Arrow", @"Rectangle", @"Ellipse", @"Text", @"Pen", @"Mosaic"]
            identifier:@"finger.tool" action:@selector(toolChanged:)];
        _toolControl.apportionsSegmentWidthsByContent = YES;
        _mosaicControl = [self segmentedControlWithKeys:@[@"Fine", @"Coarse", @"Blur"]
            identifier:@"finger.mosaic" action:@selector(mosaicChanged:)];
        _maskControl = [self segmentedControlWithKeys:@[@"Solid", @"Mosaic", @"Image"]
            identifier:@"finger.mask" action:@selector(maskChanged:)];
        _modeControl = [self segmentedControlWithKeys:@[@"Annotate", @"Cover", @"OCR", @"Crop"]
            identifier:@"finger.modes" action:@selector(modeChanged:)];
        _toolControl.accessibilityLabel = KayokoFingerControlString(@"Image Tools");
        _mosaicControl.accessibilityLabel = KayokoFingerControlString(@"Mosaic");
        _maskControl.accessibilityLabel = KayokoFingerControlString(@"Cover");
        [_modeCard addSubview:_modeControl];
        for (UIView *control in @[_toolControl, _mosaicControl, _maskControl]) [_settingsContent addSubview:control];

        _colorLabel = [self rowLabel:@"Color"];
        _styleLabel = [self rowLabel:@"Style"];
        _widthLabel = [self rowLabel:@"Width"];
        _widthValueLabel = [[UILabel alloc] init];
        _widthValueLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular];
        _widthValueLabel.textAlignment = NSTextAlignmentRight;
        _widthValueLabel.textColor = UIColor.secondaryLabelColor;
        [_settingsContent addSubview:_widthValueLabel];
        _colorScrollView = [[UIScrollView alloc] init];
        _colorScrollView.accessibilityIdentifier = @"finger.colors";
        _colorScrollView.alwaysBounceHorizontal = NO;
        _colorScrollView.showsVerticalScrollIndicator = NO;
        _colorScrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
        [_settingsContent addSubview:_colorScrollView];
        NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
        NSArray<UIColor *> *colors = @[UIColor.blackColor, UIColor.systemRedColor, UIColor.systemYellowColor,
            UIColor.systemBlueColor, UIColor.systemGreenColor, UIColor.whiteColor];
        NSArray<NSString *> *colorNames = @[@"Black", @"Red", @"Yellow", @"Blue", @"Green", @"White"];
        for (NSInteger index = 0; index < (NSInteger)colors.count; index++) {
            KayokoFingerColorButton *button = [[KayokoFingerColorButton alloc] initWithFrame:CGRectZero];
            button.tag = index;
            button.swatch.backgroundColor = colors[index];
            button.checkmark.tintColor = index == 2 || index == 5 ? UIColor.blackColor : UIColor.whiteColor;
            button.accessibilityLabel = KayokoFingerControlString(colorNames[index]);
            button.accessibilityIdentifier = [NSString stringWithFormat:@"finger.color.%ld", (long)index];
            [button addTarget:self action:@selector(colorChanged:) forControlEvents:UIControlEventTouchUpInside];
            [_colorScrollView addSubview:button];
            [buttons addObject:button];
        }
        _colorButtons = buttons;

        _widthSlider = [[UISlider alloc] init];
        _widthSlider.minimumValue = 2;
        _widthSlider.maximumValue = 40;
        _widthSlider.minimumTrackTintColor = [UIColor colorWithRed:0.56 green:0.33 blue:0.02 alpha:1];
        _widthSlider.maximumTrackTintColor = UIColor.systemGray4Color;
        _widthSlider.accessibilityLabel = KayokoFingerControlString(@"Stroke Width");
        _widthSlider.accessibilityIdentifier = @"finger.width";
        [_widthSlider addTarget:self action:@selector(widthChanged:) forControlEvents:UIControlEventValueChanged];
        [_settingsContent addSubview:_widthSlider];

        _recognizeButton = [self primaryButton:@"Recognize Text" identifier:@"finger.recognize" symbol:@"text.viewfinder"];
        _importOverlayButton = [self primaryButton:@"Import Overlay Image" identifier:@"finger.import" symbol:@"photo"];
        _hintLabel = [[UILabel alloc] init];
        _hintLabel.font = [UIFont systemFontOfSize:12];
        _hintLabel.textColor = UIColor.secondaryLabelColor;
        _hintLabel.numberOfLines = 2;
        _statusLabel = [[UILabel alloc] init];
        _statusLabel.font = [UIFont systemFontOfSize:12];
        _statusLabel.textColor = UIColor.secondaryLabelColor;
        _statusLabel.textAlignment = NSTextAlignmentRight;
        _statusLabel.numberOfLines = 2;
        [_settingsContent addSubview:_hintLabel];
        [_settingsContent addSubview:_statusLabel];

        _cancelButton = [self actionButton:@"Cancel" symbol:@"xmark" identifier:@"finger.cancel"];
        _resetButton = [self actionButton:@"Reset" symbol:@"arrow.counterclockwise" identifier:@"finger.reset"];
        _undoButton = [self actionButton:@"Undo" symbol:@"arrow.uturn.backward" identifier:@"finger.undo"];
        _exportButton = [self actionButton:@"Export" symbol:@"square.and.arrow.up" identifier:@"finger.export"];
        _copyButton = [self actionButton:@"Copy Image" symbol:@"doc.on.doc" identifier:@"finger.copy"];
        _doneButton = [self actionButton:@"Done" symbol:@"checkmark" identifier:@"finger.done"];
        [self setSelectedColorIndex:1];
        [self setStrokeWidth:8];
        [self setSelectedMode:0 tool:kKayokoFingerToolArrow];
    }
    return self;
}

- (UIView *)makeCard:(NSString *)identifier {
    UIView *card = [[UIView alloc] init];
    card.backgroundColor = KayokoFingerPanelColor();
    card.layer.cornerRadius = 8;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.borderWidth = 0.5;
    card.clipsToBounds = YES;
    card.accessibilityIdentifier = identifier;
    [self addSubview:card];
    return card;
}

- (UISegmentedControl *)segmentedControlWithKeys:(NSArray<NSString *> *)keys
                                    identifier:(NSString *)identifier action:(SEL)action {
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    for (NSString *key in keys) [titles addObject:KayokoFingerControlString(key)];
    UISegmentedControl *control = [[KayokoFingerSegmentedControl alloc] initWithItems:titles];
    control.accessibilityIdentifier = identifier;
    control.selectedSegmentIndex = 0;
    [control setTitleTextAttributes:@{NSFontAttributeName: [UIFont systemFontOfSize:13 weight:UIFontWeightMedium],
        NSForegroundColorAttributeName: UIColor.labelColor} forState:UIControlStateNormal];
    [control setTitleTextAttributes:@{NSFontAttributeName: [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold],
        NSForegroundColorAttributeName: UIColor.labelColor} forState:UIControlStateSelected];
    [control addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    return control;
}

- (UILabel *)rowLabel:(NSString *)key {
    UILabel *label = [[UILabel alloc] init];
    label.text = KayokoFingerControlString(key);
    label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    label.textColor = UIColor.labelColor;
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.75;
    [self.settingsContent addSubview:label];
    return label;
}

- (UIButton *)primaryButton:(NSString *)key identifier:(NSString *)identifier symbol:(NSString *)symbol {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:KayokoFingerControlString(key) forState:UIControlStateNormal];
    [button setImage:[UIImage systemImageNamed:symbol] forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    button.tintColor = UIColor.labelColor;
    button.backgroundColor = UIColor.tertiarySystemFillColor;
    button.layer.cornerRadius = 8;
    button.imageEdgeInsets = UIEdgeInsetsMake(0, -8, 0, 0);
    button.accessibilityIdentifier = identifier;
    [self.settingsContent addSubview:button];
    return button;
}

- (UIButton *)actionButton:(NSString *)key symbol:(NSString *)symbol identifier:(NSString *)identifier {
    UIButton *button = [[KayokoFingerActionButton alloc] initWithFrame:CGRectZero];
    [button setImage:[UIImage systemImageNamed:symbol
        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:19 weight:UIImageSymbolWeightSemibold]]
        forState:UIControlStateNormal];
    [button setTitle:KayokoFingerControlString(key) forState:UIControlStateNormal];
    [button setTitleColor:UIColor.labelColor forState:UIControlStateNormal];
    button.tintColor = UIColor.labelColor;
    button.titleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
    button.titleLabel.adjustsFontSizeToFitWidth = YES;
    button.titleLabel.minimumScaleFactor = 0.7;
    button.accessibilityLabel = KayokoFingerControlString(key);
    button.accessibilityIdentifier = identifier;
    [self.actionCard addSubview:button];
    return button;
}

- (CGFloat)settingsContentHeight {
    if (self.selectedMode == 0) return 190;
    if (self.selectedMode == 1) {
        if (self.selectedTool == kKayokoFingerToolCover) return 142;
        if (self.selectedTool == kKayokoFingerToolSticker) return 150;
        return 100;
    }
    return self.selectedMode == 2 ? 120 : 88;
}

- (CGFloat)preferredHeight {
    return self.compactLayout ? 246 : self.settingsContentHeight + 130;
}

- (CGSize)intrinsicContentSize {
    return CGSizeMake(UIViewNoIntrinsicMetric, self.preferredHeight);
}

- (void)setCompactLayout:(BOOL)compact {
    if (_compactLayout == compact) return;
    _compactLayout = compact;
    [self invalidateIntrinsicContentSize];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat height = CGRectGetHeight(self.bounds);
    CGFloat modeHeight = 48;
    CGFloat actionHeight = 62;
    CGFloat settingsHeight = MAX(0, height - modeHeight - actionHeight - 20);
    self.settingsCard.frame = CGRectMake(0, 0, width, settingsHeight);
    self.modeCard.frame = CGRectMake(0, settingsHeight + 10, width, modeHeight);
    self.actionCard.frame = CGRectMake(0, height - actionHeight, width, actionHeight);
    for (UIView *card in @[self.settingsCard, self.modeCard, self.actionCard]) {
        card.layer.borderColor = [UIColor.separatorColor colorWithAlphaComponent:0.45].CGColor;
    }
    self.settingsScrollView.frame = self.settingsCard.bounds;
    CGFloat contentHeight = MAX(self.settingsContentHeight, settingsHeight);
    self.settingsContent.frame = CGRectMake(0, 0, width, contentHeight);
    self.settingsScrollView.contentSize = CGSizeMake(width, contentHeight);
    self.settingsScrollView.scrollEnabled = contentHeight > settingsHeight;
    self.settingsScrollView.showsVerticalScrollIndicator = self.settingsScrollView.scrollEnabled;
    CGFloat panelWidth = MIN(304, MAX(0, width - 24));
    CGFloat panelX = width - 12 - panelWidth;
    self.toolControl.frame = CGRectMake(panelX, 10, panelWidth, 32);
    self.maskControl.frame = self.toolControl.frame;
    self.colorLabel.frame = CGRectMake(panelX, 50, 32, 44);
    self.styleLabel.frame = self.colorLabel.frame;
    CGFloat colorWidth = 44;
    // On a 320 pt phone, omit the label rather than shrinking the six touch targets.
    BOOL compactPalette = panelWidth < 304;
    self.colorLabel.hidden = self.colorScrollView.hidden || compactPalette;
    CGFloat colorsWidth = MAX(0, panelWidth - (compactPalette ? 0 : 40));
    self.colorScrollView.frame = CGRectMake(panelX + (compactPalette ? 0 : 40), 50, colorsWidth, 44);
    CGFloat colorsContentWidth = MAX(colorsWidth, colorWidth * self.colorButtons.count);
    self.colorScrollView.contentSize = CGSizeMake(colorsContentWidth, 44);
    self.colorScrollView.scrollEnabled = colorsWidth < colorWidth * self.colorButtons.count;
    self.colorScrollView.showsHorizontalScrollIndicator = self.colorScrollView.scrollEnabled;
    CGFloat colorsX = colorsContentWidth - colorWidth * self.colorButtons.count;
    for (NSUInteger index = 0; index < self.colorButtons.count; index++) {
        self.colorButtons[index].frame = CGRectMake(colorsX + colorWidth * index, 0, colorWidth, 44);
    }
    self.mosaicControl.frame = CGRectMake(panelX + 40, 56, MAX(0, panelWidth - 40), 32);
    self.widthLabel.frame = CGRectMake(panelX, 104, 32, 44);
    self.widthSlider.frame = CGRectMake(panelX + 40, 104, MAX(0, panelWidth - 86), 44);
    self.widthValueLabel.frame = CGRectMake(panelX + panelWidth - 38, 104, 38, 44);
    self.recognizeButton.frame = CGRectMake(panelX, 24, panelWidth, 44);
    self.importOverlayButton.frame = CGRectMake(panelX, 56, panelWidth, 44);
    CGFloat statusWidth = self.statusLabel.text.length ? MIN(102, width * 0.32) : 0;
    CGFloat footerY = contentHeight - 36;
    self.hintLabel.frame = CGRectMake(12, footerY, MAX(0, width - 24 - statusWidth - (statusWidth > 0 ? 8 : 0)), 28);
    self.statusLabel.frame = CGRectMake(width - 12 - statusWidth, footerY, statusWidth, 28);
    CGFloat modeWidth = MIN(288, MAX(0, width - 16));
    self.modeControl.frame = CGRectMake(width - 8 - modeWidth, 8, modeWidth, 32);
    NSArray<UIButton *> *actions = @[self.cancelButton, self.resetButton, self.undoButton,
        self.exportButton, self.copyButton, self.doneButton];
    CGFloat actionWidth = MIN(52, MAX(0, (width - 16) / actions.count));
    CGFloat actionX = width - 8 - actionWidth * actions.count;
    for (NSUInteger index = 0; index < actions.count; index++) {
        actions[index].frame = CGRectMake(actionX + index * actionWidth, 4, actionWidth, actionHeight - 8);
    }
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self setNeedsLayout];
    for (UIButton *button in self.colorButtons) [button setNeedsLayout];
}

- (void)setSelectedMode:(NSInteger)mode tool:(KayokoFingerTool)tool {
    BOOL modeChanged = self.selectedMode != mode;
    self.selectedMode = MIN(3, MAX(0, mode));
    self.selectedTool = tool;
    self.modeControl.selectedSegmentIndex = self.selectedMode;
    BOOL mosaic = tool == kKayokoFingerToolMosaic || tool == kKayokoFingerToolCoarseMosaic || tool == kKayokoFingerToolBlur;
    if (mosaic) self.mosaicTool = tool;
    NSArray<NSNumber *> *annotationTools = @[@(kKayokoFingerToolArrow), @(kKayokoFingerToolRectangle),
        @(kKayokoFingerToolEllipse), @(kKayokoFingerToolText), @(kKayokoFingerToolPen)];
    NSUInteger annotationIndex = [annotationTools indexOfObject:@(tool)];
    self.toolControl.selectedSegmentIndex = mosaic ? 5 : (annotationIndex == NSNotFound ? 0 : (NSInteger)annotationIndex);
    self.mosaicControl.selectedSegmentIndex = self.mosaicTool == kKayokoFingerToolBlur ? 2 :
        (self.mosaicTool == kKayokoFingerToolCoarseMosaic ? 1 : 0);
    self.maskControl.selectedSegmentIndex = tool == kKayokoFingerToolSticker ? 2 : (tool == kKayokoFingerToolPixelate ? 1 : 0);
    BOOL annotate = self.selectedMode == 0;
    BOOL mask = self.selectedMode == 1;
    BOOL colorsVisible = (annotate && !mosaic) || (mask && tool == kKayokoFingerToolCover);
    self.toolControl.hidden = !annotate;
    self.maskControl.hidden = !mask;
    self.mosaicControl.hidden = !(annotate && mosaic);
    self.styleLabel.hidden = self.mosaicControl.hidden;
    self.colorScrollView.hidden = !colorsVisible;
    for (UIButton *button in self.colorButtons) button.hidden = !colorsVisible;
    self.widthLabel.hidden = !annotate;
    self.widthSlider.hidden = !annotate;
    self.widthValueLabel.hidden = !annotate;
    self.recognizeButton.hidden = self.selectedMode != 2;
    self.importOverlayButton.hidden = !(mask && tool == kKayokoFingerToolSticker);
    if (modeChanged) self.settingsScrollView.contentOffset = CGPointZero;
    [self invalidateIntrinsicContentSize];
    [self.superview setNeedsLayout];
    [self setNeedsLayout];
}

- (void)setSelectedColorIndex:(NSInteger)index {
    for (UIButton *button in self.colorButtons) button.selected = button.tag == index;
}

- (void)setStrokeWidth:(CGFloat)width {
    self.widthSlider.value = MIN(self.widthSlider.maximumValue, MAX(self.widthSlider.minimumValue, width));
    [self widthChanged:self.widthSlider];
}

- (void)widthChanged:(UISlider *)sender {
    self.widthValueLabel.text = [NSString stringWithFormat:@"%.2f", sender.value];
    sender.accessibilityValue = self.widthValueLabel.text;
}

- (void)modeChanged:(UISegmentedControl *)sender {
    if (self.modeSelectionHandler) self.modeSelectionHandler(sender.selectedSegmentIndex);
}

- (void)toolChanged:(UISegmentedControl *)sender {
    NSArray<NSNumber *> *tools = @[@(kKayokoFingerToolArrow), @(kKayokoFingerToolRectangle),
        @(kKayokoFingerToolEllipse), @(kKayokoFingerToolText), @(kKayokoFingerToolPen), @(self.mosaicTool)];
    NSInteger index = sender.selectedSegmentIndex;
    if (index < 0 || index >= (NSInteger)tools.count) return;
    KayokoFingerTool tool = [tools[index] integerValue];
    [self setSelectedMode:0 tool:tool];
    if (self.toolSelectionHandler) self.toolSelectionHandler(tool);
}

- (void)mosaicChanged:(UISegmentedControl *)sender {
    NSArray<NSNumber *> *tools = @[@(kKayokoFingerToolMosaic), @(kKayokoFingerToolCoarseMosaic), @(kKayokoFingerToolBlur)];
    NSInteger index = sender.selectedSegmentIndex;
    if (index < 0 || index >= (NSInteger)tools.count) return;
    KayokoFingerTool tool = [tools[index] integerValue];
    [self setSelectedMode:0 tool:tool];
    if (self.toolSelectionHandler) self.toolSelectionHandler(tool);
}

- (void)maskChanged:(UISegmentedControl *)sender {
    NSArray<NSNumber *> *tools = @[@(kKayokoFingerToolCover), @(kKayokoFingerToolPixelate), @(kKayokoFingerToolSticker)];
    NSInteger index = sender.selectedSegmentIndex;
    if (index < 0 || index >= (NSInteger)tools.count) return;
    KayokoFingerTool tool = [tools[index] integerValue];
    [self setSelectedMode:1 tool:tool];
    if (self.toolSelectionHandler) self.toolSelectionHandler(tool);
}

- (void)colorChanged:(UIButton *)sender {
    [self setSelectedColorIndex:sender.tag];
    if (self.colorSelectionHandler) self.colorSelectionHandler(sender.tag);
}

@end
