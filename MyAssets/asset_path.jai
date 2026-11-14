/**
 * @brief A validated, case-sensitive asset reference backed by MyName.Name.
 * @details
 * - Construct with make_asset_path; a zero-initialized value is an invalid, absent reference.
 * - Never modify the backing name or its text. Name owns the bytes until process exit.
 * - Copying a path needs no retain/release and does not affect resource ownership or loading.
 * - Serialize the text, not the backing identity or process-local hash.
 */
Asset_Path :: struct {
    name: Name;
}

MAX_ASSET_PATH_BYTES :: 512;

Asset_Path_Error :: enum {
    None;
    EmptyPath;
    MissingExtension;
    MissingLeadingSlash;
    RootNotAllowed;
    EmptySegment;
    DotSegment;
    ParentSegment;
    Backslash;
    ControlCharacter;
    InvalidUtf8;
    TooLong;
}

/**
 * @brief Return a static explanation for an asset path validation result.
 * @param[in] error Validation result, including None.
 * @return Borrowed immutable text; None returns an empty string.
 */
get_asset_path_error_string :: (error: Asset_Path_Error) -> string {
    if #complete error == {
        case .None;
            return "";
        case .EmptyPath;
            return "an empty string is not a valid asset path";
        case .MissingExtension;
            return "the final path segment must have a nonempty extension";
        case .MissingLeadingSlash;
            return "nonempty paths must begin with '/'";
        case .RootNotAllowed;
            return "the root or a slash-only path is not an asset reference";
        case .EmptySegment;
            return "interior path segments must not be empty";
        case .DotSegment;
            return "'.' path segments are not allowed";
        case .ParentSegment;
            return "'..' path segments are not allowed";
        case .Backslash;
            return "backslashes are not allowed; use '/'";
        case .ControlCharacter;
            return "ASCII control characters, including NUL and DEL, are not allowed";
        case .InvalidUtf8;
            return "path bytes must form valid UTF-8";
        case .TooLong;
            return "the normalized asset path exceeds 512 UTF-8 bytes";
    }
    return "Unknown asset path error";
}

/**
 * @brief Validate and normalize a path before interning its text.
 * @param[in] text Input bytes, valid and unchanged for the duration of this call.
 * @return The normalized path; an empty path if an invalid-input assertion handler continues execution.
 * @pre The input passes is_valid_asset_path. Invalid input asserts with its specific reason and is never interned.
 * @details
 * - Empty input is invalid. Paths must begin with '/' and end in a nonempty extension after normalization.
 * - Remove all trailing '/' bytes. Reject '/' and slash-only input instead of making them empty references.
 * - The normalized path must not exceed MAX_ASSET_PATH_BYTES UTF-8 bytes, including the leading slash and extension.
 * - Reject repeated '/' inside the remaining path, and complete '.' or '..' segments; 'brick..png' is valid.
 * - Reject backslashes and ASCII control bytes (0 through 31, and 127), including embedded NUL.
 * - Accept valid UTF-8, including non-ASCII names and spaces. Reject malformed sequences with InvalidUtf8.
 * - Preserve the accepted text exactly. No Unicode normalization, case folding, URL decoding or platform
 *   filesystem rules are applied; canonically equivalent Unicode spellings remain distinct paths.
 * - Invalid input is never interned. Valid nonempty input may allocate and lock in MyName.make_name.
 * - The returned path is independent of the input storage. Resource existence is not checked.
 */
make_asset_path :: (text: string) -> Asset_Path {
    result: Asset_Path;
    error := is_valid_asset_path(text);
    if error != .None {
        assert(false, "Invalid asset path (%): %.", error, get_asset_path_error_string(error));
        return result;
    }

    normalized := text;
    while normalized.count > 0 && normalized[normalized.count - 1] == #char "/" {
        normalized.count -= 1;
    }

    result.name = make_name(normalized);
    return result;
}

