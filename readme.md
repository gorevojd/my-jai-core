# my-jai-core

Shared Jai utilities for strings, images and sound, with re-exported name, hash-set,
blob and curve APIs.

## Dependencies

Direct module dependencies:

- [my-jai-blob](https://github.com/gorevojd/my-jai-blob): owned byte buffers and borrowed views; re-exported.
- [my-jai-curve](https://github.com/gorevojd/my-jai-curve): keyframe and curve types and operations; re-exported.
- [my-jai-hash-set](https://github.com/gorevojd/my-jai-hash-set): key-only hash sets; re-exported.
- [my-jai-math](https://github.com/gorevojd/my-jai-math): image colors and sound resampling math.
- [my-jai-name](https://github.com/gorevojd/my-jai-name): interned string identifiers; re-exported.

Jai standard library: `Basic`, `Hash_Table`, `Unicode`.

All direct module dependencies are included as Git submodules. After cloning,
initialize them with `git submodule update --init --recursive` (or clone with
`--recurse-submodules`). See each dependency's README for its own requirements.

## Import

```jai
#import "my-jai-core";
```

Add both the directory containing `my-jai-core` and the `my-jai-core` directory
itself to the compiler's module search path, so its nested modules resolve by their
short names. In this project these paths are `Src/Modules` and
`Src/Modules/my-jai-core`.
