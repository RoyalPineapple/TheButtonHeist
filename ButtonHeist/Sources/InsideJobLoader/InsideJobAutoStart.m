#ifdef DEBUG
#import <Foundation/Foundation.h>

extern void InsideJob_autoStartFromLoad(void);

@interface InsideJobAutoStart : NSObject
@end

@implementation InsideJobAutoStart

+ (void)load {
    dispatch_async(dispatch_get_main_queue(), ^{
        InsideJob_autoStartFromLoad();
    });
}

@end
#endif // DEBUG
