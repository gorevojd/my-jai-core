Sound_Frame :: struct {
    left: s16;
    right: s16;
}

Sound :: struct {
    num_frames: u64;
    sample_rate_hz: u32;

    data: *Sound_Frame; @NonSerializeField
}

/*
    Resample a complete stereo S16 sound with a Blackman-windowed sinc filter.
    * Returns independent storage, even at the original rate; input is unchanged.
      Release it with free_sound in the allocator context used for this call.
    * Round the frame count to the nearest duration match, with at least one frame.
    * Reserve 6% of Nyquist for the transition band and use 32 zero crossings per
      side. Widen the filter when downsampling; normalize truncated edges to preserve DC.
    * Process whole clips, not streaming blocks. Allocation and filtering make this
      unsuitable for an audio callback.
    * Round and saturate S16 output without dithering. Filtering can ring near
      transients and may clip full-scale signals.
    * Failure returns an empty Sound and a static error string.
*/
resample_to_hz :: (sound: Sound, new_hz: u32) -> Sound, string {
    output_count, error := resample_frame_count(sound, new_hz);
    if error.count > 0 {
        return .{}, error;
    }

    byte_count := cast(s64) output_count * size_of(Sound_Frame);
    output := cast(*Sound_Frame) Basic.alloc(byte_count);
    if output == null {
        return .{}, "Could not allocate resampled sound.";
    }

    result: Sound;
    result.num_frames = output_count;
    result.sample_rate_hz = new_hz;
    result.data = output;
    resample_into(sound, result);
    return result, "";
}

/*
    Resample an owned sound and replace its contents after successful conversion.
    * Uses the same filter and rounding as resample_to_hz. An unchanged rate is a no-op.
    * Downsampling keeps the allocation, with a small stack queue delaying writes
      until future filter evaluations no longer need those input frames.
    * Upsampling allocates a new buffer, then frees and replaces the old buffer.
    * Requires exclusive access and storage compatible with Basic.free in the current
      allocator context. Borrowed copies become stale; do not call during playback.
    * Returns an empty string on success; on error the original sound is unchanged.
*/
resample_to_hz_inplace :: (sound: *Sound, new_hz: u32) -> string {
    if sound == null {
        return "Resampling requires a sound pointer.";
    }

    output_count, error := resample_frame_count(sound.*, new_hz);
    if error.count > 0 {
        return error;
    }

    if new_hz == sound.sample_rate_hz {
        return "";
    }

    if new_hz > sound.sample_rate_hz {
        result, conversion_error := resample_to_hz(sound.*, new_hz);
        if conversion_error.count > 0 {
            return conversion_error;
        }
        Basic.free(sound.data);
        sound.* = result;
        return "";
    }

    destination: Sound;
    destination.num_frames = output_count;
    destination.sample_rate_hz = new_hz;
    destination.data = sound.data;
    resample_into(sound.*, destination);
    sound.num_frames = output_count;
    sound.sample_rate_hz = new_hz;
    return "";
}

// Buffers allocated by the WAV loader or resample_to_hz. Struct copies borrow the
// same storage: free once, after playback stops. Null/empty inputs are allowed.
free_sound :: (sound: *Sound) {
    if sound == null {
        return;
    }
    if sound.data != null {
        Basic.free(sound.data);
    }
    sound.* = .{};
}

#scope_file
Math :: #import "my-jai-math";

// Keep frame indices exactly representable in float64 and byte counts in s64.
MAX_RESAMPLE_FRAMES :: 0x001fffffffffffff;

RESAMPLE_ZERO_CROSSINGS :: 32.0;
RESAMPLE_BAND_FRACTION :: 0.94;
// Downsampling delays at most ceil(32 / 0.94) + 1 output frames; allow a margin.
RESAMPLE_PENDING_CAPACITY :: 64;

Resample_Filter :: struct {
    cutoff: float64;
    radius: float64;
}

make_resample_filter :: (source_hz: u32, new_hz: u32) -> Resample_Filter {
    ratio := cast(float64) new_hz / cast(float64) source_hz;
    cutoff := RESAMPLE_BAND_FRACTION * Basic.min(ratio, 1.0);
    return .{cutoff, RESAMPLE_ZERO_CROSSINGS / cutoff};
}

