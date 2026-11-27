# Super Mario Party Jamboree (Switch 1, v1.1.0, title 0100965017338000): PC port notes

Working log and spec for the static recompilation of Jamboree with Switch2Recomp 0.4.1 (MZ Labs).
The runtime source in `runtime/` is patched here; every change is in git (`git log` in this folder).

## 1. Status

Last updated 2026-11-27 (after PR #8). Keep this table current with every change (see `AGENTS.md`).

| Area | State |
| --- | --- |
| Boot, loading screen | works |
| White screen freeze after the loading screen | **fixed** (bug 1) |
| Intro movie (bq_op.mp4, H.264 via NVDEC → OpenH264) | works, 60 FPS, ~5 min, unskippable on first boot (same as console) |
| Title screen ("Press L+R") | renders, music plays (SM_BGM_TITLE) |
| Title screen load | **fixed** (bug 3): no stall, balloon characters no longer black |
| Pressing L+R at the title | **fixed** (bug 4): save is created, player-count screen, Party Plaza hub |
| Saves | `bqSaveData`, `bqSaveData2` written to `<name>_data/save/user/`; intro skippable (+) once a save exists |
| Menus | player count, character select (3D preview), Party Plaza hub (walk, talk, Toad's tutorial), balloon tour and mode list (`menu01.nro`), party rules, opponent/board setup |
| Boards | all seven load and play their first turn (section 9). Mega Wiggler's Tree Party (`bd01.nro`) plays further: intro, dice/items/board menu, HUD, CPU turns, minigame and back, autosave, 55-60 FPS. Full 10-turn parties not played through yet |
| Minigames | **107 of 112** played from practice to the results in Minigame Bay (section 10); the other 5 are locked on the test save. Sandwiched also played inside a party, back to the board |
| Motion minigames (25) | **fixed** (bug 19): play as one Joy-Con with F6; right stick tilts, O shakes. Feel still to be checked by the owner (M10) |
| New party | works: party rules tutorial (scroll with the D-pad), board and settings, turn order, first turn, autosave |
| Pause menu on the board | works (Resume, exit to the balloon or plaza with its confirmation) |
| Load hitches | open: the tested Mega Wiggler resume route stayed below 1.5 s per frame gap. Other boards showed 2.7-7.2 s gaps on first entry (section 9); small spikes during ordinary play |
| Save dates | **fixed** (bug 6): parties were dated 12/31/1969 |
| Mode list backdrop | not reproduced: the gray panel seen there is the game's own Offline Data dialog |
| Reading the user's dump in place | works (`game_dump=`), nothing copied |
| Dialog boxes, text bubbles, dice counters | **fixed** (bug 7): they were clipped away. Coin change popups ("-5" when buying at the shop) show too |
| Characters missing (Mario in character select and on the board) | **fixed** with bug 7: all previews render |
| Title movie / attract cutscene choppy | **fixed** (bug 8): the video texture now updates every decoded picture |
| Board spaces | **fixed** (bugs 9 and 10): the spaces along the paths show, near and far |
| Results star graph | **fixed** (bug 17) |
| Minigame Bay sea | **fixed** (bug 18): no more black stripes |
| Input | keyboard via window messages, XInput controllers (by label: A confirms; `pad_buttons=1` for Switch positions); F6 one Joy-Con mode. Hold inputs on a real pad not checked yet |
| Button prompts with an Xbox pad | **fixed** (bug 11): the four-dot face-button icons point at the Xbox button to press |
| Minigame select background | worked around (bug 12): the board shows behind the list instead of black; the real cause is open |
| Esc | no longer quits on a tap: hold it 1.5 s (the title bar says so) |
| Audio | audren mixer runs (DSP-ADPCM voices, BFSTM streams); a stalled output device no longer freezes the game (bug 20). Not checked by ear |
| Owner checks | M1-M10 pending against the console (section 7) |

Fastest path to a board with a save (keys): + skips the intro, Q+E at the title, A through the plaza, then in the
balloon pick Mario Party; ~2.5 min from launch. With `_work/run.ps1`: `-Keys` = `12:0x0D@500,22:0x51+0x45@500,
26:0x51+0x45@500`, then `0x20` (A) every 3 s from 34 to 100 s, `104:0x28,108:0x5A,114:0x5A`, then A every 4 s.
With a party in progress the menus are shorter: A every 3 s from 34 s resumes it (board at ~70 s) and keeps playing
turns and minigames. Don't send + (Enter) on the board: it opens the pause menu. The path depends on the save, so
check screenshots rather than trusting a fixed schedule.

Keyboard (runtime defaults): arrows = D-pad, WASD = left stick, X/Space = A, Z = B, C = X, V = Y, Q = L, E = R,
1 = ZL, 3 = ZR, Enter = +, Backspace = -. The title needs L+R = **Q+E together**.

## 2. Bugs

### Bug 1: white screen after the loading screen (fixed)
- Symptom: loading screen, then white window forever. Log: `6 s without a new image`, GL thread stuck in
  `glCompressedTexSubImage*`, compile thread stuck "loading a cached shader".
- Evidence: an external stack dump (`_work/stackdump.c`) showed one NVIDIA driver thread deep in recursion (its GLSL
  compiler) while every other GL thread waited on the driver's global SRW lock. Compiling each dumped shader alone
  (`_work/glcompile.c`) found two fragment shaders (`5e9b4b7872bf24a6`, `dccc83b42d9056a8`) that never finish (> 20 s).
- Cause: they use an indirect branch (`BRX`, a switch jump table). The translator finds the table through the `LDC`
  that loads it, but looked only 8 instructions back. Jamboree loads it ~30 instructions earlier, so the translator
  made every instruction a `case` of a `while(true){switch(pc)}` loop (1211 cases), which NVIDIA can't structure.
- Fix (`runtime/shader.c`, `brx_targets2`): search up to 64 instructions back, stop at another write of the
  register or at control flow. 1211 → 23 cases, compiles in ms, the intro plays.

### Bug 2: dropped bindless texture fetch in the board vertex shader `e79ac5262cbfd67d` (fixed)
- `TEX.B (untracked handle)`: the handle comes from `IADD r19 = RZ + c[11][0x140]`; the tracker only followed RZ.
- Fix (`runtime/shader.c`, `track_src`): `IADD`/`LOP` (cbuf form) with RZ and no negate/invert is the cbuf value.
  Untranslated instruction count in the log went from 2 to 0.

### Bug 3: ~70 s freeze when the title screen loads, shader `1f72046c692943ee` (fixed)
- Same shape as bug 1 (1163 switch cases; NVIDIA works ~70 s then fails with "too many instructions", so that
  effect is also missing). Its three `BRX` all have their `LDC` close by.
- First cause found: the "another write of the register" check read bits 0-7 as a destination on every opcode. On
  `ISETP/FSETP` those bits are two predicates (P1 + PT reads as r15, the table register). Fixed.
- Second cause (from the new `shader: BRX at N: ...` log line): a predicated `BRA` between the `LDC` and the `BRX`
  stopped the search. The switch's `LDC` dominates its `BRX`, so only another write of the register stops it now.
- Result: no stall, no compile failure, and the title's balloon characters (drawn with that shader, black before)
  render correctly.

### Bug 4: pressing L+R at the title aborts the game (fixed)
- Log: `svcBreak` from `nn::diag::detail::AbortImpl(Result)` called by
  `bq::flag::GameFlagModule::On(GameFlag, bool, PlayerID)` at `0x81e0ccc`, because
  `bq::save::SaveDataMgr::FindPreselectedUserSaveData()` returned null (slot flag at `+0xE6C0` unset): the game never
  mounted a save (no `EnsureSaveData`, no fsp-srv 51).
- Chain, found with the new `SWR_TRACE_DYN` (below): `boot.nro` calls `bq::AccountMgrModule::EntryAppBootAccount`,
  which takes the uid stored at `nn::bezel::AccountModule` impl `+0` and asks the save manager to load it
  (`0x8245e90`). That needs `AccountModule::IsAccountValid(uid)`; the stored uid was **zero**, so it failed, the slot
  flag was cleared and nothing was mounted.
- Why zero: `AccountModule` init (`0x878e3e0`) first calls `nn::account::PopOpenUsers` (acc:u0 131
  `ListOpenContextStoredUsers`). Only if that returns nobody does it call `OpenPreselectedUser` and store that uid.
  The runtime answered 131 with the user, which on a console only happens when another application stored an open
  user before jumping to this one. The game took the "relaunched" path and never stored a boot account.
- Fix (`runtime/svc_core.c`): cmd 131 returns an all-zero list, as on a normal launch. `SWR_OPEN_CONTEXT_USER=1`
  brings the old answer back in case another game needs it.
- Result: `EnsureSaveData` + `OpenSaveDataFileSystem` at boot, `bqSaveData`/`bqSaveData2` written to
  `<name>_data/save/user/`. L+R loads `menu00.nro`: "How many people will play on this system?", then the Party
  Plaza hub with Mario walking. With a save, the intro shows "−/+ Skip" and + skips it.

### Bug 5: ~40 s freeze when boarding the Party Plaza balloon (fixed)
- `menu01.nro` loads, then no new image for ~40 s; GL thread inside the driver, compile thread on one shader.
- Log: `shader: BRX at 389: no LDC of r12 found before it` and `BRX at 328: no LDC of r9 ...`. With
  `SWR_BRX_DUMP=1` (lists the 64 instructions before such a BRX) neither register is written in those 64: the table
  loads are even further back than on the boards.
- Fix (`runtime/shader.c`): the search runs back to the start of the program (it still stops at another write of the
  register or at BRX/CAL/RET/JMP). No BRX warnings left, no freeze; the balloon tour plays straight through.

### Bug 6: saved parties dated 12/31/1969 (fixed)
- The party list (Mario Party, Offline Data) showed `12/31/1969` for a party saved that day: Unix time 0 shown in a
  US time zone.
- `SWR_TRACE_TIME=1`: the game never asks the time service for the clock; it maps the time shared memory (`time:u`
  cmd 20) and the SDK reads clocks from it. `SWR_TRACE_FN=a6bd2d0` (`GetStandardUserSystemClockCurrentTimespec`, called
  by libc `time()`) returned success with a zero timespec.
- `SharedMemoryClient::CalculateSystemClockCurrentTimespec` reads the 17.0+ `ContinuousAdjustmentTimePoint` at
  shared memory 0xD0: `{u32 counter; pad; 2 x 0x38}`, each `{clock_offset, multiplier, shift, SystemClockContext}`,
  and fails with 52340 unless the context's steady clock id (+0x28) matches the user clock's. The runtime wrote the
  entries 0x48 apart with the id at +0x20, so the check always failed and `time()` gave 0.
- Fix (`runtime/svc_core.c`, `time_shm_update`): 0x38 entries, id at +0x28, the rest zero (no adjustment). `time()`
  now returns the PC's time. Checked: a party started after the fix is listed as 11/24/2026 (its save called
  `StandardUserSystemClock::GetCurrentTime`, which returned the PC time). The game stamps the date when a party is
  created, so parties started before the fix keep 12/31/1969.

### Bug 7: dialog boxes, text, dice counters and some characters invisible (fixed)
- Reported from a playthrough: no text when Toad talks in the plaza or at a shop, no remaining-spaces number while
  walking, no coin change popup, Mario invisible in character select and on the board.
- F5 trace of the plaza with Toad talking: the dialog's draws are all there (window, 50-glyph text draw, choices),
  each with `result rt0: (no change)`. No scissor, no stencil, depth test off, alpha 1. Their vertices come out at
  clip z -0.003 (layout projection `cb3 d[2].w = -0.003024`), with the depth mode zero-to-one.
- `SET_VIEWPORT_CLIP_CONTROL` (method 0x1138, register 0x44E) was ignored. Its `GEOMETRY_CLIP` field decides
  near/far clipping: only PASSTHRU, FRUSTUM_XYZ_CLIP and FRUSTUM_Z_CLIP clip in z; the reset value 0 (WZERO_CLIP),
  which Jamboree leaves set, clamps depth. GL clipped the whole UI layer at z < 0.
- Fix (`runtime/gpu_gl.c`, `apply_state`): `GL_DEPTH_CLAMP` unless GEOMETRY_CLIP is 1, 3 or 5 (yuzu's
  `depth_clamp_disabled`), with the register in the state signature. `SWR_NO_DEPTH_CLAMP=1` turns it off.
- Checked: Toad's plaza dialog ("Climb aboard the Hot-Air Balloon...") and choices, the Item Shop bubble, Toad's
  "not enough coins" message, dice counters over the players, and Mario, Luigi, Daisy, Waluigi, Toadette and Toad in
  character select all render. Title, menus and the board are unchanged otherwise.

### Bug 8: title movie and attract cutscene at ~10-20 FPS (fixed)
- The movie decodes at 60 pictures a second (`video: N NVDEC jobs`), but the VIC writes each picture into guest
  memory on the CPU, and the texture over it was only re-checked on the texture cache's schedule (every 4-20 frames).
- Fix (`runtime/host1x.c`, `runtime/gpu_gl.c`): the VIC reports each output picture (`gpu_note_ext_write`); a texture
  over it is checked again on its next use. A 7 s recording of the cutscene went from 224 to 288 distinct frames,
  and the gaps of 3-4 frames between pictures are gone.

### Bug 9: board spaces missing, part 1 (target-less draws)
- Each board frame starts with two draws that have no color or depth target and no fragment shader: vertex shaders
  (`9fe02e952fb8622e`, 62 vertices; `3247054149f32e6f`, 3 vertices) that write storage buffers (an `atomicAdd`
  counter, then 0xB4 bytes of arguments the next GPFIFO entry feeds to a draw macro). The runtime dropped every
  target-less draw (`DRAW SKIPPED: no target`).
- Fixes: such draws now run with `GL_RASTERIZER_DISCARD` (`SWR_NO_SIDE_DRAWS=1` drops them like before), and a draw
  held back for instance merging is flushed before a GPFIFO entry is read, so reading the entry waits for the draw's
  storage writes (`SWR_NO_ENTRY_FLUSH=1` turns that off).
- Result: the space under the current player and some nearby ones render; most of the path's spaces still don't.
  Ruled out: depth bias (no draw uses it), EQUAL-after-prepass depth mismatch (forcing LEQUAL changed nothing), the
  buffer caches (`SWR_VB_FULLCHECK=1`, `SWR_NO_SSBO_CACHE=1`), zero-length vertex streams, occlusion queries (the
  runtime always reports visible). The rest was bug 10.

### Bug 10: most board spaces missing (flow instructions ignored their condition codes)
- Evidence: the target-less pass `9fe02e952fb8622e` is GPU culling, one vertex per board object (80 byte records):
  frustum test, then a distance bucket 0..2, an `atomicAdd` on that bucket's counter (`532b7d100`, 3 words) and the
  record copied into a per-bucket instance list (`53351b700`, 128 slots per bucket). `3247054149f32e6f` then copies
  the counters into 9 indirect draw commands at `532b7d200` (3 meshes x 3 buckets, `count, instances, first, base
  vertex, base instance`); the draw macro reads them and the space shaders (e.g. `b5973422978f2692`) take their
  matrix from slot `gl_InstanceID + base instance` (NVN keeps the base instance in `c0[0x644]`). In a trace the
  counters were `(0, 2, 42)` but every bucket 2 command had 0 instances: most spaces were in bucket 2.
- Cause: the copy loop ends with `ISET.CC RZ, R0 >= N` then `@!P0 EXIT CC.NE` (exit only when all N are done). The
  translator ignored the condition code test of flow instructions and the `.CC` of `ISET`, so the EXIT always ran and
  the last bucket's count was never written. Found with `_work/sdis.py` (a listing from the translator's opcode table).