/**
 * @brief Check asset path syntax without assertions, allocation or interning.
 * @param[in] text Input bytes, valid and unchanged for the duration of this call.
 * @return None for valid input, otherwise the first error under make_asset_path's normalization rules.
 * @details Empty input returns EmptyPath. Trailing slashes are removed before checking segments and UTF-8.
 * TooLong is checked after the leading slash and root checks, before segments and UTF-8.
 * MissingExtension is checked after syntax and UTF-8; a dotted parent directory is not a file extension.
 * Loader registration and resource existence are not checked.
 * @see make_asset_path
 */
is_valid_asset_path :: (text: string) -> Asset_Path_Error {
    if text.count == 0 {
        return .EmptyPath;
    }
    if text[0] != #char "/" {
        return .MissingLeadingSlash;
    }

    normalized := text;
    while normalized.count > 0 && normalized[normalized.count - 1] == #char "/" {
        normalized.count -= 1;
    }
    if normalized.count == 0 {
        return .RootNotAllowed;
    }
    if normalized.count > MAX_ASSET_PATH_BYTES {
        return .TooLong;
    }

    segment_start: int = 1;
    cursor: int = 1;
    while cursor <= normalized.count {
        if cursor == normalized.count || normalized[cursor] == #char "/" {
            segment: string;
            segment.data = normalized.data + segment_start;
            segment.count = cursor - segment_start;
            if segment.count == 0 {
                return .EmptySegment;
            }
            if segment == "." {
                return .DotSegment;
            }
            if segment == ".." {
                return .ParentSegment;
            }
            segment_start = cursor + 1;
        }
        else {
            byte := normalized[cursor];
            if byte == #char "\\" {
                return .Backslash;
            }
            if byte < #char " " || byte == #char "\x7f" {
                return .ControlCharacter;
            }
            if byte > #char "\x7f" {
                // The standard strict decoder accepts lone continuation bytes; check the lead-bit pattern first.
                if (byte & 0xC0) != 0xC0 {
                    return .InvalidUtf8;
                }
                code_point, byte_count, status := character_utf8_to_utf32(normalized.data + cursor,
                                                                       normalized.count - cursor,
                                                                       true);
                if status != .CONVERSION_OK {
                    return .InvalidUtf8;
                }
                cursor += byte_count;
                continue;
            }
        }
        cursor += 1;
    }

    dot := normalized.count - 1;
    while dot >= 0 && normalized[dot] != #char "." && normalized[dot] != #char "/" {
        dot -= 1;
    }
    if dot < 0 || normalized[dot] != #char "." || dot == normalized.count - 1 {
        return .MissingExtension;
    }
    return .None;
}

// Constant-time identity comparison; both paths must be constructed through make_asset_path or zero-initialized.
asset_paths_equal :: (a: Asset_Path, b: Asset_Path) -> bool {
    return names_equal(a.name, b.name);
}

operator == :: (a: Asset_Path, b: Asset_Path) -> bool {
    return asset_paths_equal(a, b);
}

// Constant-time, process-local hash for tables. Collisions are possible; never persist it as an asset ID.
asset_path_hash :: (path: Asset_Path) -> u32 {
    return name_hash(path.name);
}

// Bytewise lexicographic order: -1, 0 or 1. Empty precedes nonempty; a prefix precedes a longer path.
compare_asset_paths :: (a: Asset_Path, b: Asset_Path) -> int {
    return String.compare(a.name.text, b.name.text);
}

#scope_file
#import "Basic";
String :: #import "String";
#import "Unicode";


#scope_module
asset_path_extension :: (path: Asset_Path) -> string {
    text := path.name.text;
    dot := text.count - 1;
    while dot >= 0 && text[dot] != #char "." && text[dot] != #char "/" {
        dot -= 1;
    }

    if dot < 0 || text[dot] != #char "." || dot == text.count - 1 {
        return "";
    }

    extension: string;
    extension.data = text.data + dot + 1;
    extension.count = text.count - dot - 1;
    return extension;
}
