# Handoff: fast-forward (2x / 4x) for playtesting

F8 cycles 1x → 2x → 4x so slow parts (cutscenes, CPU turns, dialogue) play faster. Off by
default, not saved to the `.ini`, shown in the window title.

## Findings (2026-11-27, opening cutscene, background runs)

- The game advances **one step per vsync event**. `main.c` frontend loop ticks it at a fixed real 60 Hz
  (`vsync_tick_vt()`, loop sleeps 16.67 ms).
- The guest clock (`guest_ns()`, scaled by `g_vt_s`; drives the system tick, vsync timing, audio clock, GPU time)
  can already run faster: `SWR_VT=1 SWR_VT_SCALE=2|4`. **That alone does not speed the game up.** At 2x/4x it
  ran *slower* than 1x (FPS 60 → 45 → 25), because vsync stays at 60 Hz real and kernel waits use real time.
- GPU thread is ~45% busy at 60 FPS, so 2x has headroom; 4x is unproven (guest CPU cost per step unknown).

## Original design

Speed factor `g_speed` ∈ {1,2,4}:
1. **Clock:** run the guest clock at `g_speed` (fixed rate; reuse `vt_rebase` without the smooth-recording
   auto-rate logic in `vt_frame`). Keep F6 smooth recording working: disable fast-forward while recording.
2. **Vsync:** frontend loop period = 16.67 ms / `g_speed` (or a separate vsync thread), so the game gets
   60×`g_speed` steps per real second. Keep 1 s housekeeping (`tick%60` etc.) on real time.
3. **Kernel timeouts:** divide by `g_speed` in `kernel.c`: `sleep_nl`, `svc_wait_sync` (`end`), svc 0x0B
   SleepThread. One helper, e.g. `i64 guest_to_real_ns(i64)`.
4. **Fewer generated frames (saves CPU):** host-render only 1 of every `g_speed` presents, so the screen stays
   ~60 FPS. Reuse the frame-skip path in `gpu_gl.c` (`frame_skip_count()` → `g_speed-1`; `g_skip_frame` already
   skips draws in `r3d_draw_gl` and the present). Check what else a skipped frame must still do (clears, copies,
   compute, storage writes; bug 12's snapshot copy) and that F5 traces and screenshots force a real frame.
5. **Frame limiter:** `main.c` limiter must pace on guest time (`g_vt_on` branch) or by `per/g_speed`.
6. **Audio, higher pitch like emulators:** the game produces `g_speed`× the samples. Before the output queue
   (`swr_audio_submit_at` in `audio.c`), resample by 1/`g_speed` (average each group of `g_speed` frames). Pitch
   rises, sound stays continuous, and the queue never fills (a full queue blocks the game's audio thread → slows
   the game). Reset resampler state on speed change.
7. **Key/UI:** `backend_win32.c` WM_KEYDOWN F8 (and `backend_x11.c`), title text `Speed: 2x`, F1 help row,
   `SWR_SPEED=N` env for tests.

## Implementation notes (2026-11-27)

- The Switch 2 VI2 display event also has its own real-time cadence. The runtime now scales both display event
  paths. Timed kernel waits use a separate deadline clock so they follow speed changes without inheriting the F6
  recording clock. The host frontend keeps its maintenance cadence on wall time.
- The OpenGL path paces window blits and swaps while retaining guest rendering, texture copies and fences. The
  existing experimental draw-skip modes can omit render target and storage writes, including work that affects
  later frames. The performance log now reports guest presents and window swaps separately.
- The baseline opening and the fixed 2x and 4x runs completed. Heavy shots stayed around 42-50 guest presents/s.
  An isolated 2x run at half render resolution showed a similar rate. The existing experimental `fps_target=20`
  reached roughly 61-67 guest presents/s, with about 20-22 window swaps/s. Neither experiment reached 2x.
- Lighter scenes reached 81 guest presents/s at the 2x setting and 107 at the 4x setting, with 60 window swaps/s.
  The 4x Raceway replay reached CPU board actions and played Cold Front through to the coin awards and turn 3.
  Compare matched runs before attributing any speed gain to the board simulation itself.

## Verify

- Background runs from checkpoint `minigame-bay` with `SWR_SPEED=1/2/4` (`_work/save-library/prepare.ps1`,
  `_work/run.ps1`, shots at 20..60 s). Opening cutscene positions at 40 s with 1x: Roll 'em Raceway. 2x should be
  about twice as far along at the same time.
- Log `performance:` lines: displayed FPS ~60 at every speed; GPU busy should not rise much at 2x/4x.
- Minigame and board CPU turns at 4x: no desync, freezes or `15 s without a new image` reports.
- Toggle speed mid-cutscene and mid-minigame; audio pitch follows without gaps; back to 1x is normal.
- F6 recording and F5 traces still work (fast-forward off while recording).

## Docs (same PR)

`docs/JAMBOREE_PORT.md` sections 1, 3, 4 (`SWR_SPEED`); `CHANGELOG.txt`; `README.md` + `README.txt` controls
(F8). See "Documentation" in `AGENTS.md`.
