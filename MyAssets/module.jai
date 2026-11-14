#import "my-jai-core";
#load "asset_path.jai";
#load "asset_registry.jai";

global_asset_manager: *Asset_Manager;

/*
    TODO:
    * When I add compression - research a way to read & decompress only those regions of the compressed file where the data is located.
*/

Asset_State :: enum {
    Unloaded;   // Resource data is not loaded.
    Queued;     // A load was requested but CPU work has not started.
    Loading;    // Reading, decoding, or generating CPU data.
    Finalizing; // Waiting for dependencies and completing runtime setup, such as GPU upload.
    Ready;      // The resource and its required dependencies are ready to use.
    Failed;     // Loading or finalization failed.
}

Asset_Handle :: struct (T: Type) @CustomSerialize {
    using reference: Asset_Slot_Reference;

    get_serialization_size :: (value: Asset_Handle(T)) -> s64 {
        path, ok := asset_handle_path(global_asset_manager, value);
        return get_serialization_size(path.name);
    }

    serialize :: (destination: BlobView, value: Asset_Handle(T)) -> s64 {
        path, ok := asset_handle_path(global_asset_manager, value);
        if !ok {
            assert(false, "MyAssets error: invalid asset handle or missing serialization manager; substituting an empty asset path.\n");
        }

        count := serialize_into(destination, path.name);
        return count;
    }

    deserialize :: (source: BlobView, value: *Asset_Handle(T)) -> s64 {
        name: Name;

        count := deserialize_into(source, *name);
        if count < 0 || count != source.count {
            return -1;
        }

        if name.text.count == 0 {
            empty: Asset_Handle(T);
            value.* = empty;
            return count;
        }

        if is_valid_asset_path(name.text) != .None {
            return -1;
        }

        path := make_asset_path(name.text);

        replacement, found := resolve_asset_handle(global_asset_manager, path, T);
        value.* = replacement;
        return count;
    }
}

Asset_Compression :: enum {
    NONE;
    ZLIB;
    OODLE;
}

Asset_Pack :: struct {
    compression: Asset_Compression = .NONE;
}

Asset_Descriptor :: struct {
    id: Name;
    type: Type;
    format_version: u32;
    payload_offset: u64;
    payload_size: u64;
    // What if we have multiple asset packs - need some way to determine the source asset path
}

Asset_Slot :: struct {
    state: Asset_State;

    descriptor_index: u32;

    generation: u32;
    owner_count: u32;
    index_in_storage: int = -1;
    extension: Name;
    dependencies: [..] Asset_Slot_Reference;
}

// Only the first member of an Asset_Storage(T) may be entered into type_to_storage.
Asset_Storage_Base :: struct {
    type: Type;
}

Asset_Storage :: struct (T: Type) {
    base: Asset_Storage_Base;
    base.type = T;
    values: [..] T;
    slot_indices: [..] u32;
}

Asset_Manager :: struct {
    descriptors: [..] Asset_Descriptor;

    slots: [..] Asset_Slot;
    free_slots: [..] u32;

    id_to_slot: Name_Table(u32);
    type_to_storage: Table(Type, *Asset_Storage_Base, asset_type_hash);

    extension_to_type: Name_Table(*Asset_Registration);
}

Asset_Load_Mode :: enum {
    Immediate;
    Deferred;
}

