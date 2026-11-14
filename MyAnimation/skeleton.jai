// Skin weight validation is the responsibility of mesh/skeleton loaders, before runtime use:
// 1) All four weights of every vertex must be finite (no NaN or infinity).
// 2) Every weight must be nonnegative.
// 3) For a vertex with any nonzero weight, abs(sum(weights) - 1.0) must be <= 0.0001.
//    Four zero weights are allowed: skinning preserves that vertex's source position.

INVALID_JOINT_INDEX :: 255;
MAX_JOINT_COUNT :: 128;
JointPaletteIndices :: [4]u8;

AnimatedGeometryInterface :: struct {
    vertices: [..]Vec3;
    indices: [..]u32;
    joint_palette_indices: [..]JointPaletteIndices;
    weights: [..]Vec4;
}

Joint :: struct {
    local: Transform;

    name: Name;
    id: Name;

    parent_index: u8 = INVALID_JOINT_INDEX;
}

Socket :: struct {
    position: Vec3;
    rotation: Quat;

    name: Name;
    joint: Name;
}

Pose :: struct {
    joint_transforms: [MAX_JOINT_COUNT] Transform;
    num_joints: u32;
}

Skeleton :: struct {
    // Loaders must store parents before children and remap all joint references accordingly.
    // Each parent_index is INVALID_JOINT_INDEX or strictly less than the child's index.
    joints: [MAX_JOINT_COUNT] Joint;
    sockets: [MAX_JOINT_COUNT] Socket;

    num_joints: u32;
    num_sockets: u32;

    default_pose: Pose;

    root_joint_index: u8 = INVALID_JOINT_INDEX;
    joint_mapping: Name_Table(u8); // id -> index in joints array
}

set_joint_transform :: (pose: *Pose, joint_index: u32, transform: Transform) #no_abc {
    Basic.assert(joint_index < pose.num_joints, "Invalid joint_index=%, when num joints is: %!", joint_index, pose.num_joints);
    pose.joint_transforms[joint_index] = transform;
}

get_joint_transform :: (pose: Pose, joint_index: u32) -> Transform #no_abc {
    Basic.assert(joint_index < pose.num_joints, "Invalid joint_index=%, when num joints is: %!", joint_index, pose.num_joints);
    return pose.joint_transforms[joint_index];
}

set_joint_position :: (pose: *Pose, joint_index: u32, position: Vec3) #no_abc {
    Basic.assert(joint_index < pose.num_joints, "Invalid joint_index=%, when num joints is: %!", joint_index, pose.num_joints);
    pose.joint_transforms[joint_index].position = position;
}

get_joint_position :: (pose: Pose, joint_index: u32) -> Vec3 #no_abc {
    Basic.assert(joint_index < pose.num_joints, "Invalid joint_index=%, when num joints is: %!", joint_index, pose.num_joints);
    return pose.joint_transforms[joint_index].position;
}

set_joint_rotation :: (pose: *Pose, joint_index: u32, rotation: Quat) #no_abc {
    Basic.assert(joint_index < pose.num_joints, "Invalid joint_index=%, when num joints is: %!", joint_index, pose.num_joints);
    pose.joint_transforms[joint_index].rotation = rotation;
}

get_joint_rotation :: (pose: Pose, joint_index: u32) -> Quat #no_abc {
    Basic.assert(joint_index < pose.num_joints, "Invalid joint_index=%, when num joints is: %!", joint_index, pose.num_joints);
    return pose.joint_transforms[joint_index].rotation;
}

set_joint_scale :: (pose: *Pose, joint_index: u32, scale: float) #no_abc {
    Basic.assert(joint_index < pose.num_joints, "Invalid joint_index=%, when num joints is: %!", joint_index, pose.num_joints);
    pose.joint_transforms[joint_index].scale = scale;
}

get_joint_scale :: (pose: Pose, joint_index: u32) -> float #no_abc {
    Basic.assert(joint_index < pose.num_joints, "Invalid joint_index=%, when num joints is: %!", joint_index, pose.num_joints);
    return pose.joint_transforms[joint_index].scale;
}

// Applies the delta to the base pose; rotation composes as delta * base.
add_poses :: (base: Pose, delta: Pose) -> Pose {
    result := base;
    add_poses_internal(*result, delta);
    return result;
}

add_poses_internal :: (base: *Pose, delta: Pose) #no_abc {
    Basic.assert(base.num_joints == delta.num_joints && base.num_joints <= MAX_JOINT_COUNT);

    for i: 0..cast(int)base.num_joints - 1 {
        base_transform := *base.joint_transforms[i];
        delta_transform := delta.joint_transforms[i];
        base_transform.position += delta_transform.position;
        base_transform.rotation = normalize_safe(delta_transform.rotation * base_transform.rotation);
        base_transform.scale *= delta_transform.scale;
    }
}

sub_poses :: (a: Pose, b: Pose) -> Pose {
    result := a;
    sub_poses_internal(*result, b);
    return result;
}

