#ifndef UNIXCONN_PROXY_H_
#define UNIXCONN_PROXY_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if __GNUC__ >= 4
#define UNIXCONN_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#else
#define UNIXCONN_EXPORT
#endif

UNIXCONN_EXPORT int64_t unixconn_start_proxy(char* socket_path,
                                             int32_t timeout_ms,
                                             int64_t dart_port,
                                             int32_t* error_code,
                                             char** error_message);
UNIXCONN_EXPORT int32_t unixconn_stop_proxy(int64_t handle,
                                            int32_t* error_code,
                                            char** error_message);
UNIXCONN_EXPORT intptr_t unixconn_initialize_dart_api(void* data);
UNIXCONN_EXPORT void unixconn_free_string(char* string);

#ifdef __cplusplus
}
#endif

#endif  // UNIXCONN_PROXY_H_