- Fix (`shader.c`): BRA/EXIT/BRK/CONT/SYNC/KIL/RET test their condition code (`cc_test_expr`, the same flow-test
  table yuzu uses, overflow taken as clear); a flow instruction with a test no longer counts as unconditional (stack
  resolution, dead code, structured if/else); `ISET.CC` and `FSET.CC` set the Z and S flags. Translated shaders are
  cached by their GLSL, so the old ones are rebuilt by themselves.
- Result: the spaces along the paths render, near and far, at 60 FPS.

### Bug 11: button prompts showed the Switch positions with an Xbox pad
- Symptom (playtest): with `pad_buttons=0` (Xbox A = A) the "View Board" and dice prompts showed the four-dot icon
  with the Switch position lit, so they pointed at the wrong Xbox button.
- Evidence: the prompts are characters of the picture fonts `Parts.lyt/Font/bqfont_{small,middle,large}_extension.ffnt`
  (in `romfs/Archive/font~font.nx.bea`, zstd). Each has one BC7 sheet (512x1024, 512x1024, 1024x1024 x2 layers) with
  cells (cw+1)x(ch+1) apart from (1,1), rows stored bottom-up. Glyphs 6-9 are the A/B/X/Y letter buttons, glyphs 2-5
  the diamond with the right (A), left (Y), top (X), bottom (B) button lit; the same order in all three sizes. The
  playtest screenshot's "View Board" icon has the left dot lit (Switch Y).
