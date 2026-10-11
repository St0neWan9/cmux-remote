#include "CBridgeDiscovery.h"
#include <dns_sd.h>
#include <dispatch/dispatch.h>
#include <arpa/inet.h>
int32_t cmux_bonjour_publish(const char *name, uint16_t port, const unsigned char *txt, uint16_t length, void **handle) {
    DNSServiceRef ref = NULL;
    DNSServiceErrorType error = DNSServiceRegister(&ref, 0, 0, name, "_cmux-remote._tcp", "local.", NULL, htons(port), length, txt, NULL, NULL);
    if (error != kDNSServiceErr_NoError) return error;
    // Dispatch delivery works in an async CLI without a Foundation run-loop thread.
    error = DNSServiceSetDispatchQueue(ref, dispatch_get_main_queue());
    if (error != kDNSServiceErr_NoError) { DNSServiceRefDeallocate(ref); return error; }
    *handle = ref;
    return 0;
}
static void stop_on_queue(void *handle) { DNSServiceRefDeallocate((DNSServiceRef)handle); }
void cmux_bonjour_stop(void *handle) { if (handle) dispatch_async_f(dispatch_get_main_queue(), handle, stop_on_queue); }