load :: (manager: *Asset_Manager, path: Asset_Path, $T: Type, mode: Asset_Load_Mode = .Immediate) -> Asset_Handle(T) {
    invalid: Asset_Handle(T);
    if manager == null {
        assert(false, "Asset manager must not be null.");
        return invalid;
    }

    if mode != .Immediate {
        assert(false, "Deferred asset loading is not implemented.");
        return invalid;
    }

    extension := asset_path_extension(path);
    registered, registration := table_find(*manager.extension_to_type.table, make_name(extension));
    if !registered {
        assert(false, "Asset extension is not registered.");
        return invalid;
    }

    if registration.type != T {
        assert(false, "Asset extension is registered for a different type.");
        return invalid;
    }

    existing, slot_index := table_find(*manager.id_to_slot.table, path.name);
    if existing {
        handle: Asset_Handle(T);
        handle.slot_index = slot_index;
        handle.generation = manager.slots[slot_index].generation;
        if !asset_handle_valid(manager, handle) {
            assert(false, "Asset path belongs to a different resource type.");
            return invalid;
        }

        slot := *manager.slots[slot_index];
        if (slot.state == .Queued ||
            slot.state == .Loading ||
            slot.state == .Finalizing ||
            slot.state == .Ready)
        {
            if slot.owner_count == Math.U32_MAX {
                assert(false, "Asset reference count overflow.");
                return invalid;
            }

            // Asset is already queued - increase owner_count and return same handle
            slot.owner_count += 1;
            return handle;
        }

        if slot.state != .Unloaded {
            return invalid;
        }
    }

    callbacks := extension_callbacks(manager, extension, T);
    registration.pending_requests += 1;
    defer registration.pending_requests -= 1;

    push_allocator(context.default_allocator);

    // Call Load() callback
    value: T;
    success := true;
    if callbacks.load != null {
        success = callbacks.load(*value, null, 0);
    }

    // Call Finalize() callback
    if success && callbacks.finalize != null {
        success = callbacks.finalize(*value);
    }

    // Call Unload() callback
    if !success {
        if callbacks.unload != null {
            callbacks.unload(*value);
        }
        return invalid;
    }

    // Get or create asset Storage
    found, base := table_find(*manager.type_to_storage, T);
    storage: *Asset_Storage(T);
    if found {
        storage = cast(*Asset_Storage(T)) base;
    }
    else {
        storage = New(Asset_Storage(T));
        table_add(*manager.type_to_storage, T, *storage.base);
    }

    if !existing {
        descriptor: Asset_Descriptor;
        descriptor.id = path.name;
        descriptor.type = T;

        slot: Asset_Slot;
        slot.descriptor_index = cast(u32) manager.descriptors.count;
        slot.extension = make_name(extension);
        slot_index = cast(u32) manager.slots.count;

        array_add(*manager.descriptors, descriptor);
        array_add(*manager.slots, slot);
        table_add(*manager.id_to_slot.table, path.name, slot_index);
    }

    slot := *manager.slots[slot_index];
    slot.index_in_storage = storage.values.count;
    array_add(*storage.values, value);
    array_add(*storage.slot_indices, slot_index);
    slot.owner_count = 1;
    slot.state = .Ready;

    handle: Asset_Handle(T);
    handle.slot_index = slot_index;
    handle.generation = slot.generation;
    return handle;
}

unload :: (manager: *Asset_Manager, handle: Asset_Handle($T)) {
    if !asset_handle_valid(manager, handle) {
        assert(false, "Cannot unload an invalid asset handle.");
        return;
    }
    slot := *manager.slots[handle.slot_index];
    if slot.state == .Unloaded {
        return;
    }
    if slot.state != .Ready || slot.owner_count == 0 {
        assert(false, "Cannot unload an asset that is not ready and owned.");
        return;
    }
    if slot.dependencies.count != 0 {
        assert(false, "Asset dependency release is not implemented.");
        return;
    }
    if slot.owner_count > 1 {
        slot.owner_count -= 1;
        return;
    }

    value := get(manager, handle);
    if value == null {
        assert(false, "Ready asset has no matching storage.");
        return;
    }
    callbacks := extension_callbacks(manager, slot.extension.text, T);
    if callbacks.unload != null {
        callbacks.unload(value);
    }

    found, base := table_find(*manager.type_to_storage, T);
    storage := cast(*Asset_Storage(T)) base;
    index := slot.index_in_storage;
    last := storage.values.count - 1;
    if index != last {
        storage.values[index] = storage.values[last];
        moved_slot_index := storage.slot_indices[last];
        storage.slot_indices[index] = moved_slot_index;
        manager.slots[moved_slot_index].index_in_storage = index;
    }
    storage.values.count -= 1;
    storage.slot_indices.count -= 1;
    slot.index_in_storage = -1;
    slot.owner_count = 0;
    slot.state = .Unloaded;

    if storage.values.count == 0 {
        push_allocator(context.default_allocator);
        array_free(storage.values);
        array_free(storage.slot_indices);
        table_remove(*manager.type_to_storage, T);
        free(storage);
    }
}

/**
 * @brief Convert a typed runtime reference to its persistent path without loading or retaining it.
 * @param[in] manager Manager owning the reference; may be null only for the default empty handle.
 * @param[in] handle Typed reference, including its generation.
 * @return Path and true, or an empty path and false for an invalid nonempty reference.
 */
