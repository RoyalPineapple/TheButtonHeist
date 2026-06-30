#include <stdint.h>

__attribute__((used))
__attribute__((visibility("default")))
__attribute__((noinline))
int32_t BHTestCAbiPatchTarget(int32_t value) {
    return value + 7;
}