/*
    Fill validated destination storage using the shared resampling loop.
    * Buffers must be separate or identical; partial overlap is not supported.
    * Identical storage is allowed only at equal or lower rates. Delay writes until
      their input positions leave the filter window, using a fixed stack queue.
    * The caller owns allocation and updates the public Sound metadata afterwards.
*/
resample_into :: (source: Sound, destination: Sound) {
    same_buffer := source.data == destination.data;
    if source.sample_rate_hz == destination.sample_rate_hz {
        if !same_buffer {
            memcpy(destination.data, source.data, cast(s64) destination.num_frames * size_of(Sound_Frame));
        }
        return;
    }
    Basic.assert(!same_buffer || destination.sample_rate_hz < source.sample_rate_hz,
                 "Growing resampling output requires separate storage.");
    filter := make_resample_filter(source.sample_rate_hz, destination.sample_rate_hz);
    pending: [RESAMPLE_PENDING_CAPACITY]Sound_Frame;
    next_write: s64;
    for frame: 0..cast(s64) destination.num_frames - 1 {
        if same_buffer {
            position := resample_position(source.sample_rate_hz, destination.sample_rate_hz, frame);
            first_needed := cast(s64) Math.ceil(Basic.max(position - filter.radius, 0.0));
            while next_write < frame && next_write < first_needed {
                destination.data[next_write] = pending[next_write % pending.count];
                next_write += 1;
            }
            Basic.assert(frame - next_write < pending.count, "Resample delay queue must cover the filter support.");
        }
        value := resample_frame(source, destination.sample_rate_hz, frame, filter);
        if same_buffer {
            pending[frame % pending.count] = value;
        }
        else {
            destination.data[frame] = value;
        }
    }
    if same_buffer {
        while next_write < cast(s64) destination.num_frames {
            destination.data[next_write] = pending[next_write % pending.count];
            next_write += 1;
        }
    }
}

resample_frame_count :: (sound: Sound, new_hz: u32) -> u64, string {
    if sound.sample_rate_hz == 0 || new_hz == 0 {
        return 0, "Resampling requires positive source and destination sample rates.";
    }
    if sound.num_frames == 0 || sound.data == null {
        return 0, "Resampling requires a nonempty sound buffer.";
    }
    if sound.num_frames > MAX_RESAMPLE_FRAMES {
        return 0, "Sound exceeds the resampler's addressable frame count.";
    }
    // Bound multiplication and rounding before doing unsigned integer arithmetic.
    half_rate := cast(u64) sound.sample_rate_hz / 2;
    if sound.num_frames > (0xffffffffffffffff - half_rate) / new_hz {
        return 0, "Resampled duration exceeds the supported integer range.";
    }
    output_count := (sound.num_frames * new_hz + half_rate) / sound.sample_rate_hz;
    output_count = Basic.max(output_count, 1);
    if output_count > MAX_RESAMPLE_FRAMES {
        return 0, "Resampled sound exceeds the addressable frame count.";
    }
    return output_count, "";
}

resample_position :: (source_hz: u32, new_hz: u32, frame: s64) -> float64 {
    // Compute each phase independently instead of accumulating error.
    return cast(float64) frame * cast(float64) source_hz / cast(float64) new_hz;
}

resample_frame :: (sound: Sound, new_hz: u32, frame: s64, filter: Resample_Filter) -> Sound_Frame {
    position := resample_position(sound.sample_rate_hz, new_hz, frame);
    first := cast(s64) Math.ceil(Basic.max(position - filter.radius, 0.0));
    last_frame := cast(s64) sound.num_frames - 1;
    last := cast(s64) Math.floor(Basic.min(position + filter.radius, cast(float64) last_frame));
    left, right, weight_sum: float64;
    for source: first..last {
        distance := cast(float64) source - position;
        phase := Math.PI64 * filter.cutoff * distance;
        sinc: float64 = 1.0;
        if Math.abs(phase) > 0.00000001 {
            sinc = Math.sin(phase) / phase;
        }
        window_phase := Math.PI64 * distance / filter.radius;
        window := 0.42 + 0.5 * Math.cos(window_phase) + 0.08 * Math.cos(2.0 * window_phase);
        weight := sinc * window;
        left += cast(float64) sound.data[source].left * weight;
        right += cast(float64) sound.data[source].right * weight;
        weight_sum += weight;
    }
    return .{resample_quantize(left / weight_sum), resample_quantize(right / weight_sum)};
}

resample_quantize :: (value: float64) -> s16 {
    rounded := Math.floor(value + 0.5);
    return cast(s16) Basic.clamp(rounded, -32768.0, 32767.0);
}

