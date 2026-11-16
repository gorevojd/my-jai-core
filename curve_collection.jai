#scope_export
CurveCollection :: struct {
    float_curves: Name_Table(Asset_Handle(Float_Curve));
    vec2_curves: Name_Table(Asset_Handle(Vec2_Curve));
    vec3_curves: Name_Table(Asset_Handle(Vec3_Curve));
    vec4_curves: Name_Table(Asset_Handle(Vec4_Curve));
}

/**
 * @brief Samples a named float curve, returning default if its name or ready asset is unavailable.
 * @param[in] ccl Collection of borrowed curve handles.
 * @param[in] name Interned curve name, matched only in float_curves.
 * @param[in] time Finite sample time; endpoint values are held outside the curve's range.
 * @param[in] default Fallback for missing names, invalid handles or assets that are not ready.
 * @return Curve value, or default when unavailable. A ready curve without keys samples as zero.
 * @note Uses global_asset_manager; null uses the fallback. Does not allocate, load or retain assets.
 * @pre The collection and its asset manager remain stable during sampling.
 */
sample_float :: (ccl: CurveCollection, name: Name, time: float, default: float = 0.0) -> float {
    return sample_internal(ccl.float_curves, name, time, default);
}

/** @brief Samples vec2_curves with the same fallback and lifetime rules as sample_float. */
sample_vec2 :: (ccl: CurveCollection, name: Name, time: float, default: Math.Vec2 = .{}) -> Math.Vec2 {
    return sample_internal(ccl.vec2_curves, name, time, default);
}

/** @brief Samples vec3_curves with the same fallback and lifetime rules as sample_float. */
sample_vec3 :: (ccl: CurveCollection, name: Name, time: float, default: Math.Vec3 = .{}) -> Math.Vec3 {
    return sample_internal(ccl.vec3_curves, name, time, default);
}

/** @brief Samples vec4_curves with the same fallback and lifetime rules as sample_float. */
sample_vec4 :: (ccl: CurveCollection, name: Name, time: float, default: Math.Vec4 = .{}) -> Math.Vec4 {
    return sample_internal(ccl.vec4_curves, name, time, default);
}

/** @brief Returns the stored float handle, or an empty handle if absent; does not resolve, load or retain it. */
get_float_curve :: (ccl: CurveCollection, curve_name: Name) -> Asset_Handle(Float_Curve) {
    return get_curve_internal(ccl.float_curves, curve_name, float);
}

/** @brief Returns the stored Vec2 handle, or an empty handle if absent; does not resolve, load or retain it. */
get_vec2_curve :: (ccl: CurveCollection, curve_name: Name) -> Asset_Handle(Vec2_Curve) {
    return get_curve_internal(ccl.vec2_curves, curve_name, Math.Vec2);
}

/** @brief Returns the stored Vec3 handle, or an empty handle if absent; does not resolve, load or retain it. */
get_vec3_curve :: (ccl: CurveCollection, curve_name: Name) -> Asset_Handle(Vec3_Curve) {
    return get_curve_internal(ccl.vec3_curves, curve_name, Math.Vec3);
}

/** @brief Returns the stored Vec4 handle, or an empty handle if absent; does not resolve, load or retain it. */
get_vec4_curve :: (ccl: CurveCollection, curve_name: Name) -> Asset_Handle(Vec4_Curve) {
    return get_curve_internal(ccl.vec4_curves, curve_name, Math.Vec4);
}

#scope_file
#import "Hash_Table";
Math :: #import "my-jai-math";

get_curve_internal :: (curves: Name_Table($Handle), name: Name, $T: Type) -> Handle {
    #assert Handle == Asset_Handle(CurveBase(T));
    found, handle := table_find(*curves.table, name);
    if !found {
        invalid: Handle;
        return invalid;
    }

    return handle;
}

sample_internal :: (curves: Name_Table($Handle), name: Name, time: float, default: $T/AllowedCurveValueTypes) -> T {
    handle := get_curve_internal(curves, name, T);
    curve := get(global_asset_manager, handle);
    if curve == null {
        return default;
    }

    return sample(curve.*, time);
}
