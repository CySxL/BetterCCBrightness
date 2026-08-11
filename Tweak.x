#import "Tweak.h"

// valueForKey: raises on an ivar that has been renamed rather than returning
// nil, and an exception here is a safe mode.
static id ivarValue(id object, const char *name) {
  Ivar ivar = class_getInstanceVariable([object class], name);
  return ivar ? object_getIvar(object, ivar) : nil;
}

// The setting comes out of a managed configuration payload, so its type is not
// ours to assume.
static NSNumber *maxInactivitySetting(MCProfileConnection *connection) {
  id value = [connection userValueForSetting:@"maxInactivity"];
  return [value isKindOfClass:NSNumber.class] ? value : nil;
}

// The volume sliders are a subclass of CCUIContinuousSliderView, so the class
// says nothing about which module a slider belongs to.
static BOOL sliderIsInDisplayModule(UIView *slider) {
  static NSBundle *displayModule = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    displayModule = [NSBundle bundleForClass:%c(CCUIDisplayBackgroundViewController)];
  });

  for (UIResponder *responder = slider.nextResponder; responder;
       responder = responder.nextResponder)
    if ([responder isKindOfClass:UIViewController.class] &&
        [[NSBundle bundleForClass:responder.class] isEqual:displayModule])
      return YES;

  return NO;
}

// The collapsed tile sits beside Control Center's volume slider, so it takes the
// size a percentage is drawn at there.
static CGFloat percentSize(CGFloat width) {
  CGFloat expandedWidth = CCUISliderExpandedContentModuleWidth();
  if (width < expandedWidth * .5) return 16;
  return width < expandedWidth * .9 ? 20 : 25;
}

static UIFont *percentFont(CGFloat size) {
  static NSMutableDictionary<NSNumber *, UIFont *> *fonts = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{ fonts = [NSMutableDictionary dictionary]; });

  UIFont *font = fonts[@(size)];
  if (font) return font;

  font = [UIFont systemFontOfSize:size weight:UIFontWeightBold];
  UIFontDescriptor *rounded =
      [font.fontDescriptor fontDescriptorWithDesign:UIFontDescriptorSystemDesignRounded];
  if (rounded) font = [UIFont fontWithDescriptor:rounded size:size];

  fonts[@(size)] = font;
  return font;
}

%group DisplayModuleHooks

