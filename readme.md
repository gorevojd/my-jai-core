# my-jai-core

Shared Jai utilities for strings, images and sound, named collections of curve
asset handles, and re-exported name, hash-set, blob and curve APIs.

The repository also contains the module collection listed below. These modules
keep their own imports and dependency boundaries.

## Dependencies

Direct module dependencies:

- [MyAssets](MyAssets/readme.md): typed asset handles and access to ready curve assets; imported privately by `curve_collection.jai`.
- [my-jai-blob](https://github.com/gorevojd/my-jai-blob): owned byte buffers and borrowed views; re-exported.
- [my-jai-curve](https://github.com/gorevojd/my-jai-curve): keyframe and curve types and operations; re-exported.
- [my-jai-hash-set](https://github.com/gorevojd/my-jai-hash-set): key-only hash sets; re-exported.
- [my-jai-math](https://github.com/gorevojd/my-jai-math): image colors and sound resampling math.
- [my-jai-name](https://github.com/gorevojd/my-jai-name): interned string identifiers; re-exported.

Jai standard library: `Basic`, `Hash_Table`, `Unicode`.

MyAssets is an ordinary source directory in this repository. The other direct
module dependencies are included as Git submodules. After cloning, initialize
them with `git submodule update --init --recursive` (or clone with
`--recurse-submodules`). See each dependency's README for its own requirements.

Build-time dependency: the [my-jai-reflection](my-jai-reflection/readme.md) build
hook is required by MyAssets' serialization dependency. Build the importing
workspace through `ReflectionBuild.build_file` from
`my-jai-reflection/reflection_build.jai`, as in PacCodex's `Src/build.jai` and
`Tools/build_assets.jai`.

## Bundled modules

The following modules are bundled in this repository and imported explicitly;
`#import "my-jai-core"` does not re-export them:

| Module | Storage | Purpose |
| --- | --- | --- |
| [MyAnimation](MyAnimation/readme.md) | Ordinary source directory | Skeletons, clips, poses and skinning |
| [MyAssets](MyAssets/readme.md) | Ordinary source directory | Asset paths, typed handles, registries and storage |
| [my-jai-batcher](my-jai-batcher/readme.md) | Git submodule | CPU triangle batching and an optional OpenGL backend |
| [my-jai-config](my-jai-config/readme.md) | Git submodule | Typed JSON configuration |
| [my-jai-events](my-jai-events/readme.md) | Git submodule | Typed synchronous events |
| [my-jai-reflection](my-jai-reflection/readme.md) | Git submodule | Compile-time metadata and live reflection |
| [my-jai-serializer](my-jai-serializer/readme.md) | Git submodule | Reflected binary serialization |

MyAnimation and MyAssets are tracked directly by this repository. The other
bundled modules retain their own repositories and pinned revisions. The recursive
initialization command above initializes these submodules too. Several bundled
modules depend on the base Core API. MyAssets also supplies Core's curve collection;
its import is file-private and does not re-export the MyAssets API from Core.

## Import

```jai
#import "my-jai-core";
```

Add both the directory containing `my-jai-core` and the `my-jai-core` directory
itself to the compiler's module search path, so its nested modules resolve by their
short names. In this project these paths are `Src/Modules` and
`Src/Modules/my-jai-core`.

## Curve collections

`CurveCollection` maps interned `Name` values to typed `Asset_Handle` values in
four independent `Name_Table`s: `float_curves`, `vec2_curves`, `vec3_curves` and
`vec4_curves`. The same name may identify different curves in each table.

```jai
#import "my-jai-core";
#import "MyAssets";
#import "Hash_Table";

// Set global_asset_manager to the manager that owns the curve handles.
curves: CurveCollection;
name := make_name("opacity");
table_set(*curves.float_curves.table, name, opacity_handle);
opacity := sample_float(curves, name, time, 1.0);
handle := get_float_curve(curves, name);
```

`sample_float`, `sample_vec2`, `sample_vec3` and `sample_vec4` resolve handles
through MyAssets' `global_asset_manager`. They return the supplied `default`
(zero when omitted) for missing names, a null manager, invalid or stale handles,
and assets that are not ready. Ready curves use `my-jai-curve.sample` unchanged:
times must be finite, values hold at the endpoints, and empty curves sample as
zero even when a nonzero fallback is supplied.

`get_float_curve`, `get_vec2_curve`, `get_vec3_curve` and `get_vec4_curve` return
the stored handle without resolving it. Missing names return the default invalid
handle (`slot_index == -1`, `generation == 0`). Lookup and sampling do not load,
retain, unload or allocate assets. Keep the collection and manager stable during
each call; the caller manages asset lifetimes and must use the owning manager.

Populate and remove entries with standard `Hash_Table` operations on each
table's `.table` field. Release the four table allocations with `deinit` when
finished; this does not release assets. Copying a collection borrows its table
storage rather than making an independent owned copy.

## Image payloads

`Image.serialize_payload` returns an owned blob and a success flag. The blob contains raw linear premultiplied
RGBA8 pixels. The payload has no header or color conversion: width and height
belong to the separately serialized descriptor.

Set the destination dimensions and leave `data` null before calling
`Image.deserialize_payload`, which returns a success flag. It requires exactly `width * height * 4` bytes,
copies them using the current allocator, and recomputes `width_over_height`.
The input blob can be released immediately afterward. Empty dimensions require
an empty payload and succeed with null pixel storage and a zero aspect ratio.
Invalid input or allocation failure asserts, returns false and leaves the destination unchanged.

Release serialized blobs with `clear_blob`. Release deserialized image pixels
with `Basic.free(image.data)` in the allocation context, then set `image.data`
to null before reuse. The stb_image loader's `free_image` is only for its own
allocations and must not be used for these payload buffers.
