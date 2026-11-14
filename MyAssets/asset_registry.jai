Asset_Callbacks :: struct (T: Type) {
    Load_Proc     :: #type (ctx: *void, dst: *T, data: *u8, data_size: int) -> bool;
    Finalize_Proc :: #type (ctx: *void, dst: *T) -> bool;
    Unload_Proc   :: #type (ctx: *void, dst: *T);

    load:      Load_Proc;
    finalize:  Finalize_Proc;
    unload:    Unload_Proc;
}

Asset_Registration :: struct {
    type: Type;
    pending_requests: u32;

    load_address: *void;
    finalize_address: *void;
    unload_address: *void;
}

/**
 * @brief Register an extension and a typed callback bundle without loading any resources.
 * @param[in,out] manager Manager owning the registration; calls must be serialized with manager mutation.
 * @param[in] extension Case-sensitive ASCII letters, digits or underscores, nonempty and WITHOUT a dot.
 * @param[in] T Runtime resource type, inferred in the callback signatures and shared storage key.
 * @param[in] callbacks Typed operations needed by this resource; any or all callbacks may be null.
 * @pre The manager and extension are valid, and the extension is not already registered.
 * @details
 * - The extension is interned after validation; the input buffer can be released after this call.
 * - Different extensions may map to the same T and the same manager storage. Storage is populated by
 *   load, not by registration. Registration does not retain any resource.
 * - The manager owns a copy of the callback bundle allocated with the default allocator. Keep that
 *   allocator valid until unregister_extension; no allocations inherit temporary caller storage.
 */
register_extension :: (manager: *Asset_Manager, extension: string, $T: Type, callbacks: Asset_Callbacks(T)) {
    if manager == null {
        assert(false, "Asset manager must not be null.");
        return;
    }

    if !valid_asset_extension(extension) {
        assert(false, "Asset extension must contain only ASCII letters, digits or underscores, without a dot.");
        return;
    }

    name := make_name(extension);
    if table_contains(*manager.extension_to_type.table, name) {
        assert(false, "Asset extension is already registered.");
        return;
    }

    push_allocator(context.default_allocator);
    registration := cast(*Asset_Registration) alloc(size_of(Asset_Registration));
    if registration == null {
        assert(false, "Could not allocate asset registration.");
        return;
    }

    registration.type = T;
    registration.pending_requests = 0;
    registration.load_address = cast(*void) callbacks.load;
    registration.finalize_address = cast(*void) callbacks.finalize;
    registration.unload_address = cast(*void) callbacks.unload;
    table_add(*manager.extension_to_type.table, name, registration);
}

/**
 * @brief Remove an unused extension registration without unloading resources.
 * @param[in,out] manager Manager owning the registration.
 * @param[in] extension Exact case-sensitive extension without a dot.
 * @pre The extension is registered and no resources or requests still need its callbacks.
 * @details
 * - Pending requests must pin their registration before queueing, until cancellation or completion.
 * - Matching slots block removal while queued, loading, finalizing, ready, retained, holding data or
 *   holding dependencies. Failed slots are removable only after partial-load cleanup and release.
 * - Unloaded, unowned slots may remain for stable handles. Descriptors alone do not retain registrations.
 */
unregister_extension :: (manager: *Asset_Manager, extension: string) {
    if manager == null {
        assert(false, "Asset manager must not be null.");
        return;
    }

    if !valid_asset_extension(extension) {
        assert(false, "Asset extension must contain only ASCII letters, digits or underscores, without a dot.");
        return;
    }

    name := make_name(extension);
    found, registration := table_find(*manager.extension_to_type.table, name);
    if !found {
        assert(false, "Asset extension is not registered.");
        return;
    }

    if registration.pending_requests != 0 {
        assert(false, "Asset registration still has pending requests.");
        return;
    }

    for *slot: manager.slots {
        if !names_equal(slot.extension, name) {
            continue;
        }

        if (slot.state == .Queued ||
            slot.state == .Loading ||
            slot.state == .Finalizing ||
            slot.state == .Ready ||
            slot.owner_count != 0 ||
            slot.index_in_storage >= 0 ||
            slot.dependencies.count != 0)
        {
            assert(false, "Asset registration is still used by a resource.");
            return;
        }
    }

    table_remove(*manager.extension_to_type.table, name);
    push_allocator(context.default_allocator);
    free(registration);
}

// Type-check the erased registration before copying its typed callbacks; the returned copy does not pin it.
extension_callbacks :: (manager: *Asset_Manager, extension: string, $T: Type) -> Asset_Callbacks(T) {
    callbacks: Asset_Callbacks(T);
    if manager == null {
        assert(false, "Asset manager must not be null.");
        return callbacks;
    }

    if !valid_asset_extension(extension) {
        assert(false, "Asset extension must contain only ASCII letters, digits or underscores, without a dot.");
        return callbacks;
    }

    found, base := table_find(*manager.extension_to_type.table, make_name(extension));
    if !found {
        assert(false, "Asset extension is not registered.");
        return callbacks;
    }

    if base.type != T {
        assert(false, "Asset extension is registered for a different type.");
        return callbacks;
    }

    callbacks.load = cast(type_of(callbacks.load)) base.load_address;
    callbacks.finalize = cast(type_of(callbacks.finalize)) base.finalize_address;
    callbacks.unload = cast(type_of(callbacks.unload)) base.unload_address;
    return callbacks;
}

deinit_asset_registry :: (manager: *Asset_Manager) {
    if manager == null {
        assert(false, "Asset manager must not be null.");
        return;
    }

    for manager.extension_to_type.table {
        if it.pending_requests != 0 {
            assert(false, "Asset registration still has pending requests.");
            return;
        }
    }

    for *slot: manager.slots {
        if (slot.state == .Queued ||
            slot.state == .Loading ||
            slot.state == .Finalizing ||
            slot.state == .Ready ||
            slot.owner_count != 0 ||
            slot.index_in_storage >= 0 ||
            slot.dependencies.count != 0)
        {
            assert(false, "Asset registration is still used by a resource.");
            return;
        }
    }

    push_allocator(context.default_allocator);
    clear_asset_registry(manager);
}

#scope_file
#import "Basic";
#import "Hash_Table";

clear_asset_registry :: (manager: *Asset_Manager) {
    for manager.extension_to_type.table {
        free(it);
    }

    deinit(*manager.extension_to_type.table);
    manager.extension_to_type = .{};
}

valid_asset_extension :: (extension: string) -> bool {
    if extension.count == 0 {
        return false;
    }
    for byte: extension {
        if ((byte >= #char "a" && byte <= #char "z") ||
            (byte >= #char "A" && byte <= #char "Z") ||
            (byte >= #char "0" && byte <= #char "9") || byte == #char "_")
        {
            continue;
        }
        return false;
    }
    return true;
}
