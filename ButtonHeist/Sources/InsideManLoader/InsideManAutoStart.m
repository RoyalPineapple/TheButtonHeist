#ifdef DEBUG
#import <Foundation/Foundation.h>

extern void InsideMan_autoStartFromLoad(void);

@interface InsideManAutoStart : NSObject
@end

@implementation InsideManAutoStart

+ (void)load {
    dispatch_async(dispatch_get_main_queue(), ^{
        InsideMan_autoStartFromLoad();
    });
}

@end
#endif // DEBUG
