#pragma once

void set_gl4metal_bridge_tbl(void);

#ifdef __OBJC__
// Also used for the JVM property, before LWJGL's GL class is initialized.
static inline NSString *gl4metalLibraryPath(void) {
    return [NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:@"libgl4metal.dylib"];
}
#endif
