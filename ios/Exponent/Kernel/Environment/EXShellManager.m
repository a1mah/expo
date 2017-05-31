// Copyright 2015-present 650 Industries. All rights reserved.

#import "EXAnalytics.h"
#import "EXKernelUtil.h"
#import "ExpoKit.h"
#import "EXShellManager.h"

#import <Crashlytics/Crashlytics.h>
#import <React/RCTUtils.h>

NSString * const kEXShellBundleResourceName = @"shell-app";
NSString * const kEXShellManifestResourceName = @"shell-app-manifest";

@implementation EXShellManager

+ (nonnull instancetype)sharedInstance
{
  static EXShellManager *theManager;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    if (!theManager) {
      theManager = [[EXShellManager alloc] init];
    }
  });
  return theManager;
}

- (id)init
{
  if (self = [super init]) {
    [self _loadConfig];
  }
  return self;
}

- (BOOL)isShellUrlScheme:(NSString *)scheme
{
  return (_urlScheme && [scheme isEqualToString:_urlScheme]);
}

- (BOOL)hasUrlScheme
{
  return (_urlScheme != nil);
}

#pragma mark internal

- (void)_reset
{
  _isShell = NO;
  _shellManifestUrl = nil;
  _usesPublishedManifest = YES;
  _urlScheme = nil;
  _isRemoteJSEnabled = YES;
  _allManifestUrls = @[];
}

- (void)_loadConfig
{
  [self _reset];
  
  // load EXShell.plist
  NSString *configPath = [[NSBundle mainBundle] pathForResource:@"EXShell" ofType:@"plist"];
  NSDictionary *shellConfig = (configPath) ? [NSDictionary dictionaryWithContentsOfFile:configPath] : [NSDictionary dictionary];
  
  // load EXBuildConstants.plist
  NSString *buildConstantsPath = [[NSBundle mainBundle] pathForResource:@"EXBuildConstants" ofType:@"plist"];
  NSDictionary *constantsConfig = (buildConstantsPath) ? [NSDictionary dictionaryWithContentsOfFile:buildConstantsPath] : [NSDictionary dictionary];
  
  NSMutableArray *allManifestUrls = [NSMutableArray array];

  if (shellConfig) {
    _isShell = [shellConfig[@"isShell"] boolValue];
    if (_isShell) {
      // configure published shell url
      [self _loadProductionUrlFromConfig:shellConfig];
      if (_shellManifestUrl) {
        [allManifestUrls addObject:_shellManifestUrl];
      }
#if DEBUG
      // local shell development: point shell manifest url at local development url
      [self _loadDevelopmentUrlAndSchemeFromConfig:constantsConfig fallbackToShellConfig:shellConfig];
      if (_shellManifestUrl) {
        [allManifestUrls addObject:_shellManifestUrl];
      }
#else
      // load shell app configured url scheme (prod only - in dev we expect the `exp<udid>` scheme)
      [self _loadProductionUrlScheme];
#endif
      RCTAssert((_shellManifestUrl), @"This app is configured to be a standalone app, but does not specify a standalone experience url.");
      
      // load everything else from EXShell
      [self _loadMiscShellPropertiesWithConfig:shellConfig];

      [self _setAnalyticsProperties];
    }
  }
  _allManifestUrls = allManifestUrls;
}

- (void)_loadProductionUrlFromConfig:(NSDictionary *)shellConfig
{
  _shellManifestUrl = shellConfig[@"manifestUrl"];
  if ([ExpoKit sharedInstance].publishedManifestUrlOverride) {
    _shellManifestUrl = [ExpoKit sharedInstance].publishedManifestUrlOverride;
  }
}

- (void)_loadDevelopmentUrlAndSchemeFromConfig:(NSDictionary *)config fallbackToShellConfig:(NSDictionary *)shellConfig
{
  NSString *developmentUrl = nil;
  if (config && config[@"developmentUrl"]) {
    developmentUrl = config[@"developmentUrl"];
  } else if (shellConfig && shellConfig[@"developmentUrl"]) {
    DDLogWarn(@"Configuring your ExpoKit `developmentUrl` in EXShell.plist is deprecated, specify this in EXBuildConstants.plist instead.");
    developmentUrl = shellConfig[@"developmentUrl"];
  }
  
  if (developmentUrl) {
    _shellManifestUrl = developmentUrl;
    NSURLComponents *components = [NSURLComponents componentsWithURL:[NSURL URLWithString:_shellManifestUrl] resolvingAgainstBaseURL:YES];
    if ([self _isValidShellUrlScheme:components.scheme]) {
      _urlScheme = components.scheme;
    }
    _usesPublishedManifest = NO;
  } else {
    NSAssert(NO, @"No development url was configured. You must open this project with Expo before running it from XCode.");
  }
}

- (void)_loadProductionUrlScheme
{
  NSDictionary *iosConfig = [[NSBundle mainBundle] infoDictionary];
  if (iosConfig[@"CFBundleURLTypes"]) {
    // if the shell app has a custom url scheme, read that.
    // this was configured when the shell app was built.
    NSArray *urlTypes = iosConfig[@"CFBundleURLTypes"];
    if (urlTypes && urlTypes.count) {
      NSDictionary *urlType = urlTypes[0];
      NSArray *urlSchemes = urlType[@"CFBundleURLSchemes"];
      if (urlSchemes) {
        for (NSString *urlScheme in urlSchemes) {
          if ([self _isValidShellUrlScheme:urlScheme]) {
            _urlScheme = urlScheme;
            break;
          }
        }
      }
    }
  }
}

- (void)_loadMiscShellPropertiesWithConfig:(NSDictionary *)shellConfig
{
  _isManifestVerificationBypassed = [shellConfig[@"isManifestVerificationBypassed"] boolValue];
  _isRemoteJSEnabled = (shellConfig[@"isRemoteJSEnabled"] == nil)
    ? YES
    : [shellConfig[@"isRemoteJSEnabled"] boolValue];
  // other shell config goes here
}

- (void)_setAnalyticsProperties
{
  [[EXAnalytics sharedInstance] setUserProperties:@{ @"INITIAL_URL": _shellManifestUrl }];
  [CrashlyticsKit setObjectValue:_shellManifestUrl forKey:@"initial_url"];
#ifdef EX_DETACHED
  [[EXAnalytics sharedInstance] setUserProperties:@{ @"IS_DETACHED": @YES }];
#endif
}

- (BOOL)_isValidShellUrlScheme:(NSString *)urlScheme
{
  // don't allow shell apps to intercept exp links
  return (urlScheme && urlScheme.length && ![urlScheme hasPrefix:@"exp"]);
}

@end
