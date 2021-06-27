#include <notify.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

static bool isNewOSVersion = false;
static bool isChargeTimeETAEnabled = false;
static bool isWeatherLabelEnabled = true;
static bool isWeatherAppIconEnabled = false;
static bool isWeatherAppIconShowTemp = true;
static bool isWeatherAppIconShowBadge = false;
static bool isWeatherAbstractEnabled = false;
static bool isWeatherGreetingEnabled = false;
static bool isShowAllNotifications = false;
static bool isShowAllNotificationsWhenUnlocked = false;
static double updateIntervalMinutes = 60.0;
static int updateCycle = 0;

extern "C" mach_port_t kIOMasterPortDefault;
extern "C" kern_return_t IORegistryEntryCreateCFProperties(mach_port_t, CFMutableDictionaryRef *, CFAllocatorRef, UInt32);
extern "C" mach_port_t IOServiceGetMatchingService(mach_port_t, CFDictionaryRef);
extern "C" CFMutableDictionaryRef IOServiceMatching(const char *);

__attribute__((visibility ("hidden")))
uint32_t notify_register_dispatch_and_run_once(const char *name, int *out_token, dispatch_queue_t queue, notify_handler_t handler) {
    uint32_t result = notify_register_dispatch(name, out_token, queue, handler);
    int token = out_token ? *out_token : 0;
    handler(token);
    return result;
}

__attribute__((visibility ("hidden")))
NSDictionary *FCPrivateBatteryStatus()
{
    static CFMutableDictionaryRef g_powerSourceService;
    static mach_port_t g_platformExpertDevice;

    static BOOL foundSymbols = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        g_powerSourceService = IOServiceMatching("IOPMPowerSource");
        g_platformExpertDevice = IOServiceGetMatchingService(kIOMasterPortDefault, g_powerSourceService);
        foundSymbols = (g_powerSourceService && g_platformExpertDevice);
    });
    if (!foundSymbols) return nil;
    
    CFMutableDictionaryRef prop = NULL;
    IORegistryEntryCreateCFProperties(g_platformExpertDevice, &prop, 0, 0);
    return prop ? ((NSDictionary *)CFBridgingRelease(prop)) : nil;
}

__attribute__((visibility ("hidden")))
NSString *BatteryChargingEstimatedTimeLocalizedString() {
    NSDictionary *powerInfo = FCPrivateBatteryStatus();
    if (!powerInfo) return nil;
    NSNumber *isCharging = [powerInfo objectForKey:@"IsCharging"];
    NSNumber *fullyCharged = [powerInfo objectForKey:@"FullyCharged"];
    NSNumber *percentage = [powerInfo objectForKey:@"CurrentCapacity"];
    NSNumber *maxCapacity = [powerInfo objectForKey:@"AppleRawMaxCapacity"];
    //NSNumber *designCapacity = [powerInfo objectForKey:@"DesignCapacity"];
    NSNumber *currentCapacity = [powerInfo objectForKey:@"AppleRawCurrentCapacity"];
    NSNumber *instantAmperage = [powerInfo objectForKey:@"InstantAmperage"];
    if (!isCharging
        || !fullyCharged
        || !percentage
        || !maxCapacity
        //|| !designCapacity
        || !currentCapacity
        || !instantAmperage) return nil;
    if ([fullyCharged boolValue] || [percentage intValue] == (isNewOSVersion ? 100 : 1000)) return nil;
    if (![isCharging boolValue] || [instantAmperage intValue] < 35) return nil;
    if ([maxCapacity intValue] <= [currentCapacity intValue]) return nil;
    CGFloat hourEstimated, percent = [currentCapacity intValue] * 1.0 / [maxCapacity intValue];
    if (percent > 97.5 || [instantAmperage intValue] <= 200)
        hourEstimated = ([maxCapacity intValue] - [currentCapacity intValue]) / [instantAmperage intValue];
    else {
        CGFloat _percent = 0.975;
        hourEstimated = [maxCapacity intValue] * 0.025 / 200;
        if (percent <= 95 && [instantAmperage intValue] > 300) {
            _percent = 0.95;
            hourEstimated += [maxCapacity intValue] * 0.025 / 300;
        }
        if (percent <= 90 && [instantAmperage intValue] > 400) {
            _percent = 0.9;
            hourEstimated += [maxCapacity intValue] * 0.05 / 400;
        }
        if (percent <= 80 && [instantAmperage intValue] > 500) {
            _percent = 0.8;
            hourEstimated += [maxCapacity intValue] * 0.1 / 500;
        }
        hourEstimated += ([maxCapacity intValue] * _percent - [currentCapacity intValue]) / [instantAmperage intValue];
    }
    if (hourEstimated >= 24) return nil;
    if (hourEstimated < 0.02) hourEstimated = 0.02;
    
    NSDateComponents *estimatedComponents = [NSDateComponents new];
    estimatedComponents.hour = (NSInteger)hourEstimated;
    estimatedComponents.minute = (NSInteger)((hourEstimated - estimatedComponents.hour) * 60);
    NSDateComponentsFormatter* dcf = [[NSDateComponentsFormatter alloc] init];
    dcf.unitsStyle = NSDateComponentsFormatterUnitsStyleFull;
    NSCalendar* cal = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    cal.locale = [NSLocale currentLocale];
    dcf.calendar = cal;
    NSString *localizedString = [dcf stringFromDateComponents:estimatedComponents];
    [estimatedComponents release];
    [dcf release];
    return [NSString stringWithFormat:[[NSBundle mainBundle] localizedStringForKey:@"ALARM_SNOOZE_TIME_REMAINING" //@"BATTERY_CHARGE_REMAINING"
                        value:nil table:@"SpringBoard"], localizedString];
}

extern "C" NSString *WAConditionsLineStringFromCurrentForecasts(id/*WACurrentForecast **/);

@interface UIView()
@property (nonatomic,readonly) UIInterfaceOrientation _keyboardOrientation;
@end

@interface SBUILegibilityLabel : UIView
@property (nonatomic, retain) /*_UILegibilitySettings **/id legibilitySettings;
@property (assign, nonatomic) CGFloat strength;
@property (nonatomic, retain) UIFont *font;
@property (assign) NSInteger textAlignment;
@end

@interface SBLockScreenDateViewController : UIViewController
@end

@interface SBFLockScreenAlternateDateLabel : UIView
-(SBUILegibilityLabel *)label;
@end

@interface SBFLockScreenDateSubtitleDateView : UIView
@property (nonatomic) CGFloat alignmentPercent;
@property (nonatomic, retain) SBFLockScreenAlternateDateLabel *alternateDateLabel;
@property (nonatomic, assign) SBUILegibilityLabel *weatherLabel;
@end

@interface SBFLockScreenDateSubtitleView : UIView
@property (nonatomic, retain) SBUILegibilityLabel *estimateTimeLabel;
-(CGRect)subtitleLabelFrame;
@end

@interface SBFLockScreenDateView : UIView
@property (nonatomic, assign) SBFLockScreenDateSubtitleDateView *o_dateSubtitleView;
@property (nonatomic, retain) SBFLockScreenDateSubtitleView *customSubtitleView;
@property (nonatomic, retain) UIImageView *conditionsImageView;
@property (nonatomic, retain) SBUILegibilityLabel *temperatureLabel;
@property (assign, nonatomic) CGFloat alignmentPercent;
@property (getter=isSubtitleHidden) bool subtitleHidden;
-(UIView *)alternateDateLabel;
-(void)layoutWeatherLabel;
-(void)updateWeatherLabel;
-(SBUILegibilityLabel *)_timeLabel;
@end

@interface SBFAuthenticationRequest : NSObject
@end

@interface SBFUserAuthenticationController : NSObject
-(BOOL)isAuthenticated;
@end

@interface SBBacklightController : NSObject
@property (nonatomic,readonly) BOOL screenIsOn;
@property (nonatomic,readonly) BOOL screenIsDim;
+(id)sharedInstance;
-(CGFloat)backlightFactor; //not present on iOS 10
@end

@interface FBBundleInfo : NSObject
@property (nonatomic, copy, readonly) NSString *bundleIdentifier;
@end

@interface FBApplicationInfo : FBBundleInfo
@end

