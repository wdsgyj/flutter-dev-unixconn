#ifndef UNIXCONN_DART_BRIDGE_H_
#define UNIXCONN_DART_BRIDGE_H_

#include <stdint.h>

#include "unixconn_dart_api.h"
#include "unixconn_proxy.h"

#ifdef __cplusplus
extern "C" {
#endif

UNIXCONN_EXPORT intptr_t unixconn_initialize_dart_api(void* data);
int unixconn_post_trace_json(Dart_Port_DL port, const char* message);

#ifdef __cplusplus
}
#endif

#endif  // UNIXCONN_DART_BRIDGE_H_
