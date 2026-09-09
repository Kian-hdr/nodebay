#import <Foundation/Foundation.h>
#include <assert.h>
#include <stdio.h>

// Exercise the exact bundled adapter's metadata policy without publishing
// synthetic playback, reading system media, or sending transport commands.
extern bool allMandatoryPayloadKeysSet(NSDictionary *data, bool allowMissingTitle);

int main(void) {
    @autoreleasepool {
        NSDictionary *untagged = @{@"processIdentifier": @123, @"bundleIdentifier": @"fixture.chat", @"playing": @YES};
        assert(!allMandatoryPayloadKeysSet(untagged, false));
        assert(allMandatoryPayloadKeysSet(untagged, true));
        assert(allMandatoryPayloadKeysSet(@{@"processIdentifier": @123, @"playing": @YES, @"title": @"Track"}, false));
        puts("PASS title-less real clients are emitted only when opted in");
        assert(!allMandatoryPayloadKeysSet(@{}, true));
        assert(!allMandatoryPayloadKeysSet(@{@"playing": @YES}, true));
        assert(!allMandatoryPayloadKeysSet(@{@"processIdentifier": @123}, true));
        assert(!allMandatoryPayloadKeysSet(@{@"processIdentifier": [NSNull null], @"playing": @YES}, true));
        puts("PASS empty and incomplete clients remain unavailable");
    }
    return 0;
}
