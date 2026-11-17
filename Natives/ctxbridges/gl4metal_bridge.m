#import "SurfaceViewController.h"
#import <QuartzCore/CAMetalLayer.h>
#include <dlfcn.h>
#include <pthread.h>
#include "utils.h"
#include "bridge_tbl.h"
#include "gl4metal_bridge.h"
#include "gl4metal_session.h"

static void *library;
static gl4metal_session session;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static void (*swapBuffers)(void);
static void (*swapInterval)(int);
static __thread void *boundLayer;

static bool metal_init(void) {
    if (library) return true;
    // Never search RTLD_DEFAULT: ANGLE and the other renderers export the same
    // GL names. Keep this handle alive while LWJGL caches function pointers.
    void *candidate = dlopen(gl4metalLibraryPath().fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL | RTLD_FIRST);
    if (!candidate) {
        bridgeError = "Could not load Frameworks/libgl4metal.dylib; see the launcher log";
        NSLog(@"GL4MetalBridge: dlopen failed: %s", dlerror());
        return false;
    }
#define LOAD(field, symbol) do { \
    field = dlsym(candidate, symbol); \
    if (!field) { \
        bridgeError = "gl4metal is missing a required context export: " symbol; \
        NSLog(@"GL4MetalBridge: missing required export %s", symbol); \
        dlclose(candidate); \
        return false; \
    } \
} while (0)
    LOAD(session.initialize, "gl4metalInit");
    LOAD(session.make_current, "glMakeCurrent");
    LOAD(session.finish, "glFinish");
    LOAD(swapBuffers, "glSwapBuffers");
    LOAD(swapInterval, "glSwapInterval");
#undef LOAD
    library = candidate;
    // Do not call gl4metalInit here: window creation may run on a different
    // thread from glfwMakeContextCurrent / Minecraft's render loop.
    return true;
}

static basic_render_window_t *metal_create(basic_render_window_t *share) {
    pthread_mutex_lock(&lock);
    basic_render_window_t *window = calloc(1, sizeof(*window));
    const char *error = window ? gl4metal_session_create(&session, window, share) : "Out of memory";
    if (error) {
        bridgeError = error;
        NSLog(@"GL4MetalBridge: %s", error);
        free(window);
        window = NULL;
    }
    pthread_mutex_unlock(&lock);
    return window;
}

static void metal_make_current(basic_render_window_t *window) {
    pthread_mutex_lock(&lock);
    CALayer *layer = window ? SurfaceViewController.surface.layer : nil;
    const char *error = gl4metal_session_bind(&session, window, (uintptr_t)pthread_self(),
        [layer isKindOfClass:CAMetalLayer.class] ? (__bridge void *)layer : NULL);
    if (error) {
        bridgeError = error;
        NSLog(@"GL4MetalBridge: %s", error);
    } else {
        currentBundle = window;
        boundLayer = (__bridge void *)layer;
    }
    pthread_mutex_unlock(&lock);
}

static bool metal_destroy(basic_render_window_t *window) {
    pthread_mutex_lock(&lock);
    const char *error = gl4metal_session_destroy(&session, window, (uintptr_t)pthread_self());
    if (error) {
        bridgeError = error;
        NSLog(@"GL4MetalBridge: %s", error);
    } else {
        if (currentBundle == window) {
            currentBundle = NULL;
            boundLayer = NULL;
        }
        free(window);
    }
    pthread_mutex_unlock(&lock);
    return error == NULL;
}

static void metal_swap(void) {
    if (!currentBundle) return;
    // The surface can be replaced when switching to/from an external display.
    bridgeError = NULL;
    if ((__bridge void *)SurfaceViewController.surface.layer != boundLayer) metal_make_current(currentBundle);
    if (!bridgeError) swapBuffers();
}

static void metal_swap_interval(int interval) {
    if (currentBundle) swapInterval(interval);
}

static void metal_terminate(void) {
    // Do not dlclose or reset initialization: gl4metal has no teardown API.
    pthread_mutex_lock(&lock);
    basic_render_window_t *window = session.context;
    const char *error = gl4metal_session_destroy(&session, window, (uintptr_t)pthread_self());
    if (error) {
        bridgeError = error;
        NSLog(@"GL4MetalBridge: %s", error);
    } else {
        if (currentBundle == window) {
            currentBundle = NULL;
            boundLayer = NULL;
        }
        free(window);
    }
    pthread_mutex_unlock(&lock);
}

void set_gl4metal_bridge_tbl(void) {
    br_init = metal_init;
    br_init_context = metal_create;
    br_make_current = metal_make_current;
    br_destroy_context = metal_destroy;
    br_swap_buffers = metal_swap;
    br_swap_interval = metal_swap_interval;
    br_terminate = metal_terminate;
}
