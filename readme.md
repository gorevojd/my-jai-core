# my-jai-core

Shared Jai utilities for strings, images and sound, with re-exported name, hash-set,
blob and curve APIs.

The repository also contains the module collection listed below. These modules
keep their own imports and dependency boundaries.

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
modules depend on the base Core API; keeping their imports explicit avoids cycles.

## Import

```jai
#import "my-jai-core";
```

Add both the directory containing `my-jai-core` and the `my-jai-core` directory
itself to the compiler's module search path, so its nested modules resolve by their
short names. In this project these paths are `Src/Modules` and
`Src/Modules/my-jai-core`.

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