- Fix (`gpu_gl.c`, `k_icon_sheets`): the three sheets are recognised at texture creation by a sampled hash of their
  guest memory, uploaded decoded (BC7 -> RGBA8 on the CPU, as the BCn fallback already does) and, while the pad is
  mapped by label, cells 2<->5 and 3<->4 are swapped (right<->bottom, left<->top), which is where Xbox A/B/X/Y sit.
  The letter icons already match by label. `pad_buttons=1` keeps the original sheet; a change re-uploads it. Nothing
  of the game's art is added or shipped, the cells are only moved. `SWR_NO_ICON_SWAP=1` turns it off.
- Result: on the board turn menu "Board" (Y) shows the top dot and "Dice Block" (X) the left dot. Approach credit:
  mkw-recomp / SavageWindRecomp redraw their games' icon sheets on upload (MIT); this port only moves cells.

### Bug 12: minigame select background black (workaround)
- Symptom (playtest): the "4-Player Minigame" roulette showed on black instead of the blurred board, most of the time.
- Evidence: `SWR_TRACE_ON_FILE=SM_BGM_BD00_MGSEL_ROLL@1200` traced the screen. The background is draw
  `vs bc44ac40d42fc49d / fs 58ee2bd91d125591` sampling a 960x540 R11G11B10F snapshot RT, which held black.
  `SWR_PROBE_FS=974265260d1f959e` showed the copy of the board view (`513010000`, 1152x648) into the snapshot was
  correct (99% non-black). `SWR_WATCH_RT=960x540` then showed the sequence for the new snapshot RT in one frame, all
  on channel 20: created, cleared, copied, **cleared again** (full surface, colour 0, render enable override on).
  Earlier snapshots for other menus get one clear before the copy and are fine.
- Cause: not found yet. The second clear is what the command stream says; why the console keeps the copy (or does
  the copy later) is open. Candidates: CPU-side capture logic that depends on GPU fence/semaphore timing.
- Workaround (`gpu_gl.c`, clear path): a colour clear of an RT whose last write in the same frame was the snapshot
  copy shader is skipped (`SWR_KEEP_DRAWN_FS=<fs>` picks the shader, `0` turns it off). With it the board shows
  behind "Bonus Minigame!", the roulette list and the result banner.

### Bug 13: the background test runner could close a live game (fixed)
- The runner stopped every process named `Recomp` before launch, including an existing play session. It also
  stopped its own process forcibly at the time limit, bypassing runtime shutdown.
- The runner now refuses to start if Recomp is active. It requests a normal exit at the end and force-stops only
  its test instance if the request fails or the instance is still running after five seconds. `-GameDir` lets
  repeat tests use a separate save and configuration while reading the dump in place.
- During the round 3 replay, a second invocation was rejected and the first test kept running. At the time limit,
  the test process handled the close request and exited with code 0.

### Bug 14: Waluigi's initial character preview can distort (fixed)
- With Waluigi already highlighted on entry, large triangles obscure the preview across multiple frames. It
  also occurs with a warmed shader cache and with `SWR_VB_FULLCHECK=1`. Moving right to Yoshi and back to Waluigi
  restored the preview in the traced run.
- The F5 captures show the distortion in the 1232x440 preview render target, before compositing. It is visible
  after draw 31 and grows after draw 33. Both frames use vertex shader `c97c90f30af7f047`, fragment shader
  `f21a173c54461431` and the same vertex attribute formats.
