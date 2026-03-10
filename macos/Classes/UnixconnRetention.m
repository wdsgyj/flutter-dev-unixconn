#import <Foundation/Foundation.h>

#import "include/unixconn_proxy.h"

// Keep the cgo-exported symbols strongly referenced so CocoaPods static linking
// does not strip them before Dart FFI resolves them from the process image.
__attribute__((used)) static void* const kUnixconnKeepAliveSymbols[] = {
    (void*)&unixconn_initialize_dart_api,
    (void*)&unixconn_start_proxy,
    (void*)&unixconn_stop_proxy,
    (void*)&unixconn_free_string,
};

@interface UnixconnRetention : NSObject
@end

@implementation UnixconnRetention

+ (void)load {
  (void)kUnixconnKeepAliveSymbols;
}

@end
