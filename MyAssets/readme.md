# MyAssets

Typed asset storage, asset paths, registries and resource references for Jai.

This module is an ordinary source directory in my-jai-core, not a separate Git
submodule. Its API is re-exported by my-jai-core.

## Dependencies

Direct module dependencies:

- [my-jai-core](https://github.com/gorevojd/my-jai-core): shared types and utilities, including interned names.
- [my-jai-math](https://github.com/gorevojd/my-jai-math): numeric limits.
- [my-jai-serializer](https://github.com/gorevojd/my-jai-serializer): binary serialization.

Jai standard library: `Basic`, `Hash`, `Hash_Table`, `String`, `Unicode`.

## Import

```jai
#import "my-jai-core";
```

This exposes asset types and functions directly, as well as through `MyAssets`.
A separate `#import "MyAssets";` remains supported but is unnecessary when Core
is already imported. Core and the asset module share the same types and
`global_asset_manager`.

Add the directory containing my-jai-core and my-jai-core itself to the compiler's
module search path. For a checkout at `modules/my-jai-core`, these paths are
`modules` and `modules/my-jai-core`.
Dependencies are bundled as Git submodules of my-jai-core; initialize them with
`git submodule update --init --recursive`. See their READMEs for dependency details.

Build-time dependency: use the [my-jai-reflection](../my-jai-reflection/readme.md)
build hook (`ReflectionBuild.build_file`) required by the serialization module.

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
    path := make_asset_path("/textures/checker.image");
    assert(path.name.text == "/textures/checker.image");
    print("Asset path: %\n", path.name.text);
}
```

Run `jai build.jai -output_path Build` from the example directory, then run
`Build/example.exe` on Windows or `./Build/example` on Linux/macOS.
The hook compiles `main.jai` and generates its reflection metadata; a direct
compilation of `main.jai` does not run that hook.
