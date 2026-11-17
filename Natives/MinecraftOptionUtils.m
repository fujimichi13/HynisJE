#import "MinecraftOptionUtils.h"

@implementation MinecraftOptionUtils

+ (void)setupOptionsAtGameDir:(NSString *)gameDir {
    if (gameDir.length == 0) return;
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:gameDir withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *path = [gameDir stringByAppendingPathComponent:@"options.txt"];
    NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] ?: @"";

    // Only add keys that are missing so the user's own settings are never overwritten.
    NSDictionary *defaults = @{
        @"fullscreen": @"false",
        @"enableVsync": @"true"
    };
    NSMutableString *out = [content mutableCopy];
    if (out.length > 0 && ![out hasSuffix:@"\n"]) [out appendString:@"\n"];
    BOOL changed = NO;
    for (NSString *key in defaults) {
        NSString *prefix = [key stringByAppendingString:@":"];
        BOOL found = NO;
        for (NSString *line in [content componentsSeparatedByString:@"\n"]) {
            if ([line hasPrefix:prefix]) { found = YES; break; }
        }
        if (!found) {
            [out appendFormat:@"%@:%@\n", key, defaults[key]];
            changed = YES;
        }
    }
    if (changed || ![fm fileExistsAtPath:path]) {
        [out writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

@end
