# my-jai-core

Shared Jai utilities for strings, images and sound, named collections of curve
asset handles, and re-exported name, hash-set, blob, curve and asset APIs.

The repository also contains the module collection listed below. These modules
keep their own imports and dependency boundaries.

## Dependencies

Direct module dependencies:

- [MyAssets](MyAssets/readme.md): asset paths, typed handles, registries and storage; re-exported as `MyAssets` and unqualified names.
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
`my-jai-reflection/reflection_build.jai`. The standalone build example below
shows the complete setup.

## Bundled modules

The following modules are bundled in this repository and imported explicitly;
`#import "my-jai-core"` does not re-export them:

| Module | Storage | Purpose |
| --- | --- | --- |
| [MyAnimation](MyAnimation/readme.md) | Ordinary source directory | Skeletons, clips, poses and skinning |
| [my-jai-batcher](my-jai-batcher/readme.md) | Git submodule | CPU triangle batching and an optional OpenGL backend |
| [my-jai-config](my-jai-config/readme.md) | Git submodule | Typed JSON configuration |
| [my-jai-events](my-jai-events/readme.md) | Git submodule | Typed synchronous events |
| [my-jai-reflection](my-jai-reflection/readme.md) | Git submodule | Compile-time metadata and live reflection |
| [my-jai-serializer](my-jai-serializer/readme.md) | Git submodule | Reflected binary serialization |

MyAnimation and the re-exported MyAssets module are tracked directly by this
repository. The other bundled modules retain their own repositories and pinned
revisions. The recursive initialization command above initializes these submodules
too. Several bundled modules depend on the base Core API.

## Import

```jai
#import "my-jai-core";
```

Add both the directory containing `my-jai-core` and the `my-jai-core` directory
itself to the compiler's module search path, so its nested modules resolve by their
short names. For a checkout at `modules/my-jai-core`, these paths are
`modules` and `modules/my-jai-core`.

## Standalone build example

This example uses the Core collection to provide all dependencies. From a new
example directory, with Git and the Jai compiler on your path, initialize it with:

```sh
git clone --recurse-submodules https://github.com/gorevojd/my-jai-core modules/my-jai-core
mkdir Build
```

Create these two source files beside the `modules` and `Build` directories:

```text
example/
    build.jai
    main.jai
    modules/
        my-jai-core/
            my-jai-reflection/
            ...
    Build/
```

Save as `build.jai` (the build-only standard-library imports are `Basic` and
`Compiler`):

```jai
#run {
    #import "Basic";
    #import "Compiler";
    ReflectionBuild :: #import,file "modules/my-jai-core/my-jai-reflection/reflection_build.jai";

    parent_options := get_build_options();
    driver_options: Build_Options_During_Compile;
    driver_options.do_output = false;
    set_build_options_dc(driver_options);

    workspace := compiler_create_workspace("example");
    options := get_build_options(workspace);
    copy_commonly_propagated_fields(parent_options, *options);

    module_paths: [..]string;
    array_add(*module_paths, sprint("%modules", #filepath));
    array_add(*module_paths, sprint("%modules/my-jai-core", #filepath));
    array_add(*module_paths, ..options.import_path);
    options.import_path = module_paths;
    options.output_path = sprint("%Build", #filepath);
    options.output_executable_name = "example";
    options.intermediate_path = sprint("%Build/.build", #filepath);
    set_build_options(options, workspace);

    ReflectionBuild.build_file(sprint("%main.jai", #filepath), workspace);
}
```

Save as `main.jai`:

```jai
#import "Basic";
#import "my-jai-core";

main :: () {
    curves: CurveCollection;
    value := sample_float(curves, make_name("opacity"), 0.0, 1.0);
    assert(value == 1.0);
    print("Curve default: %\n", value);
}
```

Run `jai build.jai -output_path Build` from the example directory, then run
`Build/example.exe` on Windows or `./Build/example` on Linux/macOS.
The hook compiles `main.jai` and generates its reflection metadata; a direct
compilation of `main.jai` does not run that hook.

## Curve collections

`CurveCollection` maps interned `Name` values to typed `Asset_Handle` values in
four independent `Name_Table`s: `float_curves`, `vec2_curves`, `vec3_curves` and
`vec4_curves`. The same name may identify different curves in each table.

```jai
#import "my-jai-core";
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

The polymorphic sampling helper restricts its fallback/result type with
`$T/AllowedCurveValueTypes`. The lookup helper checks that the table stores
`Asset_Handle(CurveBase(T))` for that same value type. These checks run only at
compile time and use the curve module's shared list of supported value types.

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