- Reproduced on initial selection with `SWR_CS_SYNC=1`, `SWR_NO_UBO_RING=1` and `SWR_NO_GLQ=1` in separate
  background runs. Reselecting Waluigi restored the preview in each run.
- Paired mesh captures had identical index data for draws 31 through 33. The only differing vertex stream was
  draw 33 slot 13, a 44-byte-stride buffer at `5bef3e600`. On initial selection, 288 of the 369 referenced
  vertices had a finite position component with magnitude over one million, and 5 had a non-finite position
  component. After reselection, all referenced positions were finite and their component magnitudes were below 3.
- The GPU write log recorded three writes to that range on reselection through `cs_apply`, the shared GPU
  buffer readback path. It recorded no overlapping writes before the distorted draw. The three writes came
  from draws using vertex shaders `9d08ac149b01f6cc` and `3ef66eed5c63a8a4` with the empty fragment shader.
- With `SWR_SYNC_SHADERS=1`, all three writes ran on first entry and the preview rendered correctly. While
  shaders were pending on the default asynchronous path, those one-time draws could be skipped. The renderer
  now uses its existing bounded shader wait for draws that write storage buffers, even when they have render targets.
- Verified correct first-entry Waluigi previews in background tests with an empty runtime shader cache and a
  warmed cache. Three shader compiler threads were active in both runs. The rebuilt runtime also resumed a
  Roll 'em Raceway save and reached the turn 1 dice menu in a background replay.

### Bug 15: cached shader jobs looked unfinished in compile traces (fixed)
- Board-load triage needs to distinguish driver time spent loading a binary from time spent compiling source.
  `SWR_CMP_LOG=1` labeled all cache attempts as binary work and omitted the completion line on cache hits.
- The shader worker now identifies cache attempts and logs completion times for successful binary loads and
  source compiles. This fixes the diagnostic output used to correlate worker jobs with presentation gaps.
- The rebuilt runtime reported both completion types during the background board tests.

### Bug 16: first-visit character switching can freeze on NVIDIA OpenGL (fixed on the tested Windows driver)
- The original roster replay recorded a 1.33 s frame gap as three source shader jobs completed. Clearing only
  the runtime shader cache did not reproduce it. Appending a diagnostic comment to those three GLSL sources
  forced a driver cache miss and reproduced a 1.23 s gap with no required-draw wait over 20 ms in that window.
- One in-process worker still produced a 1.09 s gap. Its trace put 756 ms into linking the fragment shader
  (`c47f8e986c9e72e5`); the two vertex links took about 260 and 211 ms. The render context was held up during
  compilation in another context of the same process.
- The existing helper process isolated the compilation from rendering, but routing every job to it caused
  multi-second pauses before the roster. Windows NVIDIA auto mode now queues separable shaders of 48 KiB
  or more for the helper when their draws can be skipped while compiling. The first compiler worker stays
  available for the regular queue. Explicit `shader_process=0` or `1` still selects in-process or full helper mode.
- In a forced-cache-miss background replay, all three shaders compiled in the helper. The same switching
  sequence stayed below 50 ms per frame gap even while the fragment shader took 856 ms. Waluigi's initial
  preview rendered correctly and the title-to-roster replay peaked at 166 ms.
- A clean build with an empty runtime shader cache rendered the initial Waluigi preview and resumed a
  Roll 'em Raceway save through active turn 1 play.

### Esc quit the game on a stray press
- Esc now has to be held 1.5 s (the window title shows "Hold Esc to quit" while it is down). Closing the window and
  Alt+F4 work as before.

### Recompiling with the hints file: slower, not adopted
- Rebuilding `Recomp_code.dll` with `Recomp.hints` (109 addresses) took the board from 60 to ~42 FPS with the GPU
  thread ~25% busy (CPU bound), and fixed nothing visible. The previous DLL stays.

### Controller: Xbox A acted as Switch B
- The XInput mapping was by position (Xbox B = Switch A), so the confirm button was on the right and Xbox A went back.
  New `[Controls] pad_buttons`: 0 (default) maps by label (Xbox A = A confirms), 1 restores the Switch positions.
  Jamboree's four-dot prompts are position glyphs; with `pad_buttons=0` they are swapped to the Xbox positions (bug 11).

### Bug 17: the results star graph had no lines (fixed)
- Owner-confirmed in the 2026-11-26 Roll 'em Raceway playthrough: the Star Graph (finale and results) showed axes
  and grid but no line for any player. Reproduced every time from a turn-10 save (`raceway-finale` in the local save
  library), about 7 minutes of background play to the results.
- F5 trace: four draws, one per player, `vs=c3378efdaffd03aa fs=df003795311b14d2`, 14 vertices, topology 11 (line
  strip with adjacency), and `result rt0: (no change)`. The vertex data was right (one point per turn). The fragment
  shader draws an anti-aliased stroke from flat segment ends and a per-pixel position, which only a geometry shader
  supplies, and stage 4 (geometry, `cfg=41`) was enabled.
- The geometry shader (`6fc84d3a1da6997a`, lines adjacency in, triangle strip out) had three untranslated
  instructions: `VMAD`, `VSETP`, `ISBERD`. They turn the input vertex number 0..3 into a vertex handle. Once they
  were translated, the attribute loads still read vertex 0: `ALD Rd, a[Ra + off], Rv` takes the vertex in `Rv`
  (bits 39-46), and the translator took `Ra` (bits 8-15, RZ here). Every vertex of every segment was vertex 0, so the
  strokes had no area.
- Fix (`shader.c`): `VMAD` and `VSETP` (byte/half selects, signedness, the `.shr7`/`.shr15` scale; fields from
  envytools `gm107.c`), `ISBERD` default mode passes its source through, and a geometry shader `ALD` uses `Rv` as the
  vertex (falls back to `Ra` when `Rv` is RZ, the old behaviour). The shader cache is keyed by the translated source,
  so stale programs aren't reused.
- Result: the graph draws its four lines (flat at 0 stars, then the bonus star step at turn 10). No other
  untranslated instruction was left among the 709 shaders that run used.
- A first guess (the provoking vertex, register `0x5A1`) was ruled out: the game sets it to "last", GL's default.

### Bug 18: black horizontal stripes across the sea at Minigame Bay (fixed)
- Found in the 2026-11-26 minigame review: on the Free Play pier and the minigame list, the open sea behind the pier
  was banded with black rows, denser towards the horizon. The beach view of the same visit was clean.
- F5 trace: the bands appear at draw `vs=01f78bc6b3571c2b fs=5c4e5aab06012d80` (the sea surface) on the 1152x648
  scene target. Its slot 0 is the bound depth buffer (`501400000`) read through TIC format `0x0e` (G24R8) with the R
  component UINT and the swizzle taking R: the stencil, as an integer. The shader does `texelFetch`, tests
  `value & 0x80` and discards where it's set (stencil bit 7 masks the pier and characters out of the water).
