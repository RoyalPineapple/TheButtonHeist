#ifdef DEBUG
#import <Foundation/Foundation.h>

extern void TheInsideJob_autoStartFromLoad(void);

@interface ThePlantAutoStart : NSObject
@end

@implementation ThePlantAutoStart

+ (void)load {
    dispatch_async(dispatch_get_main_queue(), ^{
        TheInsideJob_autoStartFromLoad();
    });
}

@end
#endif // DEBUG
