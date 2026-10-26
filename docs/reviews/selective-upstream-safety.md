# Selective upstream safety fixes

This change adapts the bounded crash guards from TheBoredTeam/boring.notch
[9a46aaaf3460](https://github.com/TheBoredTeam/boring.notch/commit/9a46aaaf3460)
and the media timestamp publication optimization from
[3d5843bd7b8b](https://github.com/TheBoredTeam/boring.notch/commit/3d5843bd7b8b).
The existing GPL-3.0 license, upstream copyright headers and credits remain.

- Skip initial single-display window creation when no screen is available.
- Provide fallbacks for unavailable directory URLs and bundle identifier,
  preserving the existing `theboringteam.boringnotch` identity.
- Ignore missing audio resources, retain the current sound during playback,
  and prevent an older sound completion from clearing newer playback.
- Skip FFT processing if setup allocation fails instead of terminating the app.
- Publish the media time anchor when elapsed time, rate, play/pause, or source
  bundle changes. No-op metadata events retain the previous anchor.

The timestamp adaptation uses the existing public media/source logic. No
unpublished audio, shelf, source-selection or gesture work is imported.

## Validation

`python3 -m unittest discover -s tests -p test_selective_upstream_guards.py -v`
compiles the actual AudioPlayer implementation and the production launch and
playback-anchor fragments against controlled inputs. It tests missing audio,
no-screen/main-screen/fallback-screen behavior, no-op timeline events, seek,
rate, pause/resume and bundle-source changes without opening an app, playing
a sound, using a camera or requesting permissions. It also compiles the actual
playback position estimator. Test fixtures are temporary and isolated.

Five changed Swift files passed syntax parsing; the existing stability suite
passed. Full application compilation, DSP allocation-failure injection,
physical camera/display/HDMI/Chrome/drag acceptance and binary release remain
pending. Camera lifecycle migration and the newer upstream beta are outside
this patch. Existing acceptance holds continue to apply.
