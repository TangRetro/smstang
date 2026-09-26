# Branch status: feat/mister-2026-sync — work in progress

This branch is **not finished**. It builds on Console 60K, Primer 25K and Nano 20K with no
timing violations, and has had one round of hardware testing on the **Tang Console 60K** only.

## What it adds (on top of feat/exact-lock-hdmi)

- Exact-lock HDMI (480p, no frame buffer) with 192/224/240-line modes
- Current TangCore firmware protocol (iosys), so the core loads with current firmware
- Pause on SELECT
- From MiSTer SMS (2026): VDP X-scroll latch timing, CPU-visible V counter, sprite X-wrap
  fixes, and the new mapper detection/banking (Codemasters, Korean, 4-PAK, Janggun,
  Wonder Kid, The Castle, Dahjee A)

## Tested on hardware (Console 60K)

- Alex Kidd in Miracle World: title screen clean (sprite wrap fix), Pause works
- Micro Machines, Cosmic Spacehead (Codemasters): boot and play
- Gangcheol RoboCop (Korean mapper): OK
- Fantastic Dizzy: taller 224-line picture, stable
- Sonic, Sonic 2, Out Run (FM): OK

## Known issues / still to do

- **Micro Machines: flickering in the top black area during gameplay** — to fix
- Primer 25K and Nano 20K builds are **untested on hardware**
- Needs more testing across the library before it is merged anywhere
- Not included yet: Game Gear / SG-1000 / BIOS loading (needs firmware support), battery
  saves, PAL output