%hook CCUIDisplayBackgroundViewController
// clang-format off
%property(nonatomic, strong) CCUILabeledRoundButtonViewController *autoLockButton;
%property(nonatomic, strong) CCUILabeledRoundButtonViewController *autoBrightnessButton;
%property(nonatomic, strong) CCUILabeledRoundButtonViewController *whitePointButton;
%property(nonatomic, strong) CCUIContinuousSliderView *whitePointSliderView;
%property(nonatomic, strong) MTMaterialView *whitePointMaterialView;
%property(nonatomic, assign) BOOL reduceWhitePointWasEnabled;
%property(nonatomic, strong) CCUIContinuousSliderView *nightShiftSliderView;
%property(nonatomic, strong) MTMaterialView *nightShiftMaterialView;
%property(nonatomic, assign) BOOL observingStateChanges;
%property(nonatomic, strong) NSNumber *previousMaxInactivity;
// clang-format on
%new
- (NSArray<CCUILabeledRoundButtonViewController *> *)buttons {
  Ivar footerButtonsIvar = class_getInstanceVariable(self.class, "_footerButtons");
  if (footerButtonsIvar) return object_getIvar(self, footerButtonsIvar);
  return ivarValue(self, "_buttons");
}
%new
- (void)setButtons:(NSArray<CCUILabeledRoundButtonViewController *> *)footerButtons {
  if (class_getInstanceVariable(self.class, "_footerButtons")) {
    [self setFooterButtons:footerButtons];
    return;
  }

  Ivar buttonsIvar = class_getInstanceVariable(self.class, "_buttons");
  if (buttonsIvar) object_setIvar(self, buttonsIvar, footerButtons);
}
- (void)viewDidLoad {
  %orig;

  NSBundle *accessibilitySettingsBundle =
      [NSBundle bundleWithPath:@"/System/Library/PreferenceBundles/AccessibilitySettings.bundle"];
  NSBundle *displayAndBrightnessSettingsBundle = [NSBundle
      bundleWithPath:
          @"/System/Library/PrivateFrameworks/Settings/DisplayAndBrightnessSettings.framework"];
  SBUIProudLockIconView *proudLockIconView = [SBUIProudLockIconView alloc];

  CCUICAPackageDescription *lockPackageDescription = [CCUICAPackageDescription
      descriptionForPackageNamed:[proudLockIconView fileNameForCurrentDevice]
                        inBundle:[NSBundle bundleForClass:proudLockIconView.class]];

  self.autoLockButton = [[CCUILabeledRoundButtonViewController alloc]
      initWithGlyphPackageDescription:lockPackageDescription
                       highlightColor:[UIColor systemGreenColor]
                        useLightStyle:NO];
  self.autoLockButton.title = [displayAndBrightnessSettingsBundle localizedStringForKey:@"AUTOLOCK"
                                                                                  value:@"Auto-Lock"
                                                                                  table:@"Display"];
  self.autoLockButton.labelsVisible = YES;
  [self.autoLockButton.button addTarget:self
                                 action:@selector(_autoLockButtonPressed:)
                       forControlEvents:UIControlEventTouchUpInside];

  self.autoBrightnessButton = [[CCUILabeledRoundButtonViewController alloc]
      initWithGlyphPackageDescription:[CCUICAPackageDescription
                                          descriptionForPackageNamed:@"Brightness"
                                                            inBundle:[NSBundle
                                                                         bundleForClass:self.class]]
                       highlightColor:[UIColor systemGreenColor]
                        useLightStyle:NO];

  self.autoBrightnessButton.title =
      [accessibilitySettingsBundle localizedStringForKey:@"AUTO_BRIGHTNESS"
                                                   value:@"Auto-Brightness"
                                                   table:@"DisplayFilterSettings"];
  self.autoBrightnessButton.labelsVisible = YES;
  [self.autoBrightnessButton.button addTarget:self
                                       action:@selector(_autoBrightnessButtonPressed:)
                             forControlEvents:UIControlEventTouchUpInside];

  [self.view addSubview:self.autoLockButton.view];
  [self.view addSubview:self.autoBrightnessButton.view];

  self.whitePointSliderView = [CCUIContinuousSliderView new];
  [self.whitePointSliderView addTarget:self
                                action:@selector(_whitePointSliderEditingDidBegin:)
                      forControlEvents:UIControlEventEditingDidBegin];
  [self.whitePointSliderView addTarget:self
                                action:@selector(_whitePointSliderValueDidChange:)
                      forControlEvents:UIControlEventValueChanged];
  [self.whitePointSliderView addTarget:self
                                action:@selector(_whitePointSliderEditingDidEnd:)
                      forControlEvents:UIControlEventEditingDidEnd];
  self.whitePointMaterialView = [CCUIControlCenterMaterialView _darkMaterialView];
  [self.view addSubview:self.whitePointMaterialView];
  [self.view addSubview:self.whitePointSliderView];

  self.whitePointButton = [[CCUILabeledRoundButtonViewController alloc]
      initWithGlyphImage:[UIImage systemImageNamed:@"sun.haze.fill"]
          highlightColor:[UIColor systemBlueColor]
           useLightStyle:NO];
  self.whitePointButton.title =
      [accessibilitySettingsBundle localizedStringForKey:@"REDUCE_WHITE_POINT"
                                                   value:@"Reduce White Point"
                                                   table:@"Accessibility"];
  self.whitePointButton.labelsVisible = YES;
  [self.whitePointButton.button addTarget:self
                                   action:@selector(_reduceWhitePointButtonPressed:)
                         forControlEvents:UIControlEventTouchUpInside];
  [self.view addSubview:self.whitePointButton.view];

  NSMutableArray *mutableFooterButtons = [self.buttons mutableCopy];
  [mutableFooterButtons removeObject:self.nightShiftButton];
  [mutableFooterButtons insertObject:self.autoLockButton atIndex:1];
  self.buttons = [mutableFooterButtons copy];

  if ([CBClient supportsBlueLightReduction]) {
    self.nightShiftSliderView = [CCUIContinuousSliderView new];
    [self.nightShiftSliderView addTarget:self
                                  action:@selector(_nightShiftSliderValueDidChange:)
                        forControlEvents:UIControlEventValueChanged];
    [self.nightShiftSliderView addTarget:self
                                  action:@selector(_nightShiftSliderEditingDidEnd:)
                        forControlEvents:UIControlEventEditingDidEnd];
    self.nightShiftMaterialView = [CCUIControlCenterMaterialView _darkMaterialView];
    [self.view addSubview:self.nightShiftMaterialView];
    [self.view addSubview:self.nightShiftSliderView];

    [self.view addSubview:self.nightShiftButton.view];
  }
}
- (void)viewWillAppear:(BOOL)animated {
  %orig;
  [self startObservingStateChangesIfNecessary];

  self.whitePointSliderView.value =
      1 - ((MADisplayFilterPrefGetReduceWhitePointIntensity() - .25) / .75);

  float blueLightFilterStrength;
  CBClient *client = ivarValue([%c(SBHarmonyController) sharedInstance], "_client");
  [client.blueLightClient getStrength:&blueLightFilterStrength];
  self.nightShiftSliderView.value = blueLightFilterStrength;

  ((CCUICAPackageView *)ivarValue(self, "_packageView")).hidden = YES;

  [self.view setNeedsUpdateConstraints];
}
- (void)updateViewConstraints {
  CGFloat continuousCornerRadius = CCUISliderExpandedModuleContinuousCornerRadius() * .66;
  NSNumber *sliderWidth = @(CCUISliderExpandedContentModuleWidth() * .66);
  NSNumber *sliderHeight = @(CCUISliderExpandedContentModuleHeight() * .66);

  CGFloat heightOffset = -(CCUISliderExpandedContentModuleHeight() / 12);

  NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
  paragraphStyle.alignment = NSTextAlignmentCenter;
  // paragraphStyle.hyphenationFactor = 1.0f;
  self.autoBrightnessButton.buttonContainer.titleLabel.attributedText =
      [[NSMutableAttributedString alloc]
          initWithString:self.autoBrightnessButton.title
              attributes:@{NSParagraphStyleAttributeName : paragraphStyle}];

  [self.whitePointSliderView mas_remakeConstraints:^(MASConstraintMaker *make) {
    make.width.equalTo(sliderWidth);
    make.height.equalTo(sliderHeight);
    make.centerX.equalTo(self.view).offset(-(CCUISliderExpandedContentModuleWidth() - 7));
    if (CCUILayoutShouldBePortrait(self.view))
      make.centerY.equalTo(self.view);
    else
      make.centerY.equalTo(self.view).offset(CCUISliderExpandedContentModuleHeight() / 6);
  }];
  [self.whitePointMaterialView mas_remakeConstraints:^(MASConstraintMaker *make) {
    make.center.width.height.equalTo(self.whitePointSliderView);
  }];
  [self.whitePointButton.view mas_remakeConstraints:^(MASConstraintMaker *make) {
    make.width.equalTo(self.styleModeButton.view);
    make.centerX.equalTo(self.whitePointSliderView);
    make.bottom.equalTo(self.whitePointSliderView.mas_top).offset(heightOffset);
  }];
  [self.whitePointSliderView setContinuousSliderCornerRadius:continuousCornerRadius];
  self.whitePointMaterialView._continuousCornerRadius = continuousCornerRadius;

  [self.nightShiftSliderView mas_remakeConstraints:^(MASConstraintMaker *make) {
    make.width.equalTo(sliderWidth);
    make.height.equalTo(sliderHeight);
    make.centerX.equalTo(self.view).offset(CCUISliderExpandedContentModuleWidth() - 7);
    if (CCUILayoutShouldBePortrait(self.view))
      make.centerY.equalTo(self.view);
    else
      make.centerY.equalTo(self.view).offset(CCUISliderExpandedContentModuleHeight() / 6);
  }];

  [self.nightShiftMaterialView mas_remakeConstraints:^(MASConstraintMaker *make) {
    make.center.width.height.equalTo(self.nightShiftSliderView);
  }];
  [self.nightShiftButton.view mas_remakeConstraints:^(MASConstraintMaker *make) {
    make.width.equalTo(self.styleModeButton.view);
    make.centerX.equalTo(self.nightShiftSliderView);
    make.bottom.equalTo(self.nightShiftSliderView.mas_top).offset(heightOffset);
  }];
  [self.nightShiftSliderView setContinuousSliderCornerRadius:continuousCornerRadius];
  self.nightShiftMaterialView._continuousCornerRadius = continuousCornerRadius;

  CCUICAPackageView *packageView = ivarValue(self, "_packageView");

  [self.autoBrightnessButton.view mas_remakeConstraints:^(MASConstraintMaker *make) {
    make.width.equalTo(self.styleModeButton.view);
    make.centerX.equalTo(packageView);
    make.centerY.equalTo(packageView);
  }];

  %orig;
}
- (void)_updateState {
  %orig;

  self.autoLockButton.useAlternateBackground = NO;
  CCUIRoundButton *roundAutoLockButton = (CCUIRoundButton *)self.autoLockButton.button;
  roundAutoLockButton.glyphPackageView.scale =
      UIScreen.mainScreen.scale == 2 ? .33
      : [roundAutoLockButton.glyphPackageView.packageDescription.packageURL.lastPathComponent
            hasSuffix:@"d73.ca"]
          ? 2
          : .25;
  BOOL autoLockEnabled =
      maxInactivitySetting([MCProfileConnection sharedConnection]).intValue != INT_MAX;
  self.autoLockButton.enabled = autoLockEnabled;
  self.autoLockButton.subtitle = [self _subtitleForTrueToneEnabled:autoLockEnabled];
  self.autoLockButton.glyphState = autoLockEnabled ? @"Locked" : @"Unlocked";

  self.autoBrightnessButton.useAlternateBackground = NO;
  BOOL autoBrightnessEnabled = _AXSAutoBrightnessEnabled();
  self.autoBrightnessButton.enabled = autoBrightnessEnabled;
  self.autoBrightnessButton.subtitle = [self _subtitleForTrueToneEnabled:autoBrightnessEnabled];

  self.whitePointButton.useAlternateBackground = NO;
  BOOL whitePointEnabled = _AXSReduceWhitePointEnabled();
  self.whitePointButton.enabled = whitePointEnabled;
  self.whitePointButton.subtitle = [self _subtitleForTrueToneEnabled:whitePointEnabled];
}
- (void)setGlyphState:(NSString *)glyphState {
  self.autoBrightnessButton.glyphState = glyphState;
}
- (void)setHeaderGlyphState:(NSString *)glyphState {
  self.autoBrightnessButton.glyphState = glyphState;
}
%new
- (void)startObservingStateChangesIfNecessary {
  if (!self.observingStateChanges) [self startObservingStateChanges];
}
%new
- (void)startObservingStateChanges {
  MCProfileConnection *connection = [MCProfileConnection sharedConnection];
  [self profileConnectionDidReceiveEffectiveSettingsChangedNotification:connection userInfo:nil];
  [connection addObserver:self];
  self.observingStateChanges = YES;
}
%new
- (void)profileConnectionDidReceiveEffectiveSettingsChangedNotification:
            (MCProfileConnection *)connection
                                                               userInfo:(NSDictionary *)userInfo {
  NSNumber *maxInactivity = maxInactivitySetting(connection);
  // A read that comes back empty is not a timeout worth remembering.
  if (maxInactivity && maxInactivity.intValue != INT_MAX)
    self.previousMaxInactivity = maxInactivity;
}
%new
- (void)_whitePointSliderEditingDidBegin:(CCUIContinuousSliderView *)slider {
  self.reduceWhitePointWasEnabled = _AXSReduceWhitePointEnabled();
  _AXSSetReduceWhitePointEnabled(YES);
}
%new
- (void)_whitePointSliderValueDidChange:(CCUIContinuousSliderView *)slider {
  MADisplayFilterPrefSetReduceWhitePointIntensity(
      [@(((1 - slider.value) * .75 + .25)) doubleValue]);
}
%new
- (void)_whitePointSliderEditingDidEnd:(CCUIContinuousSliderView *)slider {
  _AXSSetReduceWhitePointEnabled(self.reduceWhitePointWasEnabled);
}
%new
- (void)_nightShiftSliderValueDidChange:(CCUIContinuousSliderView *)slider {
  CBClient *client = ivarValue([%c(SBHarmonyController) sharedInstance], "_client");
  [client.blueLightClient setStrength:slider.value commit:NO];
}
%new
- (void)_nightShiftSliderEditingDidEnd:(CCUIContinuousSliderView *)slider {
  CBClient *client = ivarValue([%c(SBHarmonyController) sharedInstance], "_client");
  [client.blueLightClient setStrength:slider.value commit:YES];
}
%new
- (void)_toggleAutoLock {
  MCProfileConnection *connection = [MCProfileConnection sharedConnection];
  BOOL autoLockEnabled = maxInactivitySetting(connection).intValue != INT_MAX;
  [connection setValue:autoLockEnabled ? @(INT_MAX) : self.previousMaxInactivity ?: @(30) forSetting:@"maxInactivity"];
  [self _updateState];
}
%new
- (void)_toggleAutoBrightness {
  BOOL autoBrightnessEnabled = _AXSAutoBrightnessEnabled();
  BKSDisplayBrightnessSetAutoBrightnessEnabled(!autoBrightnessEnabled);
  [self _updateState];
}
%new
- (void)_toggleReduceWhitePoint {
  BOOL reduceWhitePointEnabled = _AXSReduceWhitePointEnabled();
  _AXSSetReduceWhitePointEnabled(!reduceWhitePointEnabled);
  [self _updateState];
}
%new
- (void)_autoLockButtonPressed:(id)sender {
  [self _toggleAutoLock];
}
%new
- (void)_autoBrightnessButtonPressed:(id)sender {
  [self _toggleAutoBrightness];
}
%new
- (void)_reduceWhitePointButtonPressed:(id)sender {
  [self _toggleReduceWhitePoint];
}
%end

