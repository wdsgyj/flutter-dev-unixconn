#include "include/unixconn_dart_api.h"

#include <string.h>

typedef struct {
  const char* name;
  void (*function)(void);
} UnixconnDartApiEntry;

typedef struct {
  const int major;
  const int minor;
  const UnixconnDartApiEntry* const functions;
} UnixconnDartApi;

Dart_PostCObject_Type Dart_PostCObject_DL = NULL;

intptr_t Dart_InitializeApiDL(void* data) {
  UnixconnDartApi* api = (UnixconnDartApi*)data;
  if (api == NULL || api->major != UNIXCONN_DART_API_DL_MAJOR_VERSION) {
    return -1;
  }

  Dart_PostCObject_DL = NULL;
  const UnixconnDartApiEntry* entry = api->functions;
  while (entry != NULL && entry->name != NULL) {
    if (strcmp(entry->name, "Dart_PostCObject") == 0) {
      Dart_PostCObject_DL = (Dart_PostCObject_Type)entry->function;
      break;
    }
    entry++;
  }

  return Dart_PostCObject_DL == NULL ? -1 : 0;
}