@interface SBApplicationInfo : FBApplicationInfo
@property (nonatomic, retain) Class iconClass;
@end

@interface SBIcon : NSObject
-(NSString *)leafIdentifier;
-(void)setBadge:(NSString *)badgeString;
@end

@interface SBIconView : UIView
@property (nonatomic, assign) NSUInteger location; //iOS 13 or up is (retain) NSString *
@property (nonatomic, retain) SBIcon* icon;
-(UIView *)_iconImageView;
@end

@interface SBIconImageView : UIView
@property (nonatomic, readonly) double continuousCornerRadius;
@property (nonatomic, retain) NSString *location; //iOS 13 or up
@property (nonatomic, assign) double brightness;
@property (nonatomic, readonly) SBIcon *icon;
@property (nonatomic, assign) SBIconView *iconView; //iOS 11 or up
-(UIImage *)squareContentsImage;
-(UIImage *)contentsImage;
@end

@interface CLAssertion : NSObject
@end

@interface CLInUseAssertion : CLAssertion
+(id)newAssertionForBundleIdentifier:(id)arg1 withReason:(id)arg2 ;
@end

@interface WFLocation : NSObject
-(NSTimeZone *)timeZone;
@end

@interface WATodayModel : NSObject
-(WFLocation *)location;
@end

@interface WATodayAutoupdatingLocationModel : WATodayModel
@property (nonatomic, retain) CLInUseAssertion *_weatherInUseAssertion;
@end

@interface WAForecastModel : NSObject
-(WFLocation *)location;
@end

@interface WALegibilityLabel : UIView
@end

@interface WATodayPadViewStyle : NSObject
@property (nonatomic, assign) NSUInteger format;
@property (nonatomic, assign) CGFloat locationLabelBaselineToTemperatureLabelBaseline;
@property (nonatomic, assign) CGFloat conditionsLabelBaselineToLocationLabelBaseline;
@property (nonatomic, assign) CGFloat conditionsLabelBaselineToBottom;
@end

@interface WATodayPadView : UIView
@property (nonatomic, retain) WALegibilityLabel *locationLabel;
@property (nonatomic, retain) WALegibilityLabel *conditionsLabel;
@property (nonatomic, retain) UIImageView *conditionsImageView;
@property (nonatomic, retain) WALegibilityLabel *temperatureLabel;
@property (nonatomic, retain) WATodayPadViewStyle *style;
-(id)initWithFrame:(CGRect)frame;
@end

@interface WALockscreenWidgetViewController : UIViewController
@property (nonatomic, assign) double updateInterval;
@property (nonatomic, assign) int updateCycle;
@property (nonatomic, assign) int updateCount;
@property (nonatomic, assign) BOOL ignoreUpdateCycle;
+(WALockscreenWidgetViewController *)sharedInstanceIfExists;
-(NSString *)lockScreenLabelString;
-(WATodayModel *)todayModel;
-(WATodayPadView *)todayView;
-(BOOL)dataReady;
@end

@interface SBLiveWeatherIconWeatherView : UIView
@property (nonatomic, assign) SBIconImageView *iconImageView;
@property (nonatomic, retain) UIImage *backgroundImage;
@property (nonatomic, retain) UIImageView *logo;
@property (nonatomic, retain) UILabel *temp;
-(void)setupTempLabel;
-(void)setupLogoView;
-(void)updateWeatherDisplay;
@end

@interface SBLiveWeatherIconImageView : SBIconImageView
@property (nonatomic, retain) SBLiveWeatherIconWeatherView *liveWeatherView;
-(void)updateWeatherForPresentation;
-(void)updateMask;
@end

@interface WLPreferenceManager : NSObject
+(BOOL)grandEnabled;
+(void)setChargeTimeETAEnabled:(BOOL)enable;
+(void)setWeatherLabelEnabled:(BOOL)enable;
+(void)setWeatherAppIconEnabled:(BOOL)enable;
+(void)setWeatherAppIconShowTemperature:(BOOL)iconshowtemp;
+(void)setWeatherAppIconShowBadge:(BOOL)badgeshowtemp;
+(void)setWeatherAbstractEnabled:(BOOL)enable;
+(void)setWeatherGreetingEnabled:(BOOL)enable;
+(void)setShowAllNotifications:(BOOL)show;
+(void)setShowAllNotificationsWhenUnlocked:(BOOL)show;
+(void)setUpdateInterval:(double)interval;
+(void)setUpdateCycle:(int)cycle;
@end

@interface NCNotificationListSectionRevealHintView : UIView
@property (nonatomic, retain) SBUILegibilityLabel *revealHintTitle;
@property (nonatomic,retain) id /*_UILegibilitySettings **/legibilitySettings;
@property (nonatomic, retain) id /*WAGreetingView **/greetingView;
@property (nonatomic, retain) id _greetingViewController;
@property (nonatomic, retain) UIFont *_titleFont;
-(void)layoutGreetingView;
@end

static BOOL o_showAlternateDate;
static CGFloat lineDistance;
static SBFLockScreenDateView *lockScreenDateView;
static UIView *mainPageView;
static SBLiveWeatherIconImageView *weatherIconView, *floatyDockWeatherIconView;
static NCNotificationListSectionRevealHintView *revealHintView;
static id notificationListViewController; //NCNotificationCombinedListViewController(iOS12)/NCNotificationStructuredListViewController(iOS13+)

@implementation WLPreferenceManager
+(BOOL)grandEnabled {
    return isWeatherLabelEnabled || isWeatherAppIconEnabled || isWeatherAbstractEnabled || isWeatherGreetingEnabled;
}

+(void)setChargeTimeETAEnabled:(BOOL)enable {
    isChargeTimeETAEnabled = enable;
}

+(void)setWeatherLabelEnabled:(BOOL)enable {
    BOOL updateRequired = [self grandEnabled];
    isWeatherLabelEnabled = enable;
    BOOL isEnabled = [self grandEnabled];
    updateRequired ^= isEnabled;
    WALockscreenWidgetViewController *controller = [WALockscreenWidgetViewController sharedInstanceIfExists];
    if (updateRequired) controller.updateCount = -1;
    if (isEnabled) [controller updateForWidgetPresented:updateRequired];
}

+(void)setWeatherAppIconEnabled:(BOOL)enable {
    BOOL updateRequired = [self grandEnabled];
    isWeatherAppIconEnabled = enable;
    BOOL isEnabled = [self grandEnabled];
    updateRequired ^= isEnabled;
    WALockscreenWidgetViewController *controller = [WALockscreenWidgetViewController sharedInstanceIfExists];
    if (updateRequired) controller.updateCount = -1;
    if (isEnabled) [controller updateForWidgetPresented:updateRequired];
}

+(void)setWeatherAppIconShowTemperature:(BOOL)iconshowtemp {
    isWeatherAppIconShowTemp = iconshowtemp;
    [[WALockscreenWidgetViewController sharedInstanceIfExists] updateForWidgetPresented:NO];
}

+(void)setWeatherAppIconShowBadge:(BOOL)badgeshowtemp {
    isWeatherAppIconShowBadge = badgeshowtemp;
    [[WALockscreenWidgetViewController sharedInstanceIfExists] updateForWidgetPresented:NO];
}

+(void)setWeatherAbstractEnabled:(BOOL)enable {
    BOOL updateRequired = [self grandEnabled];
    isWeatherAbstractEnabled = enable;
    BOOL isEnabled = [self grandEnabled];
    updateRequired ^= isEnabled;
    WALockscreenWidgetViewController *controller = [WALockscreenWidgetViewController sharedInstanceIfExists];
    if (updateRequired) controller.updateCount = -1;
    if (isEnabled) [controller updateForWidgetPresented:updateRequired];
}

+(void)setWeatherGreetingEnabled:(BOOL)enable {
    BOOL updateRequired = [self grandEnabled];
    isWeatherGreetingEnabled = enable;
    BOOL isEnabled = [self grandEnabled];
    updateRequired ^= isEnabled;
    WALockscreenWidgetViewController *controller = [WALockscreenWidgetViewController sharedInstanceIfExists];
    if (updateRequired) controller.updateCount = -1;
    if (isEnabled) [controller updateForWidgetPresented:updateRequired];
}

+(void)setShowAllNotifications:(BOOL)show {
    isShowAllNotifications = show;
}

