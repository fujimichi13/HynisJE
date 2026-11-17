#include <assert.h>
#include <stdio.h>
#include "gl4metal_session.h"

static int initializations, binds, finishes;
static unsigned char initialization_succeeds = 1;
static void *bound_layer;
static unsigned char initialize(void) { ++initializations; return initialization_succeeds; }
static void bind_layer(void *layer) { ++binds; bound_layer = layer; }
static void finish(void) { ++finishes; }

int main(void) {
    gl4metal_session s = { .initialize = initialize, .make_current = bind_layer, .finish = finish };
    int window, second_window, layer, replacement_layer;
    // Window creation must not initialize the backend on the UI thread.
    assert(!gl4metal_session_create(&s, &window, NULL));
    assert(initializations == 0);
    assert(gl4metal_session_create(&s, &second_window, &window));
    assert(gl4metal_session_create(&s, &second_window, NULL));
    assert(s.context == &window);
    assert(!gl4metal_session_bind(&s, NULL, 1, NULL));
    assert(gl4metal_session_bind(&s, &window, 1, NULL));
    assert(gl4metal_session_bind(&s, &second_window, 1, &layer));
    assert(initializations == 0 && binds == 0);

    // A failed first initialization can be retried on the real render thread.
    initialization_succeeds = 0;
    assert(gl4metal_session_bind(&s, &window, 1, &layer));
    assert(!s.initialized && !s.bound && binds == 0);
    initialization_succeeds = 1;
    assert(!gl4metal_session_bind(&s, &window, 2, &layer));
    assert(s.initialized && s.owner == 2 && s.bound);
    assert(initializations == 2 && binds == 1 && bound_layer == &layer);
    assert(!gl4metal_session_bind(&s, &window, 2, &replacement_layer));
    assert(initializations == 2 && binds == 2 && bound_layer == &replacement_layer);

    // A foreign thread's unbind must leave the rendering thread alone.
    assert(!gl4metal_session_bind(&s, NULL, 3, NULL));
    assert(s.bound && finishes == 0);
    assert(gl4metal_session_bind(&s, &window, 3, &layer));
    assert(gl4metal_session_destroy(&s, &window, 3));
    assert(s.bound && s.context == &window && finishes == 0);
    assert(!gl4metal_session_bind(&s, NULL, 2, NULL));
    assert(!s.bound && finishes == 1);
    assert(gl4metal_session_bind(&s, &window, 3, &layer));
    assert(!gl4metal_session_bind(&s, &window, 2, &layer));
    assert(initializations == 2);
    assert(!gl4metal_session_destroy(&s, &window, 2));
    assert(finishes == 2 && !s.context && !s.bound && s.initialized);
    assert(gl4metal_session_create(&s, &window, NULL));
    assert(gl4metal_session_destroy(&s, &second_window, 2));
    assert(!gl4metal_session_destroy(&s, NULL, 2));

    // Unused windows can be destroyed/recreated without claiming a GL thread.
    s = (gl4metal_session){ .initialize = initialize, .make_current = bind_layer, .finish = finish };
    assert(!gl4metal_session_create(&s, &window, NULL));
    assert(!gl4metal_session_destroy(&s, &window, 1));
    assert(!gl4metal_session_create(&s, &second_window, NULL));
    assert(!gl4metal_session_bind(&s, &second_window, 4, &layer));
    assert(!gl4metal_session_bind(&s, NULL, 4, NULL));
    assert(!gl4metal_session_destroy(&s, &second_window, 1));
    puts("gl4metal session: all lifecycle checks passed");
    return 0;
}