%hook CCUIContinuousSliderView
// clang-format off
%property(nonatomic, strong) UILabel *bccbPercentLabel;
%property(nonatomic, strong) NSNumber *bccbShowsPercent;
%property(nonatomic, assign) NSInteger bccbPercent;
// clang-format on
- (void)layoutSubviews {
  %orig;
  [self bccbUpdatePercentLabel];
}
%new
- (void)bccbUpdatePercentLabel {
  if (!self.bccbShowsPercent) {
    if (!self.superview) return;
    self.bccbShowsPercent = @(sliderIsInDisplayModule(self));
  }
  if (!self.bccbShowsPercent.boolValue) return;

  UILabel *label = self.bccbPercentLabel;

  if (!label) {
    label = [UILabel new];
    label.textAlignment = NSTextAlignmentCenter;
    label.userInteractionEnabled = NO;
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = .6;
    self.bccbPercentLabel = label;
    self.bccbPercent = -1;
    [self addSubview:label];
  }

  CGFloat width = CGRectGetWidth(self.bounds);
  CGFloat size = percentSize(width);
  CGRect frame = CGRectMake(0, CGRectGetMidY(self.bounds) - size, width, size * 2);

  // This runs on the drag path, so nothing is assigned that has not changed.
  if (!CGRectEqualToRect(label.frame, frame)) {
    label.frame = frame;
    label.font = percentFont(size);
  }

  NSInteger percent = lroundf(self.value * 100);

  if (percent != self.bccbPercent) {
    self.bccbPercent = percent;
    label.text = [NSString stringWithFormat:@"%ld%%", (long)percent];

    // The label sits at the middle, so the fill reaches it at half.
    label.textColor = percent >= 50 ? UIColor.blackColor : UIColor.whiteColor;
  }

  if (self.subviews.lastObject != label) [self bringSubviewToFront:label];
}
%end

%end

static void add_image(const struct mach_header *mh, intptr_t vmaddr_slide) {
  Dl_info info;
  if (!dladdr(mh, &info)) return;
  if (!strcmp(info.dli_fname,
              "/System/Library/ControlCenter/Bundles/DisplayModule.bundle/DisplayModule"))
    dispatch_async(dispatch_get_main_queue(), ^{
      class_addProtocol(%c(CCUIDisplayBackgroundViewController),
                        objc_getProtocol("MCProfileConnectionObserver"));
      %init(DisplayModuleHooks);
    });
}

%ctor {
  _dyld_register_func_for_add_image(add_image);
  // This needs to be called at least once before we actually use it...
  BKSDisplayBrightnessSetAutoBrightnessEnabled(_AXSAutoBrightnessEnabled());
}
