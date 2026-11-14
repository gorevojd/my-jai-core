// A skin palette maps mesh-local vertices into skeleton/model space.
// inverse_bind_matrices[i] maps mesh-local bind positions into joint-local bind space.
// Output matrix i = current model-space joint matrix * inverse bind i. Do not apply the mesh node again.
// The skeleton is borrowed. This binding owns its arrays; free with their original allocator.
MAX_SKIN_PALETTE_JOINTS :: 256;

SkinBinding :: struct {
    skeleton: *Skeleton;
    joint_indices: [..]u32; // Map vertex pallette index -> skeleton joint index
    inverse_bind_matrices: [..]Math.Mat4;
}

free_skin_binding :: (skin: *SkinBinding) {
    Basic.array_free(skin.joint_indices);
    Basic.array_free(skin.inverse_bind_matrices);
    skin.* = .{};
}

build_joint_matrices :: (skeleton: Skeleton, pose: Pose, matrices: []Math.Mat4) -> bool {
    if (skeleton.num_joints > MAX_JOINT_COUNT ||
        pose.num_joints != skeleton.num_joints ||
        matrices.count != skeleton.num_joints)
    {
        Basic.assert(false, "Joint matrix build requires a skeleton, matching pose and output count within MAX_JOINT_COUNT.");
        return false;
    }

    model_space: [MAX_JOINT_COUNT]Math.Transform;
    result: [MAX_JOINT_COUNT]Math.Mat4;

    for i: 0..cast(int) skeleton.num_joints - 1 {
        local := pose.joint_transforms[i];
        parent := skeleton.joints[i].parent_index;

        if parent != INVALID_JOINT_INDEX {
            if parent >= i {
                Basic.assert(false, "Joint % references parent %, which must precede it.", i, parent);
                return false;
            }

            local = Math.multiply(model_space[parent], local);
        }

        local.rotation = Math.normalize_safe(local.rotation);
        model_space[i] = local;
        result[i] = Math.to_matrix(local);
    }

    for *matrix, i: matrices {
        matrix.* = result[i];
    }

    return true;
}

build_skin_matrices :: (skin: SkinBinding, pose: Pose, matrices: []Math.Mat4) -> bool {
    if (skin.skeleton == null ||
        skin.joint_indices.count > MAX_SKIN_PALETTE_JOINTS ||
        skin.joint_indices.count != skin.inverse_bind_matrices.count ||
        matrices.count != skin.joint_indices.count)
    {
        Basic.assert(false, "Skin matrix build requires a skeleton and matching palette, inverse-bind and output counts within capacity.");
        return false;
    }

    if skin.skeleton.num_joints > MAX_JOINT_COUNT {
        Basic.assert(false, "Skeleton joint count exceeds joint matrix scratch storage.");
        return false;
    }

    model_space: [MAX_JOINT_COUNT]Math.Mat4;
    if !build_joint_matrices(skin.skeleton.*, pose, .{skin.skeleton.num_joints, model_space.data}) {
        return false;
    }

    result: [MAX_SKIN_PALETTE_JOINTS]Math.Mat4;
    for joint, palette_index: skin.joint_indices {
        if joint >= skin.skeleton.num_joints {
            Basic.assert(false, "Palette entry % references joint %, but skeleton has % joints.", palette_index, joint, skin.skeleton.num_joints);
            return false;
        }

        result[palette_index] = model_space[joint] * skin.inverse_bind_matrices[palette_index];
    }

    for *matrix, i: matrices {
        matrix.* = result[i];
    }

    return true;
}

apply_pose_to_mesh :: (dst: *$T/interface AnimatedGeometryInterface, src: T, skin: SkinBinding, pose: Pose) {
    Basic.assert(dst.vertices.count == src.vertices.count, "CPU skinning source and destination vertex counts differ.");
    Basic.assert(src.joint_palette_indices.count == src.vertices.count && src.weights.count == src.vertices.count,
                 "CPU skinning requires palette indices and weights for every vertex.");

    palette: [MAX_SKIN_PALETTE_JOINTS]Math.Mat4;
    Basic.assert(skin.joint_indices.count <= palette.count, "Skin palette exceeds CPU skinning scratch storage.");

    valid := build_skin_matrices(skin, pose, .{skin.joint_indices.count, palette.data});
    if valid {
        for source, i: src.vertices {
            position: Math.Vec3;
            total_weight := 0.0;
            for influence: 0..3 {
                weight := src.weights[i].e[influence];
                if weight == 0.0 {
                    continue;
                }

                palette_index := src.joint_palette_indices[i][influence];
                Basic.assert(palette_index < skin.joint_indices.count, "Vertex % references missing palette entry %.", i, palette_index);

                transformed := palette[palette_index] * Math.Vec4.{source.x, source.y, source.z, 1.0};
                position += transformed.xyz * weight;
                total_weight += weight;
            }

            dst.vertices[i] = ifx total_weight == 0.0 then source else position;
        }
    }
}
