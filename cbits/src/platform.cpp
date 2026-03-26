#include <idunn/platform.h>

#include <cstdio>

extern "C" {
void idunn_platform_say_hello() { printf("hello, world!\n"); }
}