asset_handle_path :: (manager: *Asset_Manager, handle: Asset_Handle($T)) -> Asset_Path, bool {
    path: Asset_Path;
    if handle.slot_index == -1 && handle.generation == 0 {
        return path, true;
    }

    if !asset_handle_valid(manager, handle) {
        return path, false;
    }

    slot := manager.slots[handle.slot_index];
    path.name = manager.descriptors[slot.descriptor_index].id;
    text := path.name.text;
    if (is_valid_asset_path(text) != .None ||
        text[text.count - 1] == #char "/")
    {
        return .{}, false;
    }

    return path, true;
}

/**
 * @brief Find an existing runtime reference without loading, retaining or changing the manager.
 * @param[in] manager Manager owning the runtime slots; may be null.
 * @param[in] path Compiled asset path, or the empty reference.
 * @param[in] T Required descriptor type.
 * @return Existing handle and true; default invalid handle and false if no matching runtime slot exists.
 * @note Empty paths return the default handle and true. Descriptors alone do not resolve to handles.
 */
resolve_asset_handle :: (manager: *Asset_Manager, path: Asset_Path, $T: Type) -> Asset_Handle(T), bool {
    invalid: Asset_Handle(T);

    if path.name.text.count == 0 {
        return invalid, true;
    }

    text := path.name.text;
    if (manager == null ||
        is_valid_asset_path(text) != .None ||
        text[text.count - 1] == #char "/")
    {
        return invalid, false;
    }

    found, index := table_find(*manager.id_to_slot.table, path.name);
    if !found || index >= manager.slots.count {
        return invalid, false;
    }

    candidate: Asset_Handle(T);
    candidate.slot_index = index;
    candidate.generation = manager.slots[index].generation;
    existing_path, valid := asset_handle_path(manager, candidate);
    if !valid || !asset_paths_equal(existing_path, path) {
        return invalid, false;
    }

    return candidate, true;
}

asset_slot_reference_valid :: (manager: *Asset_Manager, slot_ref: Asset_Slot_Reference) -> bool {
    if manager == null || slot_ref.slot_index < 0 || slot_ref.slot_index >= manager.slots.count {
        return false;
    }

    return manager.slots[slot_ref.slot_index].generation == slot_ref.generation;
}

asset_handle_valid :: (manager: *Asset_Manager, handle: Asset_Handle($T)) -> bool {
    if !asset_slot_reference_valid(manager, handle.reference) {
        return false;
    }

    slot := *manager.slots[handle.slot_index];
    if slot.descriptor_index >= manager.descriptors.count {
        return false;
    }

    return manager.descriptors[slot.descriptor_index].type == T;
}

get :: (manager: *Asset_Manager, handle: Asset_Handle($T)) -> *T {
    if !asset_handle_valid(manager, handle) {
        return null;
    }

    slot := *manager.slots[handle.slot_index];
    if slot.state != .Ready {
        return null;
    }

    found, base := table_find(*manager.type_to_storage, T);
    if !found || base == null {
        return null;
    }

    if base.type != T {
        return null;
    }

    storage := cast(*Asset_Storage(T)) base;
    index := slot.index_in_storage;
    if index < 0 || index >= storage.values.count || index >= storage.slot_indices.count {
        return null;
    }

    if storage.values.data == null || storage.slot_indices.data == null || storage.slot_indices[index] != handle.slot_index {
        return null;
    }

    return *storage.values[index];
}

#scope_file
Asset_Slot_Reference :: struct {
    slot_index: int = -1;
    generation: u32;
}

#import "Basic";
Math :: #import "my-jai-math";
#import "Hash_Table";
#import "Hash";
#import "my-jai-serializer";

asset_type_hash :: (type: Type) -> u32 {
    return cast(u32) (knuth_hash(cast(u64) cast(*Type_Info) type) >> 32);
}

/*
    добавление зависимости должно быть операцией менеджера, которая одновременно:
    проверяет ссылку на дочерний ассет
    увеличивает его owner_count
    сохраняет ссылку в dependencies родителя
*/

/*
Есть несколько деталей, которые стоит определить сразу:
- Нулевой счётчик означает возможность освобождения. При синхронной работе можно освобождать сразу. При фоновой загрузке или использовании данных аудиопотоком нужно сначала дождаться безопасного момента.
- Циклы сильных зависимостей запрещаем в первой версии. Если A удерживает B, а B удерживает A, их счётчики сами не обнулятся. Обратные ссылки можно делать невладеющими.
- Поколение меняется при переиспользовании слота. Если выгружаешь только данные, но слот продолжает представлять тот же ассет, менять поколение необязательно. Нужно различать выгрузку ресурса и удаление его записи.
- Для *void нужны процедуры управления хранилищем. Менеджер должен уметь уничтожить значение и освободить хранилище. Поэтому значение type_to_storage со временем лучше заменить на запись с указателем и зарегистрированными процедурами.
- Удаление из values не должно незаметно ломать индексы. При удалении со swap-last нужно обновить index_in_storage перемещённого ассета. Для этого хранилищу понадобится обратный массив slot_indices, либо оно должно сохранять пустые позиции.
*/

/*
И ещё: твой Asset_Descriptor подходит как runtime-описание. В пакете Name нужно представлять текстом или стабильным ID, а Type — зарегистрированным ключом формата. Их внутреннее представление в памяти напрямую сериализовать нельзя.
*/
