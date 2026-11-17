#import <Foundation/Foundation.h>

@interface MinecraftOptionUtils : NSObject
// Makes sure options.txt exists in the game directory with safe defaults for iOS.
+ (void)setupOptionsAtGameDir:(NSString *)gameDir;
@end
