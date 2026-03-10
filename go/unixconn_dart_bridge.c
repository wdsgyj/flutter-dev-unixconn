#include "include/unixconn_dart_bridge.h"

#include <stddef.h>

UNIXCONN_EXPORT intptr_t unixconn_initialize_dart_api(void* data) {
  return Dart_InitializeApiDL(data);
}

int unixconn_post_trace_json(Dart_Port_DL port, const char* message) {
  if (port == 0 || message == NULL || Dart_PostCObject_DL == NULL) {
    return 0;
  }

  Dart_CObject dart_message;
  dart_message.type = Dart_CObject_kString;
  dart_message.value.as_string = message;
  return Dart_PostCObject_DL(port, &dart_message) ? 1 : 0;
}
