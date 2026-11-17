#import "SurfaceViewController.h"

#include "jni.h"
#include <assert.h>
#include <dlfcn.h>

#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>

#include "EGL/egl.h"
#include "EGL/eglext.h"
#include "GL/osmesa.h"

#include "glfw_keycodes.h"
#include "ctxbridges/bridge_tbl.h"
#include "ctxbridges/gl4metal_bridge.h"
#include "ctxbridges/osmesa_internal.h"
#include "utils.h"

int clientAPI;

bool (*br_init)();
br_init_context_t br_init_context;
br_make_current_t br_make_current;
bool (*br_destroy_context)(basic_render_window_t*);
void (*br_swap_buffers)();
void (*br_setup_window)();
void (*br_swap_interval)(int);
void (*br_terminate)();
__thread basic_render_window_t* currentBundle;
__thread const char *bridgeError;
static pthread_mutex_t bridgeInitLock = PTHREAD_MUTEX_INITIALIZER;
static BOOL bridgeInitialized;

void JNI_LWJGL_changeRenderer(const char* value_c) {
    JNIEnv *env = NULL;
    if (!value_c || !runtimeJavaVMPtr ||
        (*runtimeJavaVMPtr)->GetEnv(runtimeJavaVMPtr, (void **)&env, JNI_VERSION_1_4) != JNI_OK) return;
    jstring key = (*env)->NewStringUTF(env, "org.lwjgl.opengl.libname");
    jstring value = (*env)->NewStringUTF(env, value_c);
    jclass clazz = (*env)->FindClass(env, "java/lang/System");
    if (key && value && clazz) {
        jmethodID method = (*env)->GetStaticMethodID(env, clazz, "setProperty", "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;");
        if (method) {
            jobject previous = (*env)->CallStaticObjectMethod(env, clazz, method, key, value);
            if (previous) (*env)->DeleteLocalRef(env, previous);
        }
    }
    if (clazz) (*env)->DeleteLocalRef(env, clazz);
    if (value) (*env)->DeleteLocalRef(env, value);
    if (key) (*env)->DeleteLocalRef(env, key);
}

void pojavTerminate() {
    bridgeError = NULL;
    CallbackBridge_nativeSetInputReady(NO);
    if (!br_terminate) return;
    br_terminate();
}

void* pojavGetCurrentContext() {
    return br_get_current();
}

int pojavInit(BOOL useStackQueue) {
    clientAPI = GLFW_OPENGL_API;
    isInputReady = 1;
    isUseStackQueueCall = useStackQueue;
    return JNI_TRUE;
}

int pojavInitOpenGL() {
    br_destroy_context = NULL;
    const char *rendererName = getenv("HYNIS_RENDERER");
    NSString *renderer = rendererName ? @(rendererName) : @"auto";
    BOOL isAuto = [renderer isEqualToString:@"auto"];
    if (isAuto || [renderer isEqualToString:@ RENDERER_NAME_GL4ES]) {
        // At this point, if renderer is still auto (unspecified major version), pick gl4es
        renderer = @ RENDERER_NAME_GL4ES;
        setenv("HYNIS_RENDERER", renderer.UTF8String, 1);
        set_gl_bridge_tbl();
    } else if ([renderer isEqualToString:@ RENDERER_NAME_LTW]) {
        renderer = @ RENDERER_NAME_LTW;
        setenv("HYNIS_RENDERER", renderer.UTF8String, 1);
        set_gl_bridge_tbl();
    } else if ([renderer isEqualToString:@ RENDERER_NAME_MOBILEGL]) {
        renderer = @ RENDERER_NAME_MOBILEGL;
        setenv("MOBILEGL_BACKEND_TYPE", "DirectGLES", 1);
        set_gl_bridge_tbl();
    } else if ([renderer isEqualToString:@ RENDERER_NAME_MOBILEGLUES]) {
        renderer = @ RENDERER_NAME_MOBILEGLUES;
        setenv("HYNIS_RENDERER", renderer.UTF8String, 1);
        set_gl_bridge_tbl();
    } else if ([renderer isEqualToString:@ RENDERER_NAME_MTL_ANGLE]) {
        set_gl_bridge_tbl();
    } else if ([renderer isEqualToString:@ RENDERER_NAME_GL4METAL]) {
        set_gl4metal_bridge_tbl();
        JNI_LWJGL_changeRenderer(gl4metalLibraryPath().UTF8String);
        return !br_init();
    } else if ([renderer hasPrefix:@"libOSMesa"]) {
        setenv("GALLIUM_DRIVER","zink",1);
        set_osm_bridge_tbl();
    } else {
        NSLog(@"Unsupported renderer: %@", renderer);
        return 1;
    }
    JNI_LWJGL_changeRenderer(renderer.UTF8String);
    // Preload renderer library
    if (!dlopen([NSString stringWithFormat:@"@rpath/%@", renderer].UTF8String, RTLD_LAZY | RTLD_GLOBAL)) {
        NSLog(@"Cannot load renderer %@: %s", renderer, dlerror());
        return 1;
    }

    return !br_init();
    //return 0;
}

void pojavSetWindowHint(int hint, int value) {
    if (hint == GLFW_CLIENT_API) {
        clientAPI = value;
    } else if (getenv("HYNIS_RENDERER") && strcmp(getenv("HYNIS_RENDERER"), "auto")==0 && hint == GLFW_CONTEXT_VERSION_MAJOR) {
        switch (value) {
            case 1:
            case 2:
                setenv("HYNIS_RENDERER", RENDERER_NAME_GL4ES, 1);
                JNI_LWJGL_changeRenderer(RENDERER_NAME_GL4ES);
                break;
            // case 4: use Zink?
            default:
                setenv("HYNIS_RENDERER", RENDERER_NAME_MOBILEGLUES, 1);
                JNI_LWJGL_changeRenderer(RENDERER_NAME_MOBILEGLUES);
                break;
        }
    }
}

void pojavSwapBuffers() {
    bridgeError = NULL;
    if (currentBundle && br_swap_buffers) br_swap_buffers();
}

int pojavMakeCurrent(basic_render_window_t* window) {
    bridgeError = NULL;
    if (br_make_current) br_make_current(window);
    return !bridgeError && currentBundle == window;
}

const char *pojavGetContextError(void) { return bridgeError; }

int pojavDestroyContext(basic_render_window_t* window) {
    bridgeError = NULL;
    // Existing EGL/OSMesa bridges retain their current lifetime behavior.
    if (!br_destroy_context) return JNI_TRUE;
    return br_destroy_context(window) ? JNI_TRUE : JNI_FALSE;
}

void* pojavCreateContext(basic_render_window_t* contextSrc) {
    bridgeError = NULL;
    if (clientAPI == GLFW_NO_API) {
        // Game has selected Vulkan API to render
        return (__bridge void *)SurfaceViewController.surface.layer;
    }

    pthread_mutex_lock(&bridgeInitLock);
    if (!bridgeInitialized) bridgeInitialized = pojavInitOpenGL() == 0;
    if (!bridgeInitialized && !bridgeError) bridgeError = "Could not load or initialize the selected renderer; see the launcher log";
    basic_render_window_t *result = bridgeInitialized ? br_init_context(contextSrc) : NULL;
    pthread_mutex_unlock(&bridgeInitLock);
    return result;
}

void pojavSwapInterval(int interval) {
    if (!br_swap_interval) return;
    br_swap_interval(interval);
}