+(void)setShowAllNotificationsWhenUnlocked:(BOOL)show {
    isShowAllNotificationsWhenUnlocked = show;
}

+(void)setUpdateInterval:(double)interval {
    updateIntervalMinutes = interval;
    if ([WALockscreenWidgetViewController sharedInstanceIfExists])
        [WALockscreenWidgetViewController sharedInstanceIfExists].updateInterval = updateIntervalMinutes * 60.0;
}

+(void)setUpdateCycle:(int)cycle {
    updateCycle = cycle;
    WALockscreenWidgetViewController *controller = [WALockscreenWidgetViewController sharedInstanceIfExists];
    if (controller) {
        BOOL ison = controller.updateCycle == 0 && updateCycle != 0;
        controller.updateCycle = updateCycle;
        if (ison) {
            controller.updateCount = -1;
            if ([self grandEnabled]) [controller updateForWidgetPresented:YES];
        }
    }
}
@end

@implementation SBLiveWeatherIconWeatherView
-(instancetype)initWithFrame:(CGRect)frame {
    if(self = [super initWithFrame:frame]) {
        self.backgroundColor = [UIColor clearColor];
        self.clipsToBounds = YES;
        if (![WALockscreenWidgetViewController sharedInstanceIfExists]) [[WALockscreenWidgetViewController new] _setupWeatherModel];
    }
    return self;
}

-(void)setupTempLabel{
    if (!self.temp) {
        self.temp = [[UILabel alloc] init];
        [self addSubview:self.temp];
    }
    self.temp.frame = CGRectMake(0, 0, self.frame.size.width, self.frame.size.height);
    self.temp.font = [UIFont boldSystemFontOfSize:13];
    self.temp.textColor = [UIColor whiteColor];
    self.temp.textAlignment = NSTextAlignmentCenter;
    [self.temp setCenter:CGPointMake(self.frame.size.width / 1.9, self.frame.size.height / 1.22)];
}

-(void)setupLogoView{
    if (!self.logo) {
        self.logo = [[UIImageView alloc] init];
        [self addSubview:self.logo];
        
        [self.logo.leftAnchor constraintEqualToAnchor:self.leftAnchor constant:4].active = YES;
        [self.logo.rightAnchor constraintEqualToAnchor:self.rightAnchor constant:-4].active = YES;
        [self.logo.topAnchor constraintEqualToAnchor:self.topAnchor constant:4].active = YES;
        [self.logo.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-4].active = YES;
    }
    self.logo.contentMode = UIViewContentModeScaleAspectFit;
    if (isWeatherAppIconShowTemp) {
        self.logo.frame = CGRectMake(0, 0, self.frame.size.width / 1.18 , self.frame.size.height / 1.18);
        [self.logo setCenter:CGPointMake(self.frame.size.width / 2, self.frame.size.height / 2.74)];
    } else {
        self.logo.frame = CGRectMake(0, 0, self.frame.size.width / 1.05 , self.frame.size.height / 1.05);
        [self.logo setCenter:CGPointMake(self.frame.size.width / 2, self.frame.size.height / 2)];
    }
}

-(void)updateWeatherDisplay {
    [self setupTempLabel];
    [self setupLogoView];
    
    WALockscreenWidgetViewController *_weatherModel = [WALockscreenWidgetViewController sharedInstanceIfExists];
    BOOL enabled = isWeatherAppIconEnabled && self.iconImageView && _weatherModel && [_weatherModel dataReady];
    if (enabled) {
        WAForecastModel *currentForecastModel = [_weatherModel currentForecastModel];
        NSString *imageName = [[[_weatherModel _conditionsImage] imageAsset] assetName];
        BOOL night = NO;
        if (imageName
            && [imageName length]
            && [[imageName lowercaseString] containsString:@"night"]) night = YES;
        else {
            NSCalendar *calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
            calendar.timeZone = [[currentForecastModel location] timeZone];
            NSDateComponents *sunrise = [calendar
                                       components:NSCalendarUnitHour | NSCalendarUnitMinute
                                         fromDate:[currentForecastModel sunrise]],
                             *sunset = [calendar
                                      components:NSCalendarUnitHour | NSCalendarUnitMinute
                                        fromDate:[currentForecastModel sunset]];
            NSUInteger observationTime = (NSUInteger)[[currentForecastModel currentConditions] observationTime];
            night = observationTime < sunrise.hour * 100 + sunrise.minute
                 || observationTime >= sunset.hour * 100 + sunset.minute;
        }
        self.backgroundImage = [UIImage imageWithContentsOfFile:night
                                ? @"/Library/Application Support/WeatherDate/background_night.png"
                                : @"/Library/Application Support/WeatherDate/background_day.png"];
        [self.iconImageView updateImageAnimated:NO];
        self.temp.text = [_weatherModel _temperature];
        [self.temp layoutSubviews];
        self.temp.hidden = !isWeatherAppIconShowTemp;
        self.logo.image = [_weatherModel _conditionsImage];
        [self.logo layoutSubviews];
        self.logo.hidden = NO;
        if ([weatherIconView liveWeatherView] == self) {
            if (isWeatherAppIconShowBadge) [self.iconImageView.icon setBadge:[_weatherModel _temperature]];
            else [self.iconImageView.icon setBadge:nil];
        }
    } else {
        self.backgroundImage = nil;
        [self.iconImageView updateImageAnimated:NO];
        self.temp.hidden = YES;
        self.logo.hidden = YES;
        [self.iconImageView.icon setBadge:nil];
    }
}

-(void)layoutSubviews {
    [self updateWeatherDisplay];
    if ([weatherIconView liveWeatherView] != self)
        [[weatherIconView liveWeatherView] updateWeatherDisplay];
    if ([floatyDockWeatherIconView liveWeatherView] != self)
        [[floatyDockWeatherIconView liveWeatherView] updateWeatherDisplay];
}

-(void)dealloc {
    if (self.temp) {
        [self.temp removeFromSuperview];
        [self.temp release];
    }
    if (self.logo) {
        [self.logo removeFromSuperview];
        [self.logo release];
    }
    self.iconImageView = nil;
    [super dealloc];
}
@end

%hook SBFLockScreenDateSubtitleView
%property (nonatomic, retain) SBUILegibilityLabel *estimateTimeLabel;
%new
-(void)updateEstimateTimeLabelFrame {
    if (!self.superview || !self.estimateTimeLabel) return;
    if ([[self superview] class] != [SBFLockScreenDateView class]) return;
    CGRect mainFrame = [self subtitleLabelFrame];
    CGFloat alignmentPercent = [[self superview] alignmentPercent];
    self.estimateTimeLabel.frame = CGRectMake(
        (self.frame.size.width - self.estimateTimeLabel.frame.size.width) / 2 * (1 + alignmentPercent),
        mainFrame.origin.y + mainFrame.size.height + lineDistance / 2,
        self.estimateTimeLabel.frame.size.width,
        self.estimateTimeLabel.frame.size.height
    );
}

-(void)layoutSubviews {
    %orig;
    [self updateEstimateTimeLabelFrame];
}

-(void)setLegibilitySettings:(id)arg1 {
    %orig;
    self.estimateTimeLabel.legibilitySettings = arg1;
}

-(void)setStrength:(CGFloat)arg1 {
    %orig;
    self.estimateTimeLabel.strength = arg1;
}

-(void)dealloc {
    if (self.estimateTimeLabel) {
        [self.estimateTimeLabel removeFromSuperview];
        self.estimateTimeLabel = nil;
    }
    %orig;
}
%end

%hook SBFLockScreenDateSubtitleDateView
%property (nonatomic, retain) SBUILegibilityLabel *weatherLabel;
-(void)didMoveToSuperview {
    %orig;
    if ([[self superview] class] == [SBFLockScreenDateView class])
        [[self superview] setO_dateSubtitleView:(UIView *)self];
}

-(void)removeFromSuperview {
    [self.weatherLabel removeFromSuperview];
    self.weatherLabel = nil;
    if ([[self superview] class] == [SBFLockScreenDateView class])
        [[self superview] setO_dateSubtitleView:nil];
    %orig;
}

