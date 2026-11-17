#pragma once

#include <stdlib.h>
#include "gl_bridge.h"
#include "osm_bridge.h"

typedef union {
    gl_render_window_t gl;
    osm_render_window_t osm;
} basic_render_window_t;

typedef basic_render_window_t* (*br_init_context_t)(basic_render_window_t* share);
typedef void (*br_make_current_t)(basic_render_window_t* bundle);
typedef basic_render_window_t* (*br_get_current_t)();

extern bool (*br_init)();
extern br_init_context_t br_init_context;
extern br_make_current_t br_make_current;
extern bool (*br_destroy_context)(basic_render_window_t*);
//br_get_current_t br_get_current = NULL;
extern void (*br_swap_buffers)();
extern void (*br_setup_window)();
extern void (*br_swap_interval)(int swapInterval);
extern void (*br_terminate)();

extern __thread basic_render_window_t* currentBundle;
extern __thread const char *bridgeError;
static inline basic_render_window_t* br_get_current() {
    return currentBundle;
}
