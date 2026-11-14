# MyAssets

Typed asset storage, asset paths, registries and resource references for Jai.

This module is an ordinary source directory in my-jai-core, not a separate Git submodule.

## Dependencies

Direct module dependencies:

- [my-jai-core](https://github.com/gorevojd/my-jai-core): shared types and utilities, including interned names.
- [my-jai-math](https://github.com/gorevojd/my-jai-math): numeric limits.
- [my-jai-serializer](https://github.com/gorevojd/my-jai-serializer): binary serialization.

Jai standard library: `Basic`, `Hash`, `Hash_Table`, `String`, `Unicode`.

## Import

```jai
#import "MyAssets";
```

Add the directory containing my-jai-core and my-jai-core itself to the compiler's
module search path. In PacCodex these are `Src/Modules` and `Src/Modules/my-jai-core`.
Dependencies are bundled as Git submodules of my-jai-core; initialize them with
`git submodule update --init --recursive`. See their READMEs for dependency details.