%new
-(void)updateWeatherLabelSettings {
    if (!self.superview || !self.weatherLabel) return;
    if ([[self superview] class] != [SBFLockScreenDateView class]) return;
    SBUILegibilityLabel *originalLabel = self.alternateDateLabel.label;
    self.weatherLabel.legibilitySettings = [originalLabel legibilitySettings];
    self.weatherLabel.strength = [originalLabel strength];
    self.weatherLabel.font = [originalLabel font];
    self.weatherLabel.textAlignment = [originalLabel textAlignment];
}

%new
-(void)updateWeatherLabelFrame {
    if (!self.superview || !self.weatherLabel) return;
    if ([[self superview] class] != [SBFLockScreenDateView class]) return;
    CGRect alternateFrame = self.alternateDateLabel.frame;
    lineDistance = alternateFrame.origin.y - alternateFrame.size.height;
    self.weatherLabel.frame = CGRectMake(
        (self.frame.size.width - self.weatherLabel.frame.size.width) / 2 * (1 + self.alignmentPercent),
        alternateFrame.origin.y + alternateFrame.size.height + lineDistance / 2,
        self.weatherLabel.frame.size.width,
        self.weatherLabel.frame.size.height
    );
}

-(void)layoutSubviews {
    %orig;
    [self updateWeatherLabelFrame];
}

-(void)setAlignmentPercent:(CGFloat)arg1 {
    %orig;
    [self updateWeatherLabelFrame];
}

-(void)setLegibilitySettings:(id)arg1 {
    %orig;
    [self updateWeatherLabelSettings];
}

-(void)setStrength:(CGFloat)arg1 {
    %orig;
    [self updateWeatherLabelSettings];
}

-(void)dealloc {
    if (self.weatherLabel) {
        [self.weatherLabel removeFromSuperview];
        self.weatherLabel = nil;
    }
    %orig;
}
%end

%hook SBFLockScreenDateView
%property (nonatomic, assign) SBFLockScreenDateSubtitleDateView *o_dateSubtitleView;
%property (nonatomic, assign) NSString *todayHeaderViewText;
%property (nonatomic, retain) UIImageView *conditionsImageView;
%property (nonatomic, retain) SBUILegibilityLabel *temperatureLabel;
-(void)didMoveToSuperview {
    %orig;
    if (!self.o_dateSubtitleView) return;
    if (self.o_dateSubtitleView.alternateDateLabel && !self.o_dateSubtitleView.weatherLabel) {
        CGRect alternateFrame = self.o_dateSubtitleView.alternateDateLabel.frame;
        SBUILegibilityLabel *originalLabel = self.o_dateSubtitleView.alternateDateLabel.label;
        lineDistance = alternateFrame.origin.y - alternateFrame.size.height;
        SBUILegibilityLabel *weatherLabel = [[SBUILegibilityLabel alloc] initWithFrame:CGRectZero];
        weatherLabel.legibilitySettings = [originalLabel legibilitySettings];
        weatherLabel.strength = [originalLabel strength];
        weatherLabel.font = [originalLabel font];
        weatherLabel.textAlignment = [originalLabel textAlignment];
        self.o_dateSubtitleView.weatherLabel = weatherLabel;
        [self.o_dateSubtitleView addSubview:self.o_dateSubtitleView.weatherLabel];
        
        if (![WALockscreenWidgetViewController sharedInstanceIfExists])
            [[WALockscreenWidgetViewController new] _setupWeatherModel];
        WALockscreenWidgetViewController *weatherController = [WALockscreenWidgetViewController sharedInstanceIfExists];
        self.conditionsImageView = [[UIImageView alloc] init];
        self.conditionsImageView.hidden = YES;
        self.temperatureLabel = [[SBUILegibilityLabel alloc] initWithFrame:CGRectZero];
        self.temperatureLabel.hidden = YES;
        self.temperatureLabel.legibilitySettings = [self._timeLabel legibilitySettings];
        WATodayPadViewStyle *style = [[WATodayPadViewStyle alloc] initWithFormat:2 orientation:0];
        [self.temperatureLabel setFont:[[style temperatureFont] retain]];
        [style release];
        [self addSubview:self.conditionsImageView];
        [self addSubview:self.temperatureLabel];
    }
    lockScreenDateView = self;
}

-(void)removeFromSuperview {
    if (lockScreenDateView == self) lockScreenDateView = nil;
    %orig;
}

-(void)dealloc {
    if (lockScreenDateView == self) lockScreenDateView = nil;
    %orig;
}

-(void)setCustomSubtitleView:(SBFLockScreenDateSubtitleView *)subtitleView {
    %orig;
    if (isChargeTimeETAEnabled
        && self.o_dateSubtitleView.alternateDateLabel
        && !subtitleView.estimateTimeLabel
        && [subtitleView isKindOfClass:[SBFLockScreenDateSubtitleView class]]
        && [[subtitleView string] containsString:@"%"]) {
        SBUILegibilityLabel *originalLabel = self.o_dateSubtitleView.alternateDateLabel.label;
        SBUILegibilityLabel *estimateTimeLabel = [[SBUILegibilityLabel alloc] initWithFrame:CGRectZero];
        estimateTimeLabel.legibilitySettings = [originalLabel legibilitySettings];
        estimateTimeLabel.strength = [originalLabel strength];
        estimateTimeLabel.font = [originalLabel font];
        estimateTimeLabel.textAlignment = [originalLabel textAlignment];
        subtitleView.estimateTimeLabel = estimateTimeLabel;
        [subtitleView addSubview:subtitleView.estimateTimeLabel];
        [subtitleView.estimateTimeLabel setString:BatteryChargingEstimatedTimeLocalizedString()];
        [subtitleView.estimateTimeLabel sizeToFit];
        [subtitleView updateEstimateTimeLabelFrame];
    }
}

%new
-(void)updateWeatherLabel {
    WALockscreenWidgetViewController *weatherLabelController = [WALockscreenWidgetViewController sharedInstanceIfExists];
    [%c(SBFLockScreenAlternateDateLabel) showAlternateDate];
    if (!self.o_dateSubtitleView) return;
    self.o_dateSubtitleView.weatherLabel.hidden = !o_showAlternateDate;
    if (o_showAlternateDate) {
        [self.o_dateSubtitleView.weatherLabel setString:
            isWeatherLabelEnabled ? [weatherLabelController lockScreenLabelString] : @""];
        [self.o_dateSubtitleView.weatherLabel sizeToFit];
    } else {
        [[self.o_dateSubtitleView.alternateDateLabel label] setString:
            isWeatherLabelEnabled ? [weatherLabelController lockScreenLabelString] : @""];
        [[self.o_dateSubtitleView.alternateDateLabel label] sizeToFit];
    }
}

%new
-(void)updateWeatherAbstractInfo {
    if (!isWeatherAbstractEnabled) return;
    WALockscreenWidgetViewController *weatherController = [WALockscreenWidgetViewController sharedInstanceIfExists];
    if (![weatherController dataReady]) return;
    [self.temperatureLabel setString:[weatherController _temperature]];
    [self.conditionsImageView setImage:[weatherController _conditionsImage]];
}