- Cause: GL returns the depth from a depth-stencil texture unless `DEPTH_STENCIL_TEXTURE_MODE` is `STENCIL_INDEX`,
  and the translator declared a float sampler. The shader tested bit 7 of the depth's float bits, which flips with
  distance: black rows wherever the bit was set.
- Fix (`gpu_gl.c`): a depth-stencil texture read through a TIC whose first swizzle source is a UINT component is a
  stencil read. The fragment shader key marks that slot as an integer texture (`usampler2D`), and the bind uses a
  texture view of the depth texture with `DEPTH_STENCIL_TEXTURE_MODE = STENCIL_INDEX` (kept per texture, nearest
  filtering). `SWR_NO_STENCIL_VIEW=1` turns it off.
- Result: the sea renders clean on the pier and behind the minigame list. The log notes the first stencil views
  (`gpu: depth-stencil ... read as stencil`).

### Bug 19: motion minigames could not be started (fixed, F6)
- Found in the 2026-11-26 Minigame Bay sweep: Tilt-a-Golf, Night Lights, Hammer It Home, Twist and Sort, Shuttle
  Scuttle, Tiny Triathlon and Pickax Dash (the second row of the "All" list) answer Play with "Use one Joy-Con to play
  motion minigames. Change controller settings?". Yes and No both returned to the minigame card.
- Evidence: the runtime reported controller 1 as a Pro Controller only, with a six-axis sensor fixed at rest, and
  answered the controller applet with "1 player, controller 1" without changing anything. The game calls
  `ShowControllerSupport` from one place (`87f4e94`) with the same arguments (1..1 players, single mode and dual both
  allowed) at boot, on menu changes and on Yes, so the call can't tell that a motion minigame wants a Joy-Con.
  `SWR_TRACE_FN` on the `nn::hid` six-axis functions showed the game takes handles for Handheld and JoyRight at boot
  and reads both every frame through `GetSixAxisSensorStates`.
- Fix (`svc_hid.c`, `kernel.c`, `backend_win32.c`): a single Joy-Con mode for controller 1. It reports style JoyRight,
  device type right Joy-Con, single assignment, the right-connected attribute, its own button LIFO and six-axis LIFO,
  and `IsSixAxisSensorAtRest` false. The six-axis state follows the right stick (orientation matrix, gravity,
  angular velocity and angle, 1/60 s steps), and the right stick button adds a shake. The handheld sensor gets the
  same motion. Turned on by F6 or `single_joycon=1`, by `SWR_SINGLE_JOYCON=1`, by `SetNpadJoyAssignmentModeSingle`
  on controller 1, or when the game allows only single Joy-Con styles; `SetNpadJoyAssignmentModeDual` and F6 turn
  it off. `SWR_NO_SINGLE_JOYCON=1` disables it.
- Two things the first try got wrong, kept here: switching on every applet call that allowed single mode left the
  title screen waiting for L+R (a right Joy-Con has none: SL/SR now stand in). Pushing the handheld sensor twice per
  sample (at rest, then moving, same sampling number) froze the game at boot; it gets one entry per sample now.
- Result: after F6, Tilt-a-Golf starts without the prompt. A drops the ball, the right stick tilts the board and the
  ball rolls. Menus and an ordinary minigame (Lumber Tumble) work in this mode with the normal keys.

### Bug 20: the game froze when the audio device stopped taking sound (fixed)
- Found in the 2026-11-26 minigame sweep: during Blame It on the Crane, about 86 minutes into the session, the frame
  rate fell from 60 to 17 and 8 FPS and then stopped. The log's hang report: "the GPU finished everything sent to
  it (the stop is on the CPU side)"; the main thread waited on a light event that thread 86 signals, and thread 86
  waited on the sound system. A native stack dump (`_work/stackdump.exe` + `resolve.py`) of the frozen process showed
  the game's audio thread in `swr_audio_submit_at` (from `audren_update`), sleeping until the output queue had room,
  and the output worker in `host_write`, waiting for the waveOut device to hand back a buffer.
- Cause: the Windows audio device stopped consuming buffers (the likely trigger is the audio endpoint going away
  with no one at the PC, such as a monitor with HDMI/DP audio going to sleep). Both waits had no limit, so the
  device's stall stopped the audio thread and with it the whole game.
- Fix (`audio.c`): a buffer the device holds 250 ms gets `waveOutReset`; still held 500 ms in, or 200 ms of write
  errors, closes the device and opens the default one again. With no device, audio is dropped and a new one is tried
  every 2 s. The game's side waits at most 100 ms without progress, then drops the rest of that packet. Each step
  logs an `audio:` warning.
- Result: `SWR_AUDIO_STALL_AT=50` (pauses the device after 50 s, a stand-in for a dead endpoint) logs "stopped
  taking buffers, reset" 0.3 s later and the game stays at 60 FPS. The old code waits forever at that point.

### Build fixes (the source as shipped didn't build with the bundled GCC 16)
- `plat.c`: missing `#include <math.h>`; `svc_core.c`: `ipc_warn_once` used before its declaration.
- `plat.c`: prebuilt `vp9/win/libvpx.a` calls `_setjmp`, which the UCRT import library no longer exports; a jump shim
  to `__intrinsic_setjmp`.
- The GCC from `Install.bat` has no C++ compiler (the runtime needs it for `bcn/*.cpp`): `_work/get_gxx.py` adds
  conda-forge `gxx_impl_win-64 16.2.0` (sha256-checked) to `gcc/`. This belongs in `tool/get_deps.py`.
- The rebuilt runtime is ~5 MB; the shipped one was ~20 MB because it also had the optional `renderer=vulkan/eden`
  libraries, whose prebuilt archives aren't in this package. `renderer=opengl` (default) is what's used.

## 3. Features added

- `game_dump=` (new `[Game]` section in the game's `.ini`): exefs and romfs are read from the user's own extracted
  dump where it is. Saves, `sdmc` and fonts stay in `<name>_data/`. If neither `game_dump` nor `<name>_data/` has
  `exefs/main`, a folder picker asks for the dump (3 tries, then a clear error). The dump's `main.npdm` program id
  must match the recompiled code's title id.
- `switchrecomp.py --link`: recompile without copying exefs/romfs (5.4 GB), writes `game_dump=` into the `.ini`.
- Motion minigames (bug 19): **F6** switches controller 1 between a Pro Controller and one Joy-Con (R) held on its
  own, saved as `single_joycon=0/1` in the `.ini`. As one Joy-Con, the right stick (IJKL keys, or the mouse in mouse
  mode) tilts the controller up to about 60 degrees and the right stick button (**O** on the keyboard) shakes it.
  L/R press the Joy-Con's SL/SR, and the d-pad (arrow keys) moves its stick. When the game holds it sideways (menus,
  most minigames) the face buttons are mapped to where they sit on a sideways Joy-Con, so A stays A. F1 lists F6 and
  the new **U/O** stick-click keys.

## 4. Diagnostic switches added