// Produces a left delta: delta = pose * inverse(other).
// add_poses(other, delta) reconstructs the input pose.
sub_poses_internal :: (pose: *Pose, other: Pose) {
    Basic.assert(pose.num_joints == other.num_joints && pose.num_joints <= MAX_JOINT_COUNT);

    for i: 0..cast(int)pose.num_joints - 1 {
        a := *pose.joint_transforms[i];
        b := other.joint_transforms[i];

        if b.scale != 0.0 {
            a.position -= b.position;
            a.rotation = normalize_safe(normalize_safe(a.rotation) * conjugate(normalize_safe(b.rotation)));
            a.scale /= b.scale;
        }
        else {
            a.scale = 0.0;
            Basic.assert(b.scale != 0.0, "Cannot subtract a pose with zero scale at joint %!", i);
        }
    }
}

lerp_poses :: (a: Pose, b: Pose, t: float) -> Pose #no_abc {
    result := a;
    lerp_poses_internal(*result, b, t);
    return result;
}

// The blend parameter is unclamped, matching the scalar/vector lerp helpers.
lerp_poses_internal :: (pose: *Pose, other: Pose, t: float) #no_abc {
    Basic.assert(pose.num_joints == other.num_joints && pose.num_joints <= MAX_JOINT_COUNT);
    Basic.assert(is_finite(t));

    if t == 0.0 {
        return;
    }
    if t == 1.0 {
        move_poses(pose, other);
        return;
    }

    for i: 0..cast(int)pose.num_joints - 1 {
        a := *pose.joint_transforms[i];
        b := other.joint_transforms[i];
        a.position = lerp(a.position, b.position, t);
        a.rotation = slerp_unclamped(a.rotation, b.rotation, t);
        a.scale = lerp(a.scale, b.scale, t);
    }
}

lerp_barycentric_poses :: (p0: Pose, p1: Pose, p2: Pose, t0: float, t1: float, t2: float) -> Pose #no_abc {
    result := p0;
    lerp_barycentric_poses_internal(*result, p1, p2, t0, t1, t2);
    return result;
}

lerp_barycentric_poses_internal :: (p0: *Pose, p1: Pose, p2: Pose, t0: float, t1: float, t2: float) #no_abc {
    Basic.assert(p0.num_joints == p1.num_joints && p0.num_joints == p2.num_joints && p0.num_joints <= MAX_JOINT_COUNT);
    Basic.assert(is_finite(t0) && is_finite(t1) && is_finite(t2));
    Basic.assert(t0 >= 0.0 && t1 >= 0.0 && t2 >= 0.0);

    largest := Basic.max(t0, Basic.max(t1, t2));
    Basic.assert(largest > 0.0);

    // Triangle vertices select an exact pose without quaternion normalization.
    if t1 == 0.0 && t2 == 0.0 {
        return;
    }

    if t0 == 0.0 && t2 == 0.0 {
        move_poses(p0, p1);
        return;
    }

    if t0 == 0.0 && t1 == 0.0 {
        move_poses(p0, p2);
        return;
    }

    w0 := t0 / largest;
    w1 := t1 / largest;
    w2 := t2 / largest;
    total := w0 + w1 + w2;
    w0 /= total;
    w1 /= total;
    w2 /= total;

    // On an edge, use the same SLERP as ordinary two-pose interpolation.
    if t0 == 0.0 {
        move_poses(p0, p1);
        lerp_poses_internal(p0, p2, w2);
        return;
    }

    if t1 == 0.0 {
        lerp_poses_internal(p0, p2, w2);
        return;
    }

    if t2 == 0.0 {
        lerp_poses_internal(p0, p1, w1);
        return;
    }

    for i: 0..cast(int)p0.num_joints - 1 {
        a := *p0.joint_transforms[i];
        b := p1.joint_transforms[i];
        c := p2.joint_transforms[i];
        q0 := normalize_safe(a.rotation);
        q1 := normalize_safe(b.rotation);
        q2 := normalize_safe(c.rotation);
        reference := q0;
        if t1 > t0 && t1 >= t2 {
            reference = q1;
        }
        else if t2 > t0 && t2 > t1 {
            reference = q2;
        }
        if dot(reference, q0) < 0.0 {
            q0 = -q0;
        }
        if dot(reference, q1) < 0.0 {
            q1 = -q1;
        }
        if dot(reference, q2) < 0.0 {
            q2 = -q2;
        }
        a.position = a.position * w0 + b.position * w1 + c.position * w2;
        a.rotation = normalize_safe(q0 * w0 + q1 * w1 + q2 * w2);
        a.scale = a.scale * w0 + b.scale * w1 + c.scale * w2;
    }
}

move_poses :: (dst: *Pose, src: Pose) #no_abc {
    Basic.assert(src.num_joints <= MAX_JOINT_COUNT);
    dst.* = src;
}
