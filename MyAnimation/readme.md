# MyAnimation

Skeletal animation for Jai: named joints and sockets, animation clips, pose blending
and skinning transforms.

This module is an ordinary source directory in my-jai-core, not a separate Git submodule.

## Dependencies

Direct module dependencies:

- [my-jai-math](https://github.com/gorevojd/my-jai-math): vectors, transforms and interpolation.
- [my-jai-name](https://github.com/gorevojd/my-jai-name): interned joint, socket and clip identifiers.

Jai standard library: `Basic`, `Hash_Table`.

## Import

```jai
#import "MyAnimation";
```

Add the directory containing my-jai-core and my-jai-core itself to the compiler's
module search path. In PacCodex these are `Src/Modules` and `Src/Modules/my-jai-core`.
Dependencies are bundled as Git submodules of my-jai-core; initialize them with
`git submodule update --init --recursive`. See their READMEs for dependency details.
