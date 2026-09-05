# Enshrouded on macOS with CrossOver: fix for "No graphics driver found"

Enshrouded fails to start under CrossOver on Apple Silicon with
**"No graphics driver found"** (log: `Graphics_NoCompatibleDeviceFound`). This repo
contains a drop-in replacement for CrossOver's bundled MoltenVK that makes the game
run, plus an installer that sets a few tuning variables so it runs smoothly.

Tested on: CrossOver 26.2, macOS 27.0, MacBook Pro M5 Max, Enshrouded build 1024233
(September 2026). It should work on any Apple Silicon Mac with CrossOver 24 or newer.

## Quick start

```bash
git clone https://github.com/PatrickJaiin/enshrouded-crossover-mac-fix.git
cd enshrouded-crossover-mac-fix
./install.sh            # or ./install.sh "My Bottle Name" if your Steam bottle isn't called "Steam"
```

Then fully quit Steam inside CrossOver, start it again, and launch Enshrouded.

The **first session rebuilds every shader in the background** and will stutter
badly for 20 to 30 minutes. Keep playing until the "Compiling shaders" indicator in
the bottom-left corner is gone so the game saves its shader cache. Every session
after that loads the cache and is smooth.

To undo everything: `./uninstall.sh`.

## What was actually wrong

Two separate problems, both inside MoltenVK (the Vulkan-to-Metal layer that
CrossOver uses for Vulkan games):

1. **Missing `drawIndirectCount`.** CrossOver 26.2 ships MoltenVK 1.2.10. Enshrouded
   refuses any GPU that doesn't advertise the Vulkan 1.2 `drawIndirectCount` feature,
   and MoltenVK only gained support for it on its `main` branch in July 2026, after the
   last tagged release (1.4.2). The game log shows:
   ```
   [graphics] skipping device because 'drawIndirectCount' is not supported!
   [graphics] No usable Vulkan device found!
   ```
2. **A SPIRV-Cross bug on one fog shader.** With a current MoltenVK the game starts,
   then crashes while compiling the `VolumetricFog3ViewVolumeIntegrate` compute
   shader. MoltenVK's log reveals:
   ```
   [mvk-error] SPIR-V to MSL conversion error: Maximum compilation loops detected and no forward progress was made. Must be a SPIRV-Cross bug!
   ```
   SPIRV-Cross fixed this on September 3 2026 (commit `83fa691c`), but MoltenVK pins an
   older SPIRV-Cross revision, so a stock MoltenVK build still crashes.

The `libMoltenVK.dylib` in the release is MoltenVK `main` (1.4.3, commit `4aaf714a`)
built with SPIRV-Cross bumped to `83fa691c`. Source for that exact build:
<https://github.com/PatrickJaiin/MoltenVK/tree/enshrouded-spirv-cross-bump>
(one-line change to `ExternalRevisions/SPIRV-Cross_repo_revision`; the binary comes from
that branch's GitHub Actions run).

## Why it was slow afterwards, and what the env vars do

Even with the game running, frame times were bad and the Metal shader compiler was
pegged at 150% CPU all the time. Cause: Enshrouded refuses to load a Vulkan pipeline
cache larger than 1 GiB, and MoltenVK's cache (which stores generated Metal source for
every pipeline) came out at 2.1 GB. So the game deleted it on every launch and
recompiled all shaders during play, forever.

`install.sh` adds these to the bottle's `cxbottle.conf` under `[EnvironmentVariables]`:

| Variable | Value | Why |
|---|---|---|
| `MVK_CONFIG_SHADER_COMPRESSION_ALGORITHM` | `1` | LZFSE-compress shader source in the pipeline cache so it fits under the game's 1 GiB limit and gets reused |
| `MVK_CONFIG_FAST_MATH_ENABLED` | `1` | The game's shaders declare float-controls that force "precise" math in Metal; fast math is noticeably cheaper |
| `MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS` | `0` | Stop blocking the render thread on every queue submit |
| `MVK_CONFIG_USE_MTLHEAP` | `1` | Cheaper memory allocation |
| `DISABLE_VK_LAYER_VALVE_steam_overlay_1` | `1` | Steam's overlay Vulkan layer hooks every present. The Shift+Tab overlay will not work in-game |
| `DISABLE_VK_LAYER_VALVE_steam_fossilize_1` | `1` | Steam's shader-recording layer, pure overhead here |

Other things that help:

- In Steam settings, turn off "GPU accelerated rendering in web views" and "smooth
  scrolling in web views". Steam's web helper otherwise burns a full core while you play.
- In the game, use FSR3 (DLSS and XeSS are skipped on Apple GPUs) and cap your framerate.
- Sound goes to whatever macOS has as the default output device when the game starts.
  If you hear nothing, check that it isn't a headset you aren't wearing.

## Manual install

If you'd rather not run a script:

1. Download `libMoltenVK.dylib` from the [latest release](../../releases/latest) and
   verify it against `libMoltenVK.dylib.sha256`.
2. In `CrossOver.app/Contents/SharedSupport/CrossOver/lib64/`, rename the existing
   `libMoltenVK.dylib` to `libMoltenVK.dylib.cx-orig` and copy the downloaded file in.
3. `codesign --force --sign - <path to the new libMoltenVK.dylib>`
4. Add the env vars from the table above to
   `~/Library/Application Support/CrossOver/Bottles/<bottle>/cxbottle.conf`
   in the `[EnvironmentVariables]` section, one per line, in the form
   `"NAME" = "value"`.
5. Restart Steam in CrossOver.

## Caveats

- Every CrossOver update restores the stock MoltenVK. Re-run `install.sh` after updating.
- The replacement is used by every Vulkan game in CrossOver, not just Enshrouded. It is
  a newer MoltenVK than CrossOver ships, so other games are more likely to improve than
  regress, but if one misbehaves run `uninstall.sh`.
- This is an unsigned, community-built library loaded by CrossOver. CrossOver's wine
  loader is signed with library validation disabled, which is why this works at all.
- Rosetta plus Vulkan-on-Metal is still a lot of translation. Expect well under native
  Windows performance, especially at ultrawide resolutions.

## Rebuilding the library yourself

```bash
git clone https://github.com/KhronosGroup/MoltenVK.git
cd MoltenVK
echo 83fa691cb8606ca4b3af7f13bfcbedd5668f2a3a > ExternalRevisions/SPIRV-Cross_repo_revision
./fetchDependencies --macos
make macos
# result: Package/Release/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib
```

Requires full Xcode. Or push that change to a fork and let MoltenVK's own GitHub
Actions workflow build it, which is how the release binary here was produced.

## License

MoltenVK and SPIRV-Cross are Apache 2.0 licensed by The Khronos Group and The Brenwill
Workshop Ltd. The redistributed `libMoltenVK.dylib` is an unmodified build of those
sources at the revisions listed above. The scripts in this repo are MIT licensed.