| Env var | Effect |
| --- | --- |
| `SWR_DRAW_SYNC=1` (with `SWR_NO_GLQ=1`) | `glFinish` after every draw, logs each draw and the slow ones |
| `SWR_CMP_LOG=1` | logs shader worker jobs. `try binary` is a cache attempt. Completion labels distinguish binary loads from source compiles |
| `SWR_IPC_LOG=1` | logs every IPC call and result except hid/audio/nvdrv |
| `SWR_TRACE_DYN=lo-hi,clo-chi` (hex) | logs each function in `[lo,hi)` the first time it's called through the dispatch table from a return address in `[clo,chi)` (calls between modules, e.g. `boot.nro` → main, main → sdk) |
| `SWR_OPEN_CONTEXT_USER=1` | acc:u0 131 answers with the user again (pre-bug-4 behaviour) |
| `SWR_BRX_DUMP=1` | with `no LDC found`, lists the 64 instructions before the BRX |
| (always) `shader: BRX at ...` | why a jump table couldn't be resolved |
| (always) `pause: N s without a new image` | every gap over 1.5 s between frames (loads, stalls), with its length |
| `SWR_SLOW_FRAME_MS=50` | report frame gaps over 50 ms in `performance.txt`, with time since launch, frame number, GPU-thread work and shader queue depth. Default is 120 ms, up to 300 reports per run |
| `SWR_TRACE_TIME=1` | logs every time service call (clock, time zone, shared memory) |
| `SWR_TRACE_FN=addr,...` | (existing) now also shows the 16 bytes at the first argument after the call, for out pointers |
| `SWR_INPUT_UNFOCUSED=1` | keys posted to the window count while it isn't in front (`run.ps1` sets it) |
| `SWR_NO_DEPTH_CLAMP=1` | ignore the viewport clip control and clip in z (pre-bug-7 behaviour) |
| `SWR_NO_SIDE_DRAWS=1` | drop draws without targets even when they write storage buffers (pre-bug-9) |
| `SWR_NO_ENTRY_FLUSH=1` | don't flush a held-back draw before reading a GPFIFO entry (pre-bug-9) |
| `SWR_VB_FULLCHECK=1` | hash every cached vertex/index/storage buffer on every use (finds stale buffer bugs) |
| `SWR_ZALWAYS_FS=<hash>` | draws with that fragment shader skip the depth test (tells a draw lost to depth from one with no pixels) |
| `SWR_TRACE_ON_FILE=<romfs path part>[@ms]` | F5 trace that long after a romfs file is first read (screens that are hard to time, e.g. a music file) |
| `SWR_TRACE_TEX=1` | F5 traces also save a thumbnail of every sampled RT at each draw (`dNNNN_texK.ppm`) |
| `SWR_PROBE_FS=<fs>[,<rt addr>]` | after each draw with that fragment shader, log the average colour of its target (and of the given RT) |
| `SWR_WATCH_RT=<w>x<h>` | log what happens to RTs of that size: created, parked, revived, cleared (with the clear's registers), dropped, freed; `SWR_WATCH_RT_TRACE=1` traces the frame after a second clear in one frame |
| `SWR_NO_ICON_SWAP=1` | keep the game's button icon sheets as they are (bug 11) |
| `SWR_BACKGROUND=1` | background test mode: the window sits past the right edge of all monitors, is never activated, has no taskbar or Alt+Tab entry; sound is silenced (still sent to the device so audio timing is unchanged); the real pad, mouse and keyboard are ignored, only posted keys count. F8 captures and logs work as usual. `run.ps1` sets it unless `-Foreground` |
| `SWR_MUTE=1` | silence only, everything else as normal |
| `SWR_SHOT8_EVERY=N[@s[,max]]` | an F8 capture every N presented frames, optionally from s seconds after the first frame and up to max captures (default 40): shows frame by frame how long a transition or glitch lasts |
| `SWR_SHOT8_FLAG=N` | while a file `burst.flag` exists in the game folder, an F8 capture every N presents (a test script creates it when OCR sees the screen it wants) |
| `SWR_TRACE_EVERY=N[@s[,max]]` | an F5 trace every N presents from s seconds, up to max (default 20) |
| (F5 trace) | line draws also list the line widths, the shader stage registers and the first 16 vertices' float attributes; every draw lists the provoking vertex |
| `SWR_AUDIO_STALL_AT=<s>` | test: pause the Windows audio device once after s seconds, to check that a stalled device doesn't freeze the game (bug 20) |
| `SWR_SINGLE_JOYCON=1` / `SWR_NO_SINGLE_JOYCON=1` | start controller 1 as one Joy-Con / never switch to it (bug 19) |
| `SWR_TRACE_FN_EVERY=N` | with `SWR_TRACE_FN`, also log every Nth call with the 0x60 bytes its first argument points to (sensor states). `SWR_TRACE_FN` now also logs each new return address after the first 8 calls |
| (log) `hid:` | controller applet calls with their arguments and caller chain, single Joy-Con mode on/off, Joy-Con hold type |
| `SWR_NO_STENCIL_VIEW=1` | read depth-stencil textures as depth even when the TIC asks for the stencil (pre-bug-18) |
| `SWR_KEEP_DRAWN_FS=<fs>` / `0` | which copy shader protects its RT from a clear later in the frame (bug 12); 0 = off |
| `_work/sdis.py <sh_*.bin>` | rough listing of a dumped shader (word index = `case N` in the GLSL, guards, CC tests) |
| (F5 trace) | each draw also lists scissor, clip control, depth bias, stencil function, vertex attribute formats; a skipped target-less draw lists its targets, stream-out state and storage writes and dumps its vertex shader |

Tools in `_work/`: `run.ps1` launches in the background unless `-Foreground` is given. It posts keys to the game
window with `Q+E` chords and `vk@ms` holds, uses the runtime's F8 capture for screenshots, and requests a normal exit
when time is up. It refuses to start while Recomp is running. Use `-GameDir` for a separate test install that links
the dump in place and uses its own save directory. Other tools include `fn.sh` (print the generated C of one function), `dynsym.py`
(symbolize `SWR_TRACE_DYN` output), `build.py`
(rebuild the runtime, ~30 s), `stackdump.c` + `resolve.py` (every host thread's stack, symbolized), `glcompile.c`
(compile one GLSL file on the real driver and time it), `syms.py` (search the dump's symbol tables), `thr.py`
(symbolize `threads.txt`), `get_gxx.py`.

## 5. What the finished product is

A Windows build that plays Jamboree from the user's own dump, without shipping anything of Nintendo's.

What the user does:
1. Dumps their own copy of the game and the 1.1.0 update on their own Switch, extracts `exefs/` and `romfs/` with
   their own keys (hactool), as in `README.txt`.
2. Runs the package's tool once: it recompiles `exefs/` into `<Game>_code.dll` on their PC (GCC, a few minutes) and
   links their dump folder (`--link`, nothing copied).
3. Starts the game. Settings in `<Game>.ini`; saves in `<Game>_data/save/`.

What the distributed package contains (no game data, no game code):

| Ship | Why |
| --- | --- |
| `SwitchRecomp.exe` (tool), `switchrecomp.py`, `a64.py`, `codegen.py`, `nxloader.py`, `brt.py`, `tools_sym.py` | the recompiler that turns the user's own exefs into a DLL locally |
| `bin/runtime_win64_win32.exe` | the runtime (OS services, GPU → OpenGL, audio, video) with the fixes above |
| `runtime/` source, `LICENSE.txt`, `NOTICE.txt`, `README*`, `CHANGELOG.txt` | AGPL v3 requires the source; NOTICE requires the MZ Labs credit and startup screen |
| `Install.bat`, `tool/get_deps.py` | downloads Python and GCC (+ g++) on the user's PC, hash-checked |
| `tcc/` | small compiler fallback (LGPL) |
| `docs/JAMBOREE_PORT.md` | this file |

Never shipped (each one is Nintendo's work or derived from it):

| Do not ship | What it is |
| --- | --- |
| `Recomp/exefs/`, `Recomp/romfs/`, `Recomp/control*` | the dump itself (code, 5.4 GB of assets, icon) |
| `games/Recomp_data/` | a copy of the dump, plus the user's saves |
| `games/Recomp_code.dll`, `games/Recomp_build/` | the game's code translated to C and compiled: a derivative of the game's code |
| `games/shader_cache/`, `games/captures/`, `games/*.log`, `threads.txt`, dumped `shader_*.glsl` | the game's shaders, frame dumps, logs |
| `games/Recomp.hints` | addresses inside the game's code (generated per user) |
| Nintendo fonts, keys, firmware | never needed: the runtime has its own font fallback |

Rule: everything the game needs is read from the user's own dump at build or run time. A release must pass a check
that no file in it came out of the dump (`.gitignore` here already excludes `games/`, `gcc/`, `python/`).

## 6. Files needed at run time (per user install)

```
<Game>.exe                 runtime (copy of bin/runtime_win64_win32.exe)
<Game>_code.dll            built locally from the user's exefs
<Game>.ini                 options; [Game] game_dump= points at the user's dump
<dump>/exefs/main, main.npdm, rtld, sdk, subsdk0           user's dump (read in place)
<dump>/romfs/...           user's dump: Archive/, movie/, nro/ (boards + minigames), stream/, boot.nbinit, ac.nx.archiveconfig
<Game>_data/control.nacp, icon_AmericanEnglish.dat         title and icon for the tool (copied, user-local)
<Game>_data/save/          created by the game
```

Note: the minigames and boards are NROs in `romfs/nro/NX_Release/`. The recompiler compiles them too
(`nxloader.romfs_nros`), so the romfs NROs are part of the code build input as well.

## 7. Playtest log (found, not all fixed yet)

Everything seen in manual and scripted play goes here first, fixed or not, so nothing gets lost.

| Date | Where | What | State |
| --- | --- | --- | --- |
| 2026-11-25 | board prompts | four-dot icons showed Switch positions with an Xbox pad | fixed (bug 11) |
| 2026-11-25 | minigame select | black background instead of the board | worked around (bug 12), cause open |
| 2026-11-25 | anywhere | a stray Esc closed the game | changed: hold 1.5 s |
| 2026-11-26 | character select | rapid switching hit a 1.33 s frame gap alongside three roughly 1.29 s shader compiles. The same input schedule on a warmed cache had no reported gap over 50 ms during switching. Waluigi's preview distorted on entry in both runs. | preview distortion and the reproduced NVIDIA hitch are fixed (bugs 14 and 16) |
| 2026-11-26 | board load and general play | first board load had a 449 ms frame on the installed runtime and a 468 ms frame on the rebuilt runtime. The latter included 141 ms of texture work and 47 ms of shader work on the GPU thread. | load hitch reproduced. The rest of the frame and the reported spikes during ordinary play are still open |
| 2026-11-26 | resume screen | the existing turn-2 party shows 12/31/1969 on the rebuilt runtime | matches the legacy save behavior in bug 6. The stored date belongs to party creation and is retained on resume |
| 2026-11-25 | resuming a party | a few white frames (~2 s) between "Continue?" and the board | to check against the console (probably the load fade) |
| 2026-11-26 | Granite Getaway | on the practice screen, a 1.6 s scripted Plus and Minus chord started the actual minigame. The replay reached the outdoor bridge section. | scripted start verified. Return to the board and physical controller input still need a check |
| 2026-11-26 | board | a waiting player on a far space looked see-through in an earlier playtest. Mario rendered opaque in the sampled turn-2 view across the mushroom platforms. | exact camera and position from the report still need a reproduction |
| 2026-11-26 | results (Raceway, owner-reviewed) | Star Graph empty: no player lines, in the finale and on the results screen | fixed (bug 17) |
| 2026-11-26 | board turn start (owner-reviewed) | big see-through character (Waluigi, Peach) over the board, see-through karts | frame by frame (capture every 2nd frame): a crossfade from the previous player's shot to the next player's, 20 frames (0.33 s), ending clean. Looks like the game's own transition caught mid-way; owner to compare with the console |
| 2026-11-26 | turn banner (owner-reviewed) | "Your turn" bars show without their text; a highlighted Bowser-space row ("Lose 15 coins") lost its text | frame by frame: the bars slide in for ~10 frames, then the text types in over ~6 frames. Caught mid-animation; owner to compare. The Bowser-space row is not checked yet |
| 2026-11-26 | finale (owner-reviewed) | "Congratulations!" drawn with letters missing ("n rat ations!") | open: a burst over the finale is still to be taken (letters may pop in one by one) |
| 2026-11-26 | Boo steal (owner-reviewed) | Boo see-through with Waluigi in a bubble during the steal; should be solid | probably the same crossfade (the frame also shows the board doubled); not captured frame by frame yet |
| 2026-11-26 | transitions (owner-reviewed) | fully white frames before minigames and after a duel | frame by frame: before a minigame an iris closes to white, the screen stays white ~1.1 s while the minigame loads, then fades in; after practice a 0.4 s fade through white. Load time may make the white hold longer than on the console |

### Owner manual checks (open)

The owner is checking these by hand against the console. Results go back into the table above.
Review images are in `_work/save-library/review-2026-11-26` (local only, not committed).

| # | Check | What to compare | Owner result |
| --- | --- | --- | --- |
| M1 | Star Graph (finale and results) | player lines draw on both screens after bug 17 | pending |
| M2 | Turn change | the console blends the old player's shot into the next player's for about 1/3 s (see-through characters and karts), rather than cutting | pending |
| M3 | Boo steal | Boo and the bubbled character stay solid; the see-through look is only a short blend | pending |
| M4 | Turn banner | bars slide in empty first, then the text types in | pending |
| M5 | Bowser Space menu | the highlighted row ("Lose 15 coins") keeps its text | pending |
| M6 | Finale | "Congratulations!" shows all letters once its animation ends | pending |
| M7 | Minigame transitions | the iris closes to white and stays white about 1.1 s while the minigame loads; after practice a 0.4 s fade through white | pending |
| M8 | Jr.'s Jauntlet | the arena floor has horizontal scanlines over its pictures (screen effect?) | pending |
| M9 | Rewards screen | the area below the header is plain black | pending |
| M10 | Motion minigames | with F6 (one Joy-Con) the right stick tilts and O shakes; do the 25 motion games feel playable? | pending |

## 8. Next steps
1. Owner checks M1-M10 (section 7): fold the results back into the playtest log and fix what differs.
2. First-entry board stalls (2.7-7.2 s, section 9) and small lag spikes during play: use `SWR_SLOW_FRAME_MS=50` and
   match frame timestamps to asset loads. For the reproducible board load hitch, investigate the time outside the
   GPU-thread categories before tuning texture work.
3. Full 10-turn parties through the results screen, and board-specific events on all seven boards.
4. Bug 12's real cause (why the console keeps the snapshot copy), then drop the workaround.
5. Board: a waiting player (Mario, on a space further down the path) looked see-through. Check whether that's the
   game's own fade or a rendering bug.
6. Plaza overview: the paving around the fountain looks noisy from far away (reported; likely the texture's lower
   mips, ASTC decoded to BC3 on GPUs without ASTC). Not reproduced yet: needs the first-visit plaza tour.
7. Hold-to-start ("-/+ Start!" in minigame practice) and other hold inputs with a real pad.
8. Why the hints rebuild is slower (see above) before using it; audio by ear, performance on long sessions.
9. Packaging: fold `get_gxx.py` into `tool/get_deps.py`, make `--link` the tool's default, and a release check that
   no file in the package came from the dump. `CHANGELOG.txt` has an OpenJamboree section, kept current per change.
10. Fast-forward (F9: 1x/2x/4x) for playtesting: plan and findings in `docs/handoff/fast-forward.md`.

## 9. Board coverage

Background Party Rules smoke tests on Switch 1 v1.1.0 with an isolated save. The first pass checked board entry,
intro dialogue, the turn HUD, spaces and movement. Full parties and later board events remain open.
The game has seven boards. Western Land, Mario's Rainbow Castle and King Bowser's Keep require Silver, Gold and
Diamond Player Rank, respectively. [Nintendo's board guide](https://www.nintendo.com/au/games/nintendo-switch/super-mario-party-jamboree/)
The locked-board run used a local test build that exposed the three boards on the isolated save and ran the
reveal scenes. This covers the board paths after availability checks. Normal achievement progression remains untested.

| Board | Confirmed path | Findings |
| --- | --- | --- |
| Mega Wiggler's Tree Party | Resume, turn 1 and exit to the balloon | Existing coverage includes autosave and a minigame return |
| Rainbow Galleria | New party, turn 1 dice and walking, exit, new save slot dated correctly | Up to 7.2 s without a new frame during first entry. A later run with warmed shader caches had no gap over 1.5 s on entry |
| Goomba Lagoon | New party, turn 1 CPU dice and walking, exit, new save slot dated correctly | Up to 4.6 s without a new frame during board entry |
| Roll 'em Raceway | New party, opening, turn 1 CPU kart movement and coin result | Up to 4.8 s without a new frame during board entry |
| Western Land | Reveal, new party, first CPU movement and Lucky Space roulette | Up to 2.7 s without a new frame during board entry. The slowest source shader job in that window took 1.83 s |
| Mario's Rainbow Castle | Reveal, new party, autosave, turn 1 player dice and walking, exit | Up to 4.6 s without a new frame during board entry |
| King Bowser's Keep | Reveal, new party, Impostor Bowser introduction, turn 1 CPU dice and walking, Creepy Dice Block result | Up to 4.2 s without a new frame during board entry |

On Rainbow Galleria, the stall sample caught the host GL thread in `glCompressedTexSubImage2D` with about
32 MB of queued calls and 14 guest fence writes held behind a compute readback. The timeout released the
held writes. Roll 'em Raceway also logged the compute readback timeout. Both boards resumed rendering.
This identifies where the load stalled in those samples. The cause of the slow driver call is still open.

A follow-up Rainbow Galleria resume used identical save copies and empty runtime shader caches. During the first
20 seconds after opening the board archive, the longest frame gaps were 522 ms with the default configuration
and 498 ms with `SWR_DRV_EXCL=1`. Each run recorded six gaps over 50 ms and none over 1.5 s. This resume test
did not reproduce the multi-second pause from new-party entry. The default driver configuration stays in use.

Later runs started a new Rainbow Galleria party with an empty runtime shader cache, both directly and after
resuming and exiting Mega Wiggler's Tree Party in the same process. The largest recorded frame gaps during
entry were 545 ms and 573 ms, respectively. Texture work on the GPU thread accounted for 267 ms and 298 ms of
those frames. The transition replay ran for about 41 seconds after opening the Galleria archive and logged no
pause over 1.5 s. The original 7.2 s stall remains open.

## 10. Minigame coverage

Minigame Bay, Free Play, "All" list, 2026-11-26/27, background mode with CPU opponents on Easy and the test
player pressing A only when the screen waits. Each game ran from the practice screen to the results menu, with a
capture about every 1.3 s (local only, `_work/save-library/evidence/mg/NNN`). Index = position in the 14 x 8 list.

- **Played to the results: 107 of 112.** The other 5 (indices 73-77) are still locked ("?") on the test save.
- **Pro Controller, 82 games:** every one reached its results menu (or, for 1-player challenges, its score screen)
  with nothing missing or broken in the captures. Luigi Rescue Operation (64) hit the script's 5.5 minute limit:
  it's a room-by-room puzzle the idle test player never solves, and it rendered normally throughout.
- **Motion minigames, 25 games, played as one Joy-Con (F6, bug 19):** Tilt-a-Golf, Night Lights, Hammer It Home,
  Twist and Sort, Shuttle Scuttle, Tiny Triathlon, Pickax Dash, Arch Rivals, Income Stream, Dorrie Pedal-Paddle,
  Robo Arm Wrestle, Coin Corral, Fast Fishing, Roll with It, Rosalina's Radical Race, and the ten cooking games
  (Soup Troupe, Parfait the Course, Whisk Cream, Spread 'n Butter, Short-Stack Chef, Burger Builders, Footlong
  Frenzy, Copycat Curry, En Barb!, On the Beet). All started, ran and finished. Their motion input (the right
  stick) was checked by hand only in Tilt-a-Golf.
- Bugs found and fixed on the way: the sea at Minigame Bay (bug 18), motion minigames (bug 19), and a game-wide
  freeze when the audio device stalled, hit about 86 minutes into the session (bug 20).

For the owner to compare with the console (not known to be wrong):
- Jr.'s Jauntlet (72): the arena floor shows horizontal scanlines over its pictures. It reads like a screen effect.
- Hot Cross Blocks (6): with four CPUs one round lasted 5+ minutes.
- The Rewards / achievement screen: plain black below its header.
