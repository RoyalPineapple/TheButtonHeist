#import <Foundation/Foundation.h>

extern void AccraHost_autoStartFromLoad(void);

@interface AccraHostAutoStart : NSObject
@end

@implementation AccraHostAutoStart

+ (void)load {
    dispatch_async(dispatch_get_main_queue(), ^{
        AccraHost_autoStartFromLoad();
    });
}

@end
