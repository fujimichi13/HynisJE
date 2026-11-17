#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// gl4metal's current ABI has process-wide initialization but thread-local GL
// state. Keep ownership for the library's entire lifetime, including unbinds.
// The caller serializes access and supplies the rendering thread's identity.
typedef struct {
    unsigned char (*initialize)(void);
    void (*make_current)(void *layer);
    void (*finish)(void);
    void *context;
    uintptr_t owner;
    bool initialized;
    bool bound;
} gl4metal_session;

static inline const char *gl4metal_session_create(gl4metal_session *s, void *context, void *share) {
    if (share) return "gl4metal does not support shared contexts";
    if (s->context) return "gl4metal supports only one live context";
    if (s->initialized) return "gl4metal cannot reset a destroyed context; restart the game";
    s->context = context;
    return NULL;
}

static inline const char *gl4metal_session_bind(gl4metal_session *s, void *context,
                                             uintptr_t thread, void *layer) {
    // Unbinding a thread with no current context must not touch another thread.
    if (!context && (!s->initialized || s->owner != thread || !s->bound)) return NULL;
    if (s->initialized && s->owner != thread)
        return "gl4metal cannot migrate a context to another rendering thread";
    if (!context) {
        s->finish();
        s->bound = false;
        return NULL;
    }
    if (context != s->context) return "Invalid gl4metal context";
    if (!layer) return "gl4metal requires a CAMetalLayer";
    if (!s->initialized) {
        if (!s->initialize()) return "gl4metal failed to initialize the Metal device";
        s->owner = thread;
        s->initialized = true;
    }
    s->make_current(layer);
    s->bound = true;
    return NULL;
}

static inline const char *gl4metal_session_destroy(gl4metal_session *s, void *context, uintptr_t thread) {
    if (!context) return NULL;
    if (context != s->context) return "Invalid gl4metal context";
    if (s->bound && s->owner != thread)
        return "Unbind gl4metal on its rendering thread before destroying the window";
    if (s->bound) s->finish();
    s->bound = false;
    s->context = NULL;
    // No backend destruction/reset API exists. Preserve owner and initialized.
    return NULL;
}
