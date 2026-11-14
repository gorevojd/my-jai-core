// Reusable skeletal animation: named joints/sockets, pose blending and skinning transforms.
// Geometry and math come from my-jai-math; interned identifiers come from my-jai-name.
// Asset loading, materials and game animation policy remain outside this module.
#scope_module
Basic :: #import "Basic";
Math :: #import "my-jai-math";
#import "my-jai-name";
using Math;

#scope_export
#load "skeleton.jai";
#load "skinning.jai";
#load "clip.jai";
#load "player.jai";
