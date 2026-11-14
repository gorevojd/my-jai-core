// Gamma corrected (linear) premultiplied alpha format loaded image; RGBA8 format (32bits)
Image :: struct {
    width: u32;
    height: u32;

    width_over_height: float; @NonSerializeField

    data: *u8; @NonSerializeField

    finalize_descriptor :: (image: *Image) -> bool {
        if image.height <= 0 return false;

        image.width_over_height = cast(float) image.width / cast(float) image.height;
        image.data = null;

        return true;
    }
}

/**
 * @brief Fills existing image storage with a straight sRGB color, converted to linear premultiplied RGBA8.
 * @param[in,out] image Valid image with writable width * height * 4 bytes. Empty images are unchanged.
 * @param[in] color Straight sRGB color; alpha is coverage.
 */
clear :: (image: *Image, color: Math.Color) {
    assert(image != null, "Image must not be null.");
    if image.width == 0 || image.height == 0 {
        return;
    }
    assert(image.data != null, "A nonempty image must have writable pixel storage.");

    pixel := image_color_to_pixel(color);
    count := cast(u64)image.width * image.height;
    destination := image.data;
    for 0..count - 1 {
        destination[0] = pixel.r;
        destination[1] = pixel.g;
        destination[2] = pixel.b;
        destination[3] = pixel.a;
        destination += 4;
    }
}

/**
 * @brief Fills existing image storage with a checkerboard in linear premultiplied RGBA8, starting with c1 at (0, 0).
 * @param[in,out] image Valid image with writable width * height * 4 bytes. Empty images are unchanged.
 * @param[in] cell_size Positive square cell size in pixels; edge cells may be partial.
 * @param[in] c1 Straight sRGB color of even cells.
 * @param[in] c2 Straight sRGB color of odd cells.
 */
checker :: (image: *Image, cell_size: u32, c1: Math.Color = Math.Colors.WHITE, c2: Math.Color = Math.Colors.BLACK) {
    assert(image != null, "Image must not be null.");
    assert(cell_size > 0, "Checkerboard cell size must be positive.");
    if image.width == 0 || image.height == 0 {
        return;
    }
    assert(image.data != null, "A nonempty image must have writable pixel storage.");

    pixel1 := image_color_to_pixel(c1);
    pixel2 := image_color_to_pixel(c2);
    destination := image.data;
    for y: 0..image.height - 1 {
        row_parity := (y / cell_size) & 1;
        for x: 0..image.width - 1 {
            pixel := pixel1;
            if ((x / cell_size) & 1) != row_parity {
                pixel = pixel2;
            }
            destination[0] = pixel.r;
            destination[1] = pixel.g;
            destination[2] = pixel.b;
            destination[3] = pixel.a;
            destination += 4;
        }
    }
}

/**
 * @brief Composites linear premultiplied RGBA8 pixels using source-over, without scaling, clipped to destination bounds.
 * @param[in,out] dst Valid destination image with writable pixel storage.
 * @param[in] x Destination X coordinate; coordinates outside the image are allowed.
 * @param[in] y Destination Y coordinate; coordinates outside the image are allowed.
 * @param[in] src Source image; empty images are ignored.
 * @pre Source and destination pixel storage must not overlap.
 */
write_one_image_into_another :: (dst: *Image, x: u32, y: u32, src: Image) {
    assert(dst != null, "Destination image must not be null.");
    if (x >= dst.width ||
        y >= dst.height ||
        src.width == 0 ||
        src.height == 0) {
        return;
    }
    assert(dst.data != null, "A nonempty destination image must have writable pixel storage.");
    assert(src.data != null, "A nonempty source image must have readable pixel storage.");

    // Subtract only after the bounds check, avoiding overflow from x + src.width.
    copy_width := min(src.width, dst.width - x);
    copy_height := min(src.height, dst.height - y);
    src_stride := cast(s64)src.width * 4;
    dst_stride := cast(s64)dst.width * 4;
    destination := dst.data + cast(s64)y * dst_stride + cast(s64)x * 4;
    source := src.data;
    for row: 0..copy_height - 1 {
        dst_pixel := destination + row * dst_stride;
        src_pixel := source + row * src_stride;
        for column: 0..copy_width - 1 {
            inverse_alpha := 255 - cast(u32)src_pixel[3];
            // RGB is already premultiplied. Apply source-over to all four channels, rounding to the nearest byte.
            dst_pixel[0] = cast(u8)(cast(u32)src_pixel[0] + (cast(u32)dst_pixel[0] * inverse_alpha + 127) / 255);
            dst_pixel[1] = cast(u8)(cast(u32)src_pixel[1] + (cast(u32)dst_pixel[1] * inverse_alpha + 127) / 255);
            dst_pixel[2] = cast(u8)(cast(u32)src_pixel[2] + (cast(u32)dst_pixel[2] * inverse_alpha + 127) / 255);
            dst_pixel[3] = cast(u8)(cast(u32)src_pixel[3] + (cast(u32)dst_pixel[3] * inverse_alpha + 127) / 255);
            dst_pixel += 4;
            src_pixel += 4;
        }
    }
}

#scope_file
Math :: #import "my-jai-math";

image_color_to_pixel :: (color: Math.Color) -> Math.Color {
    linear := Math.srgb_to_linear_accurate(Math.get_float_representation(color));
    return Math.color_from_float_representation(Math.premultiply_alpha_linear(linear));
}