%new
-(void)updateWeatherAbstractFrame {
    WALockscreenWidgetViewController *weatherController = [WALockscreenWidgetViewController sharedInstanceIfExists];
    WATodayPadView *weatherView = [weatherController todayView];
    if (!weatherView) return;
    if (!isWeatherAbstractEnabled) {
        self.conditionsImageView.hidden = YES;
        self.temperatureLabel.hidden = YES;
        return;
    }
    BOOL IS_RTL = [UIApplication sharedApplication].userInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    BOOL isPhoneLandscape = UI_USER_INTERFACE_IDIOM() != UIUserInterfaceIdiomPad;
    if (isPhoneLandscape) {
        UIInterfaceOrientation orientation = [self _keyboardOrientation];
        isPhoneLandscape = orientation == UIInterfaceOrientationLandscapeLeft
                 || orientation == UIInterfaceOrientationLandscapeRight;
    }
    [self.temperatureLabel sizeToFit];
    CGFloat conditionsImageViewWidth = self.frame.size.height / 2,
            conditionsImageViewHeight = self.frame.size.height / 2,
            temperatureLabelHeight = self.frame.size.height / 2;
    if (isPhoneLandscape) {
        self.conditionsImageView.frame = CGRectMake(
            (IS_RTL ? self.temperatureLabel.frame.size.width : 0) + 0.5 * (self.alignmentPercent + 1) * (self.frame.size.width - conditionsImageViewWidth - (IS_RTL ? 0 : self.temperatureLabel.frame.size.width) - (IS_RTL ? self.temperatureLabel.frame.size.width : 0)),
            self.frame.size.height + (2 + o_showAlternateDate + isWeatherLabelEnabled) * lineDistance,
            conditionsImageViewWidth,
            conditionsImageViewHeight
        );
        self.temperatureLabel.frame = CGRectMake(
            IS_RTL ? (self.conditionsImageView.frame.origin.x - self.temperatureLabel.frame.size.width) : (self.conditionsImageView.frame.origin.x + conditionsImageViewWidth),
            self.frame.size.height + (2 + o_showAlternateDate + isWeatherLabelEnabled) * lineDistance,
            self.temperatureLabel.frame.size.width,
            temperatureLabelHeight
        );
    } else {
        self.conditionsImageView.frame = CGRectMake(
            IS_RTL ? self.frame.size.width - conditionsImageViewWidth : 0,
            0,
            conditionsImageViewWidth,
            conditionsImageViewHeight
        );
        self.temperatureLabel.frame = CGRectMake(
            IS_RTL ? self.frame.size.width - self.temperatureLabel.frame.size.width : 0,
            conditionsImageViewHeight,
            self.temperatureLabel.frame.size.width,
            temperatureLabelHeight
        );
    }
    self.conditionsImageView.hidden = NO;
    self.temperatureLabel.hidden = NO;
}

-(void)setLegibilitySettings:(id)arg1 {
    %orig;
    if (self.temperatureLabel) self.temperatureLabel.legibilitySettings = [self._timeLabel legibilitySettings];
}

- (CGFloat)alignmentPercent {
    if (!isWeatherAbstractEnabled) return %orig;
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) return %orig;
    if (![[WALockscreenWidgetViewController sharedInstanceIfExists] dataReady]) return %orig;
    UIInterfaceOrientation orientation = [self _keyboardOrientation];
    BOOL IS_RTL = [UIApplication sharedApplication].userInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    if (orientation == UIInterfaceOrientationLandscapeLeft
        || orientation == UIInterfaceOrientationLandscapeRight) return %orig;
    return IS_RTL ? -1.0 : 1.0;
}

- (void)setAlignmentPercent:(CGFloat)percent {
    if (!isWeatherAbstractEnabled) return %orig;
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) return %orig;
    if (![[WALockscreenWidgetViewController sharedInstanceIfExists] dataReady]) return %orig;
    UIInterfaceOrientation orientation = [self _keyboardOrientation];
    BOOL IS_RTL = [UIApplication sharedApplication].userInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    if (orientation == UIInterfaceOrientationLandscapeLeft
        || orientation == UIInterfaceOrientationLandscapeRight) return %orig;
    %orig(IS_RTL ? -1.0 : 1.0);
}

-(void)layoutSubviews {
    %orig;
    [self updateWeatherLabel];
    [self updateWeatherAbstractInfo];
    [self updateWeatherAbstractFrame];
    self.conditionsImageView.alpha = self._timeLabel.alpha;
    self.temperatureLabel.alpha = self._timeLabel.alpha;
}

-(void)setFrame:(CGRect)frame {
    if (!isWeatherAbstractEnabled || self != lockScreenDateView) return %orig;
    UIInterfaceOrientation orientation = [self _keyboardOrientation];
    if (orientation == UIInterfaceOrientationLandscapeLeft
        || orientation == UIInterfaceOrientationLandscapeRight) return %orig;
    if (frame.size.width >= self.superview.frame.size.width - 48) {
        CGFloat diff = frame.size.width - self.superview.frame.size.width + 48;
        frame.size.width -= diff;
        frame.origin.x += diff / 2.0;
    }
    %orig(frame);
}
%end

%hook SBFLockScreenAlternateDateLabel
+(BOOL)showAlternateDate {
    if (isNewOSVersion) o_showAlternateDate = %orig;
    else o_showAlternateDate = %orig;
    if (isWeatherLabelEnabled) return YES;
    return %orig;
}
%end

