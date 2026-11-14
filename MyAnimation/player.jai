PlaybackMode :: enum {
    Once;
    Loop;
}

PlaybackState :: enum {
    Stopped;
    Playing;
    Paused;
}

Player :: struct {
    time: float;
    speed: float = 1.0;
    mode: PlaybackMode = .Loop;
    state: PlaybackState;
}

// Always restarts; reverse playback begins at the final sample. Use unpause to resume.
play :: (player: *Player, clip: Clip) {
    Basic.assert(Math.is_finite(player.speed));
    player.time = ifx player.speed < 0.0 then clip_duration(clip) else 0.0;
    player.state = .Playing;
}

// Explicit stop resets to the first sample. Natural completion retains the reached endpoint.
stop :: (player: *Player) {
    player.state = .Stopped;
    player.time = 0.0;
}

pause :: (player: *Player) {
    if player.state == .Playing {
        player.state = .Paused;
    }
}

unpause :: (player: *Player) {
    if player.state == .Paused {
        player.state = .Playing;
    }
}

// Negative speed supports reverse playback. Once stops at the endpoint reached in that direction.
advance_animation :: (player: *Player, clip: Clip, delta_time: float) {
    Basic.assert(Math.is_finite(delta_time) && delta_time >= 0.0);
    Basic.assert(Math.is_finite(player.time) && Math.is_finite(player.speed));

    if player.state != .Playing {
        return;
    }

    duration := clip_duration(clip);
    if duration == 0.0 {
        player.time = 0.0;
        if player.mode == .Once {
            player.state = .Stopped;
        }
        return;
    }

    next := player.time + delta_time * player.speed;
    if player.mode == .Loop {
        cycles := next / duration;
        next -= Math.floor(cycles) * duration;
        if next < 0.0 {
            next += duration;
        }

        if next >= duration {
            next = 0.0;
        }

        player.time = next;
    }
    else {
        player.time = Basic.clamp(next, 0.0, duration);
        if (delta_time > 0.0 &&
            ((player.speed > 0.0 && next >= duration) || (player.speed < 0.0 && next <= 0.0))) {
            player.state = .Stopped;
        }
    }
}
