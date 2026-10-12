#ifndef CMUX_BRIDGE_DISCOVERY_H
#define CMUX_BRIDGE_DISCOVERY_H
#include <stdint.h>
int32_t cmux_bonjour_publish(const char *name, uint16_t port, const unsigned char *txt, uint16_t length, void **handle);
void cmux_bonjour_stop(void *handle);
#endif
