// Implementations of functions that are declared in utils.h / LauncherPreferences.h
// and called from the launcher, but were missing from the project (linker errors).

#import <Foundation/Foundation.h>
#include <sys/mman.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>

#import "utils.h"
#import "LauncherPreferences.h"

#pragma mark - LWJGL versions

NSArray* getLwjglVersions(BOOL containsDefault) {
    NSMutableArray *array = @[@"3.3.3", @"3.3.6", @"3.4.1"].mutableCopy;
    if (containsDefault) {
        [array insertObject:@"(default)" atIndex:0];
    }
    return array;
}

#pragma mark - JIT flags

static JITFlags cachedJITFlags;
static BOOL jitFlagsCached = NO;

static BOOL envFlag(const char *name) {
    const char *value = getenv(name);
    return value && value[0] && strcmp(value, "0") != 0;
}

JITFlags DeviceGetJITFlags(BOOL refresh) {
    if (jitFlagsCached && !refresh) {
        return cachedJITFlags;
    }
    JITFlags flags = 0;
    if (NSProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26) {
        flags |= JIT_FLAG_IS_IOS_26;
    }
    // The TXM/mirrored-JIT workaround is only used when explicitly requested.
    if (envFlag("POJAV_FORCE_MIRRORED_JIT")) {
        flags |= JIT_FLAG_FORCE_MIRRORED;
    }
    if (envFlag("POJAV_HAS_TXM")) {
        flags |= JIT_FLAG_HAS_TXM;
    }
    cachedJITFlags = flags;
    jitFlagsCached = YES;
    return flags;
}

BOOL DeviceHasJITFlags(JITFlags flags) {
    // Matches if any of the requested flags is set.
    return (DeviceGetJITFlags(NO) & flags) != 0;
}

#pragma mark - JIT26 (iOS 26 TXM workaround)

static BOOL jit26DetachAfterFirstBr = YES;

void* JIT26CreateRegionLegacy(size_t len) {
    void *region = mmap(NULL, len, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    return region == MAP_FAILED ? NULL : region;
}

void* JIT26PrepareRegion(void *addr, size_t len) {
    if (!addr) {
        addr = mmap(NULL, len, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
        if (addr == MAP_FAILED) return NULL;
    }
    memset(addr, 0x69, len);
    return addr;
}

void JIT26PrepareRegionForPatching(void *addr, size_t len) {
    // Content is kept as is. Nothing to do without a debugger-assisted script.
    (void)addr;
    (void)len;
}

void JIT26SetDetachAfterFirstBr(BOOL value) {
    jit26DetachAfterFirstBr = value;
}

void JIT26SendJITScript(NSString *script) {
    // Needs a debugger (StikDebug) to run the script; just log it here.
    NSLog(@"[JIT26] Script received (%lu chars), detachAfterFirstBr=%d",
          (unsigned long)script.length, jit26DetachAfterFirstBr);
}

BOOL JIT26IsLikelyDebuggerKeepAttached(void) {
    return !jit26DetachAfterFirstBr;
}
