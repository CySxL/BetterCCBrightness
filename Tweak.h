#import <ControlCenterUIKit/CCUIContinuousSliderView.h>
#import <ControlCenterUIKit/CCUIControlCenterMaterialView.h>
#import <ControlCenterUIKit/CCUILabeledRoundButtonViewController.h>
#import <CoreBrightness/CBClient.h>
#import <DisplayModule/CCUIDisplayBackgroundViewController.h>
#import <DisplayModule/CCUIDisplayModuleViewController.h>
#import <ManagedConfiguration/MCProfileConnection.h>
#import <Masonry/Masonry.h>
#import <MaterialKit/MTMaterialView.h>
#import <SpringBoard/SBHarmonyController.h>
#import <SpringBoardUIServices/SBUIProudLockIconView.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <objc/runtime.h>

// The /System paths below are system paths, not jailbreak paths, so they stay
// as-is under rootless/roothide.

// CCUI Layout
extern CGFloat CCUISliderExpandedModuleContinuousCornerRadius();
extern CGFloat CCUISliderExpandedContentModuleHeight();
extern CGFloat CCUISliderExpandedContentModuleWidth();
extern BOOL CCUILayoutShouldBePortrait(UIView *);

// Auto-Brightness
extern BOOL _AXSAutoBrightnessEnabled();
extern void BKSDisplayBrightnessSetAutoBrightnessEnabled(BOOL);

// Reduce White Point
extern BOOL _AXSReduceWhitePointEnabled();
extern void _AXSSetReduceWhitePointEnabled(BOOL);
extern double MADisplayFilterPrefGetReduceWhitePointIntensity();
extern void MADisplayFilterPrefSetReduceWhitePointIntensity(double);

// Night Shift
// Use CBBlueLightClient

@interface UIView ()
@property(nonatomic, setter=_setContinuousCornerRadius:)
    CGFloat _continuousCornerRadius;
@end

@interface CCUILabeledRoundButtonViewController ()
@property(nonatomic) BOOL useAlternateBackground;
@end

// Prefixed because other tweaks label these sliders too, and %new leaves the
// first implementation of a selector in place.
@interface CCUIContinuousSliderView ()
@property(nonatomic) UILabel *bccbPercentLabel;
@property(nonatomic) NSNumber *bccbShowsPercent;
@property(nonatomic) NSInteger bccbPercent;
- (void)bccbUpdatePercentLabel;
@end

@interface CCUIModuleCollectionViewController : UIViewController
- (void)didUpdateHomeGestureDismissalAllowed:(BOOL)allowed
                    forModuleWithIdentifier:(NSString *)identifier;
@end

@interface CCUIContentModuleContainerViewController : UIViewController
@property(nonatomic, readonly) NSString *moduleIdentifier;
@property(nonatomic, weak) id delegate;
@end

@interface CCUICAPackageView ()
@property(nonatomic) CGFloat scale;
@end

@interface CCUIDisplayBackgroundViewController () <MCProfileConnectionObserver>
@property(nonatomic) CCUILabeledRoundButtonViewController *autoBrightnessButton;
@property(nonatomic) CCUILabeledRoundButtonViewController *autoLockButton;
@property(nonatomic) NSArray<CCUILabeledRoundButtonViewController *> *buttons;
@property(nonatomic) MTMaterialView *nightShiftMaterialView;
@property(nonatomic) CCUIContinuousSliderView *nightShiftSliderView;
@property(nonatomic) BOOL reduceWhitePointWasEnabled;
@property(nonatomic) CCUILabeledRoundButtonViewController *whitePointButton;
@property(nonatomic) MTMaterialView *whitePointMaterialView;
@property(nonatomic) CCUIContinuousSliderView *whitePointSliderView;
@property(nonatomic) BOOL observingStateChanges;
@property(nonatomic) NSNumber *previousMaxInactivity;
- (void)startObservingStateChangesIfNecessary;
- (void)startObservingStateChanges;
- (void)_toggleAutoLock;
- (void)_toggleAutoBrightness;
- (void)_toggleReduceWhitePoint;
@end
