using MyName :: #import "my-jai-name";
using MyHashSet :: #import "my-jai-hash-set";
using MyBlob :: #import "my-jai-blob";
using MyCurve :: #import "my-jai-curve";

#load "string_utils.jai";
#load "image.jai";
#load "sound.jai";
#load "name_set.jai";

/**
 * @brief Copies a string, returning false before copying if allocation fails.
 * @param[in] source Valid source bytes.
 * @return Owned string and success flag. Free the string in the allocation context. Empty strings succeed without allocating.
 */
try_copy_string :: (source: string) -> string, bool {
    if source.count < 0 || (source.count > 0 && source.data == null) {
        return "", false;
    }

    if source.count == 0 {
        return "", true;
    }

    result: string;
    result.data = cast(*u8)alloc(source.count);
    if result.data == null {
        return "", false;
    }

    result.count = source.count;
    memcpy(result.data, source.data, source.count);
    return result, true;
}

#scope_module
#import "Basic";