%hook NCNotificationListSectionRevealHintView
%property (nonatomic, retain) id /*WAGreetingView **/greetingView;
%property (nonatomic, retain) id _greetingViewController;
%property (nonatomic, retain) UIFont *_titleFont;
%new
-(NSString *)_labelText {
    if (!self.revealHintTitle) return nil;
    Class NCNotificationListLegibilityLabelCache_class = NSClassFromString(@"NCNotificationListLegibilityLabelCache");
    if (!NCNotificationListLegibilityLabelCache_class) return nil;
    NSDictionary *dict = (NSDictionary *)[[NCNotificationListLegibilityLabelCache_class sharedInstance] sectionHeaderViewLegibilityLabelDictionary];
    for (NSString *key in [dict allKeys]) {
        if (![dict[key] isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *_dict = (NSDictionary *)dict[key];
        for (NSString *_key in [_dict allKeys]) if (_dict[_key] == self.revealHintTitle) return key;
    }
    return nil;
}

%new
-(void)layoutGreetingView {
    if (!self.greetingView) return;
    id legibilitySettings = [self.revealHintTitle legibilitySettings];
    if (!legibilitySettings) legibilitySettings = self.legibilitySettings;
    WALockscreenWidgetViewController *weatherWidgetViewController = [WALockscreenWidgetViewController sharedInstanceIfExists];
    if (!isWeatherGreetingEnabled || ![weatherWidgetViewController dataReady]
        || (!isShowAllNotifications && isShowAllNotificationsWhenUnlocked && ![(SBFUserAuthenticationController *)[[%c(SBLockScreenManager) sharedInstanceIfExists] _userAuthController] isAuthenticated])) {
        [self.greetingView setHidden:YES];
        if ([self.revealHintTitle font] == self._titleFont) {
            [self.revealHintTitle setFont:[self _labelFont]];
            [self.revealHintTitle setString:[self _labelText]];
        }
        return;
    }
    [self.revealHintTitle setString:[self._greetingViewController _greetingString]];
    [self.revealHintTitle setFont:self._titleFont];
    [self.greetingView setHidden:NO];
    [self.greetingView setTodayModel:[weatherWidgetViewController todayModel]];
    [self.greetingView setLabelColor:[legibilitySettings primaryColor]];
    [self.greetingView setFrame:CGRectMake(0,
                                           self.revealHintTitle.frame.origin.y + self.revealHintTitle.frame.size.height,
                                           self.frame.size.width, self.frame.size.height)];
    [self.greetingView setupConstraints];
    [self.greetingView updateLabelColors];
    [self.greetingView updateView];
    [self.greetingView layoutSubviews];
}

-(void)didMoveToSuperview {
    %orig;
    revealHintView = self;
}

-(void)adjustForLegibilitySettingsChange:(id)arg1 {
    %orig;
    [self layoutGreetingView];
}

-(void)_configureRevealHintTitleIfNecessary {
    %orig;
    if (self.revealHintTitle && revealHintView == self && !self.greetingView) {
        Class WAGreetingView_class = NSClassFromString(@"WAGreetingView");
        if (!WAGreetingView_class) return;
        self.greetingView = [[WAGreetingView_class alloc] initWithColor:[self.legibilitySettings primaryColor]];
        if (self.revealHintTitle) [self.greetingView setAlpha:[self.revealHintTitle alpha]];
        else [self.greetingView setAlpha:self.alpha];
        [self addSubview:self.greetingView];
        
        Class DNDBedtimeGreetingViewController_class = NSClassFromString(@"CSDNDBedtimeGreetingViewController"); //iOS 13+
        if (!DNDBedtimeGreetingViewController_class) DNDBedtimeGreetingViewController_class = NSClassFromString(@"SBDashBoardDNDBedtimeGreetingViewController"); //iOS 12
        if (!DNDBedtimeGreetingViewController_class) return;
        self._greetingViewController = [[DNDBedtimeGreetingViewController_class alloc] init];
        
        self._titleFont = [UIFont preferredFontForTextStyle:@"UICTFontTextStyleTitle0"];
        
        [self _configureRevealHintTitleIfNecessary];
    }
    [self layoutGreetingView];
}

-(void)layoutSubviews {
    %orig;
    [self layoutGreetingView];
}

-(void)_updateAlpha {
    %orig;
    if (self.revealHintTitle) [self.greetingView setAlpha:[self.revealHintTitle alpha]];
    else [self.greetingView setAlpha:self.alpha];
}

-(void)removeFromSuperview {
    if (revealHintView == self) revealHintView = nil;
    if (self.greetingView) {
        [self.greetingView removeFromSuperview];
        [self.greetingView release];
        self.greetingView = nil;
    }
    if (self._greetingViewController) {
        [self._greetingViewController release];
        self._greetingViewController = nil;
    }
    %orig;
}

-(void)dealloc {
    if (revealHintView == self) revealHintView = nil;
    %orig;
}
%end

%hook NCNotificationStructuredListViewController
-(id)init {
    id _self = %orig;
    if (!notificationListViewController) notificationListViewController = _self;
    return _self;
}

%new
-(void)wl_showAllNotifications:(BOOL)isShow {
    [self revealNotificationHistory:isShow animated:YES];
}

-(void)dealloc {
    if (notificationListViewController == self) notificationListViewController = nil;
    %orig;
}
%end

%hook NCNotificationCombinedListViewController
-(id)init {
    id _self = %orig;
    if (!notificationListViewController) notificationListViewController = _self;
    return _self;
}

%new
-(void)wl_showAllNotifications:(BOOL)isShow {
    [self forceNotificationHistoryRevealed:isShow animated:YES];
}

-(void)dealloc {
    if (notificationListViewController == self) notificationListViewController = nil;
    %orig;
}
%end

%hook WALockscreenWidgetViewController
%property (nonatomic, assign) double updateInterval;
%property (nonatomic, assign) int updateCycle;
%property (nonatomic, assign) int updateCount;
%property (nonatomic, assign) BOOL ignoreUpdateCycle;
-(WALockscreenWidgetViewController *)init {
    WALockscreenWidgetViewController *_self = %orig;
    if (_self == [WALockscreenWidgetViewController sharedInstanceIfExists]) {
        _self.updateInterval = updateIntervalMinutes * 60.0;
        _self.updateCycle = updateCycle;
        _self.updateCount = -1;
    }
    return _self;
}

%new
-(BOOL)dataReady {
    return [[[self currentForecastModel] currentConditions] observationTime] != 0;
}

%new
-(NSString *)lockScreenLabelString {
    if (![self dataReady])
        return [[NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/Weather.framework"] localizedStringForKey:@"WEATHER_OFFLINE" value:nil table:@"WeatherFrameworkLocalizableStrings"];
    NSString *temperature = [self _temperature],
             *conditionsLine = [self shouldFakeWeather] ?
                               [self _conditionsLine] :
    WAConditionsLineStringFromCurrentForecasts([[self currentForecastModel] currentConditions]);
    return [NSString stringWithFormat:@"%@ %@", conditionsLine, temperature];
}

%new
-(void)updateWeatherViews {
    if ((isWeatherLabelEnabled || isWeatherAbstractEnabled) && lockScreenDateView) {
        //[[self todayView] layoutSubviews];
        [lockScreenDateView layoutSubviews];
    }
    if (weatherIconView) {
        [[weatherIconView liveWeatherView] updateWeatherDisplay];
        [weatherIconView updateImageAnimated:NO];
    }
    if (floatyDockWeatherIconView) {
        [[floatyDockWeatherIconView liveWeatherView] updateWeatherDisplay];
        [floatyDockWeatherIconView updateImageAnimated:NO];
    }
    if (!isWeatherGreetingEnabled || [self dataReady]) [revealHintView layoutSubviews];
}

-(void)setCurrentForecastModel:(WAForecastModel *)arg1 {
    %orig;
    [self updateWeatherViews];
}

-(void)_updateTimerFired:(NSTimer *)timer {
    if (self == [WALockscreenWidgetViewController sharedInstanceIfExists]) {
        if (!isWeatherLabelEnabled && !isWeatherAppIconEnabled && !isWeatherAbstractEnabled && !isWeatherGreetingEnabled) return;
        if (timer && [[UIApplication sharedApplication] _accessibilityFrontMostApplication]
            && ![[%c(SBLockScreenManager) sharedInstanceIfExists] isUILocked]) return;
        if (timer) {
            id backlightController = [%c(SBBacklightController) sharedInstanceIfExists];
            if (![backlightController screenIsOn] || [backlightController screenIsDim]) return;
        }
    }
    %orig;
}

-(void)_updateWithReason:(NSString *)reason {
    if (![[self todayModel] isKindOfClass:[WATodayAutoupdatingLocationModel class]]) return %orig;
    
    BOOL isUpdateLocation = self.updateCycle && !self.ignoreUpdateCycle && [WLPreferenceManager grandEnabled];
    if (isUpdateLocation
        && self.updateCount >= 0
        && self.updateCount % self.updateCycle != 0
        && [[NSDate date] timeIntervalSinceDate:[self updateLastCompletionDate]] < self.updateInterval * self.updateCycle) isUpdateLocation = NO;
    if (isUpdateLocation) {
        if (![[self todayModel] _weatherInUseAssertion])
            ((WATodayAutoupdatingLocationModel *)[self todayModel])._weatherInUseAssertion = [CLInUseAssertion newAssertionForBundleIdentifier:@"com.apple.weather" withReason:reason];
        self.updateCount = 0;
    }
    
    if (self.ignoreUpdateCycle) self.ignoreUpdateCycle = NO;
    else self.updateCount++;
    %orig;
    [self updateWeatherViews];
}

-(void)updateForChangedSettings:(id)arg1 {
    %orig;
    [self updateWeatherViews];
}

%new
-(void)updateForWidgetPresented:(BOOL)forced {
    if (forced) {
        if (self.updateCycle && self.updateCount >= 0) self.ignoreUpdateCycle = YES;
        [self _updateTimerFired:nil];
    }
    if (![self updateTimer]) {
        [self updateWeatherViews];
        return;
    }
    if ([self updateLastCompletionDate]
        && [[NSDate date] timeIntervalSinceDate:[self updateLastCompletionDate]] < self.updateInterval) {
        [self updateWeatherViews];
        return;
    }
    [self _updateTimerFired:[self updateTimer]];
}
%end

%hook WATodayAutoupdatingLocationModel
%property (nonatomic, retain) CLInUseAssertion *_weatherInUseAssertion;
-(void)_locationUpdateCompleted:(WFLocation *)location error:(NSError *)error completion:(id)completion {
    if (self != [[WALockscreenWidgetViewController sharedInstanceIfExists] todayModel]) return %orig;
    if (error && [self location]) {
        return %orig([self location], nil, completion);
    }
    if (!error && location && [self _weatherInUseAssertion]) {
        //[self._weatherInUseAssertion invalidate];
        [self._weatherInUseAssertion release];
        self._weatherInUseAssertion = nil;
    }
    %orig;
}
%end

%hook SpringBoard
-(void)frontDisplayDidChange:(id)newDisplay {
    %orig;
    [[WALockscreenWidgetViewController sharedInstanceIfExists] updateForWidgetPresented:NO];
}
%end

%hook SBLockScreenManager
-(void)_reallySetUILocked:(BOOL)locked {
    %orig;
    if (locked) [[WALockscreenWidgetViewController sharedInstanceIfExists] updateForWidgetPresented:NO];
}
%end

%hook SBFUserAuthenticationController
- (long long)_evaluateAuthenticationAttempt:(SBFAuthenticationRequest *)arg1 outError:(NSError **)arg2 {
    long long ret = %orig;
    if (ret == 2 && isShowAllNotificationsWhenUnlocked && notificationListViewController) {
        if (revealHintView) [revealHintView layoutGreetingView];
        [notificationListViewController wl_showAllNotifications:YES];
    }
    return ret;
}
%end

%hook SBBacklightController
-(void)animateBacklightToFactor:(float)factor duration:(double)duration source:(long long)source completion:(void(^)())completion {
    BOOL isNoPassword = [(SBFUserAuthenticationController *)[[%c(SBLockScreenManager) sharedInstanceIfExists] _userAuthController] isAuthenticated];
    if ((!isShowAllNotifications && (!isShowAllNotificationsWhenUnlocked || !isNoPassword))
        || (source != 15 && (!completion || factor != 1.0))) %orig;
    else {
        void (^_completion)() = ^{
            if (completion) completion();
            [notificationListViewController wl_showAllNotifications:YES];
        };
        %orig(factor, duration, source, _completion);
    }
    
    if (factor == 1.0) [[WALockscreenWidgetViewController sharedInstanceIfExists] updateForWidgetPresented:NO];
    else if (isShowAllNotifications || isShowAllNotificationsWhenUnlocked)
        if (notificationListViewController) [notificationListViewController wl_showAllNotifications:NO];
}
%end

%hook SBDashBoardTodayPageView
-(CGRect)frame {
    CGRect _frame = %orig;
    if (!o_showAlternateDate) return _frame;
    if (UI_USER_INTERFACE_IDIOM() != UIUserInterfaceIdiomPad) {
        UIInterfaceOrientation orientation = [self _keyboardOrientation];
        if (orientation == UIInterfaceOrientationLandscapeLeft
            || orientation == UIInterfaceOrientationLandscapeRight) return _frame;
    }
    return CGRectMake(_frame.origin.x, _frame.origin.y - (isWeatherLabelEnabled * lineDistance), _frame.size.width, _frame.size.height);
}

-(void)setFrame:(CGRect)frame {
    if (!o_showAlternateDate) return %orig;
    if (UI_USER_INTERFACE_IDIOM() != UIUserInterfaceIdiomPad) {
        UIInterfaceOrientation orientation = [self _keyboardOrientation];
        if (orientation == UIInterfaceOrientationLandscapeLeft
            || orientation == UIInterfaceOrientationLandscapeRight) return %orig;
    }
    return %orig(CGRectMake(frame.origin.x, frame.origin.y + (isWeatherLabelEnabled * lineDistance), frame.size.width, frame.size.height));
}
%end

%hook CSTodayPageView
-(CGRect)frame {
    CGRect _frame = %orig;
    if (!o_showAlternateDate) return _frame;
    if (UI_USER_INTERFACE_IDIOM() != UIUserInterfaceIdiomPad) {
        UIInterfaceOrientation orientation = [self _keyboardOrientation];
        if (orientation == UIInterfaceOrientationLandscapeLeft
            || orientation == UIInterfaceOrientationLandscapeRight) return _frame;
    }
    return CGRectMake(_frame.origin.x, _frame.origin.y - (isWeatherLabelEnabled * lineDistance), _frame.size.width, _frame.size.height);
}

-(void)setFrame:(CGRect)frame {
    if (!o_showAlternateDate) return %orig;
    if (UI_USER_INTERFACE_IDIOM() != UIUserInterfaceIdiomPad) {
        UIInterfaceOrientation orientation = [self _keyboardOrientation];
        if (orientation == UIInterfaceOrientationLandscapeLeft
            || orientation == UIInterfaceOrientationLandscapeRight) return %orig;
    }
    return %orig(CGRectMake(frame.origin.x, frame.origin.y + (isWeatherLabelEnabled * lineDistance), frame.size.width, frame.size.height));
}
%end

%hook SBDashBoardMainPageView
-(CGRect)frame {
    CGRect _frame = %orig;
    if (!o_showAlternateDate) return _frame;
    if (UI_USER_INTERFACE_IDIOM() != UIUserInterfaceIdiomPad) {
        UIInterfaceOrientation orientation = [self _keyboardOrientation];
        if (orientation == UIInterfaceOrientationLandscapeLeft
            || orientation == UIInterfaceOrientationLandscapeRight) return _frame;
    }
    return CGRectMake(_frame.origin.x, _frame.origin.y - (isWeatherLabelEnabled * lineDistance), _frame.size.width, _frame.size.height);
}

-(void)setFrame:(CGRect)frame {
    if (!o_showAlternateDate) return %orig;
    if (UI_USER_INTERFACE_IDIOM() != UIUserInterfaceIdiomPad) {
        UIInterfaceOrientation orientation = [self _keyboardOrientation];
        if (orientation == UIInterfaceOrientationLandscapeLeft
            || orientation == UIInterfaceOrientationLandscapeRight) return %orig;
    }
    return %orig(CGRectMake(frame.origin.x, frame.origin.y + (isWeatherLabelEnabled * lineDistance), frame.size.width, frame.size.height));
}
%end

%hook CSCoverSheetViewBase
%property(assign) BOOL isMainPageView;
-(void)didMoveToSuperview {
    %orig;
    [self setIsMainPageView:[NSStringFromClass([[self superview] class]) isEqualToString:@"CSMainPageView"]];
}

-(CGRect)frame {
    CGRect _frame = %orig;
    if (![self isMainPageView]) return _frame;
    if (!o_showAlternateDate) return _frame;
    if (UI_USER_INTERFACE_IDIOM() != UIUserInterfaceIdiomPad) {
        UIInterfaceOrientation orientation = [self _keyboardOrientation];
        if (orientation == UIInterfaceOrientationLandscapeLeft
            || orientation == UIInterfaceOrientationLandscapeRight) return _frame;
    }
    return CGRectMake(_frame.origin.x, _frame.origin.y - (isWeatherLabelEnabled * lineDistance), _frame.size.width, _frame.size.height);
}

-(void)setFrame:(CGRect)frame {
    if (![self isMainPageView]) return %orig;
    if (!o_showAlternateDate) return %orig;
    if (UI_USER_INTERFACE_IDIOM() != UIUserInterfaceIdiomPad) {
        UIInterfaceOrientation orientation = [self _keyboardOrientation];
        if (orientation == UIInterfaceOrientationLandscapeLeft
            || orientation == UIInterfaceOrientationLandscapeRight) return %orig;
    }
    return %orig(CGRectMake(frame.origin.x, frame.origin.y + (isWeatherLabelEnabled * lineDistance), frame.size.width, frame.size.height));
}
%end

%subclass SBLiveWeatherIconImageView : SBIconImageView
%property (nonatomic, retain) SBLiveWeatherIconWeatherView *liveWeatherView;
%new
-(void)weatherIconCleanUp {
    if (![[self.icon leafIdentifier] isEqualToString:@"com.apple.weather"]) return;
    if (self.layer.contents == nil) [self updateImageAnimated:NO];
    
    int recycleFlag = 0;
    if ([self respondsToSelector:@selector(location)]) { //iOS 13 or up
        NSString *location = self.location;
        if ([(NSString *)location isEqualToString:@"SBIconLocationRoot"]
            || [(NSString *)location isEqualToString:@"SBIconLocationDock"]
            || [(NSString *)location isEqualToString:@"SBIconLocationFolder"]
            || [(NSString *)location isEqualToString:@"SBIconLocationFloatingDock"]) recycleFlag = 1;
        else if ([(NSString *)location isEqualToString:@"SBIconLocationFloatingDockSuggestions"]) recycleFlag = 2;
        else recycleFlag = 3;
    } else {
        NSUInteger location = MSHookIvar<NSUInteger>(self, "_location");
        if (location == 1 || location == 3 || location == 6) recycleFlag = 1;
        else if (location == 4) recycleFlag = 2;
        else recycleFlag = 3;
    }
    
    if (recycleFlag == 1) {
        //if (!weatherIconView)
            weatherIconView = self;
    } else if (recycleFlag == 2) {
        //if (!floatyDockWeatherIconView)
            floatyDockWeatherIconView = self;
    } else if (recycleFlag == 3) {
        if (weatherIconView == self) weatherIconView = nil;
        if (floatyDockWeatherIconView == self) floatyDockWeatherIconView = nil;
        if (self.liveWeatherView) {
            [self.liveWeatherView removeFromSuperview];
            [self.liveWeatherView release];
            self.liveWeatherView = nil;
        }
        [self updateImageAnimated:NO];
    }
}

-(void)didMoveToSuperview {
    %orig;
    if ([self.superview isKindOfClass:%c(SBIconView)] || [self.superview.superview isKindOfClass:%c(SBIconView)]) {
        if (!self.liveWeatherView) {
            self.liveWeatherView = [[SBLiveWeatherIconWeatherView alloc] initWithFrame:CGRectZero];
            self.liveWeatherView.iconImageView = self;
            self.liveWeatherView.translatesAutoresizingMaskIntoConstraints = NO;
            [self addSubview:self.liveWeatherView];
            self.liveWeatherView.clipsToBounds = YES;
            [self.liveWeatherView.leftAnchor constraintEqualToAnchor:self.leftAnchor].active = YES;
            [self.liveWeatherView.rightAnchor constraintEqualToAnchor:self.rightAnchor].active = YES;
            [self.liveWeatherView.topAnchor constraintEqualToAnchor:self.topAnchor].active = YES;
            [self.liveWeatherView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor].active = YES;
        }
        [self updateMask];
        [self weatherIconCleanUp];
    }
}

-(UIImage *)squareContentsImage {
    UIImage *image = [[self liveWeatherView] backgroundImage];
    if (!image) return %orig;
    return image;
}

-(UIImage *)contentsImage {
    UIImage *image = [[self liveWeatherView] backgroundImage];
    if (!image) return %orig;
    
    if ([self respondsToSelector:@selector(_currentOverlayImage)]) {
        UIImage *maskImg = [UIImage imageWithData:UIImageJPEGRepresentation([self _currentOverlayImage], 1)];

        CGImageRef maskRef = maskImg.CGImage;
        CGImageRef mask = CGImageMaskCreate(CGImageGetWidth(maskRef), CGImageGetHeight(maskRef), CGImageGetBitsPerComponent(maskRef), CGImageGetBitsPerPixel(maskRef), CGImageGetBytesPerRow(maskRef), CGImageGetDataProvider(maskRef), NULL, false);
        CGImageRef masked = CGImageCreateWithMask(image.CGImage, mask);

        return [UIImage imageWithCGImage:masked];
    }

    CALayer *imageLayer = [CALayer layer];
    imageLayer.frame = CGRectMake(0, 0, image.size.width, image.size.height);
    imageLayer.contents = (id)image.CGImage;

    imageLayer.masksToBounds = YES;
    imageLayer.cornerRadius = self.continuousCornerRadius;

    UIGraphicsBeginImageContextWithOptions(self.bounds.size, NO, 2.0);
    [imageLayer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *roundedImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    return roundedImage;
}

%new
-(void)updateMask {
    NSBundle *bundle = [NSBundle bundleWithPath:[NSString stringWithFormat:@"/System/Library/PrivateFrameworks/MobileIcons.framework"]];
    UIImage *maskImage = [UIImage imageNamed:@"AppIconMask" inBundle:bundle];

    CALayer *mask = [CALayer layer];
    mask.contents = (id)[maskImage CGImage];
    mask.frame = CGRectMake(0, 0, maskImage.size.width, maskImage.size.height);
    self.liveWeatherView.layer.mask = mask;
    self.liveWeatherView.layer.masksToBounds = YES;
}

-(void)layoutSubviews {
    [self weatherIconCleanUp];
    if (self.liveWeatherView) [self.liveWeatherView layoutSubviews];
    %orig;
}

-(void)setBrightness:(double)brightness {
    %orig;
    [self weatherIconCleanUp];
    if (self.liveWeatherView) self.liveWeatherView.alpha = self.brightness;
}

-(void)setPaused:(BOOL)paused {
    %orig;
    if (!paused) [self weatherIconCleanUp];
}

-(void)prepareForReuse {
    %orig;
    [self weatherIconCleanUp];
}

-(void)dealloc {
    if (self.liveWeatherView) {
        [self.liveWeatherView removeFromSuperview];
        [self.liveWeatherView release];
        self.liveWeatherView = nil;
    }
    if (weatherIconView == self) weatherIconView = nil;
    if (floatyDockWeatherIconView == self) floatyDockWeatherIconView = nil;
    %orig;
}
%end

%subclass SBLiveWeatherIcon : SBApplicationIcon
/*
 * subclass our own application icon and return a custom subclassed icon view
 */
-(Class)iconImageViewClassForLocation:(int)arg1 {
    return NSClassFromString(@"SBLiveWeatherIconImageView");
}
%end

%hook SBApplicationInfo
-(Class)iconClass {
    if([self.bundleIdentifier isEqualToString:@"com.apple.weather"]) {
        return NSClassFromString(@"SBLiveWeatherIcon");
    }
    return %orig;
}
%end

%hook SBIconView
-(void)_setIcon:(id)icon animated:(BOOL)animated {
    %orig;
    /*
     * This happens during icon recycling so update rings to keep them fresh
     */
    if ([[self.icon leafIdentifier] isEqualToString:@"com.apple.weather"]
        && [[icon leafIdentifier] isEqualToString:[self.icon leafIdentifier]]) {
        [self _iconImageView].layer.contents = nil;
    }
}
%end

%hook SBIconController
-(BOOL)iconViewDisplaysBadges:(SBIconView *)iconView {
    if (isWeatherAppIconShowBadge && iconView && [iconView.icon.leafIdentifier isEqualToString:@"com.apple.weather"]) return YES;
    return %orig;
}
%end

%hook SBHIconManager
-(BOOL)iconViewDisplaysBadges:(SBIconView *)iconView {
    if (isWeatherAppIconShowBadge && iconView && [iconView.icon.leafIdentifier isEqualToString:@"com.apple.weather"]) return YES;
    return %orig;
}
%end

%ctor {
    if (@available(iOS 11, *)) isNewOSVersion = true;
    int token;
    notify_register_dispatch_and_run_once("in.net.mario.tweak.weatherlabel/prefs", &token, dispatch_get_main_queue(), ^(int token) {
        NSDictionary *prefs = nil;
        CFArrayRef keyList = CFPreferencesCopyKeyList(CFSTR("in.net.mario.tweak.weatherlabelprefs"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        if(keyList) {
            prefs = (NSDictionary *)CFPreferencesCopyMultiple(keyList, CFSTR("in.net.mario.tweak.weatherlabelprefs"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
            if(!prefs) prefs = [NSDictionary dictionaryWithContentsOfFile:@"/private/var/mobile/Library/Preferences/in.net.mario.tweak.weatherlabelprefs.plist"];
            CFRelease(keyList);
        }
        if (prefs) {
            NSValue *value = [prefs objectForKey:@"chargetimeeta"];
            if (value && isChargeTimeETAEnabled != [value boolValue])
                [WLPreferenceManager setChargeTimeETAEnabled:[value boolValue]];
            value = [prefs objectForKey:@"weatherlabel"];
            if (value && isWeatherLabelEnabled != [value boolValue])
                [WLPreferenceManager setWeatherLabelEnabled:[value boolValue]];
            value = [prefs objectForKey:@"weatherappicon"];
            if (value && isWeatherAppIconEnabled != [value boolValue])
                [WLPreferenceManager setWeatherAppIconEnabled:[value boolValue]];
            value = [prefs objectForKey:@"iconshowtemp"];
            if (value && isWeatherAppIconShowTemp != [value boolValue])
                [WLPreferenceManager setWeatherAppIconShowTemperature:[value boolValue]];
            value = [prefs objectForKey:@"badgeshowtemp"];
            if (value && isWeatherAppIconShowBadge != [value boolValue])
                [WLPreferenceManager setWeatherAppIconShowBadge:[value boolValue]];
            value = [prefs objectForKey:@"weatherabstract"];
            if (value && isWeatherAbstractEnabled != [value boolValue])
                [WLPreferenceManager setWeatherAbstractEnabled:[value boolValue]];
            value = [prefs objectForKey:@"weathergreeting"];
            if (value && isWeatherGreetingEnabled != [value boolValue])
                [WLPreferenceManager setWeatherGreetingEnabled:[value boolValue]];
            value = [prefs objectForKey:@"showallplatters"];
            if (value && isShowAllNotifications != [value boolValue])
                [WLPreferenceManager setShowAllNotifications:[value boolValue]];
            value = [prefs objectForKey:@"showallplatters2"];
            if (value && isShowAllNotificationsWhenUnlocked != [value boolValue])
                [WLPreferenceManager setShowAllNotificationsWhenUnlocked:[value boolValue]];
            value = [prefs objectForKey:@"updateinterval"];
            if (value) [WLPreferenceManager setUpdateInterval:[value doubleValue]];
            value = [prefs objectForKey:@"updatecycle"];
            if (value) [WLPreferenceManager setUpdateCycle:[value intValue]];
        }
    });
}
