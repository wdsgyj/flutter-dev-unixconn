#import "include/UnixconnPlugin.h"

#import <UIKit/UIKit.h>

#import "include/unixconn_proxy.h"

static NSDictionary<NSString*, NSNumber*>* UnixconnCopyNativeApiAddresses(void) {
  return @{
    @"initializeDartApi" : @((unsigned long long)(uintptr_t)&unixconn_initialize_dart_api),
    @"startProxy" : @((unsigned long long)(uintptr_t)&unixconn_start_proxy),
    @"stopProxy" : @((unsigned long long)(uintptr_t)&unixconn_stop_proxy),
    @"freeString" : @((unsigned long long)(uintptr_t)&unixconn_free_string),
  };
}

@implementation UnixconnPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  FlutterMethodChannel* channel =
      [FlutterMethodChannel methodChannelWithName:@"unixconn"
                                  binaryMessenger:[registrar messenger]];
  UnixconnPlugin* instance = [[UnixconnPlugin alloc] init];
  [registrar addMethodCallDelegate:instance channel:channel];
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
  if ([@"getNativeApiAddresses" isEqualToString:call.method]) {
    result(UnixconnCopyNativeApiAddresses());
    return;
  }
  if ([@"getPlatformVersion" isEqualToString:call.method]) {
    result([@"iOS " stringByAppendingString:[[UIDevice currentDevice] systemVersion]]);
    return;
  }
  result(FlutterMethodNotImplemented);
}

@end
