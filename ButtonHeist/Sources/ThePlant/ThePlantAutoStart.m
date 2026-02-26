#ifdef DEBUG
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

@interface ThePlantAutoStart : NSObject
@end

@implementation ThePlantAutoStart

+ (void)load {
    dispatch_async(dispatch_get_main_queue(), ^{
        // Look up the Swift class at runtime to avoid generated header dependency
        Class cls = NSClassFromString(@"InsideJobAutoStarter");
        if (cls) {
            SEL sel = NSSelectorFromString(@"autoStart");
            if ([cls respondsToSelector:sel]) {
                ((void (*)(id, SEL))objc_msgSend)(cls, sel);
            }
        }
    });
}

@end
#endif // DEBUG
