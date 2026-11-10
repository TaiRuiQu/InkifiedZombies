# Original audio / 墨潮原创音频

All recordings in this folder were synthesized specifically for Ink Tide by
`tools/generate_audio.py`; there are no downloaded samples, prerecorded speech,
third-party music excerpts or licensed audio-library dependencies.

The game loads the baked PCM files. Python, NumPy and SciPy are needed only to
regenerate them, not to run the game. The generator is deterministic.

## Score

The score is a 16-bar, 48-second loop at 80 BPM, arranged around a D-minor
pentatonic question-and-answer melody. Four four-bar harmonic phrases move
through D minor, B-flat, G minor and an A suspended return. There are five
phase-aligned music stems and a separate ambience stem:

- `menu.wav`: sparse plucked melody, open-fifth bowed chords.
- `melody.wav`: the battle theme, alternating low and upper string responses.
- `strings.wav`: sustained, overlapping modal harmony.
- `drums.wav`: low war drums, higher answering drums and wooden subdivisions.
- `boss.wav`: faster bowed ostinato, double drums and bronze gong accents.
- `ambience.wav`: stereo wind and sparse high string/chime textures.

`MusicDirector` keeps all five musical tracks running on the same transport;
changing scenes, pausing, opening upgrades or entering a boss encounter only
crossfades their levels. Early waves have a restrained drum layer, later waves
bring it forward. The Music bus has its own user volume. Local weapon reports
briefly duck the score so transients remain readable.

## Sound effects

The 65 compatible sound events include six weapons with three recordings each,
independent soft-body / armor / critical / kill confirmations, health / shield
damage, three reload stages, brass casings, four stone / paper footstep variants,
world enemy callouts and reworked spell / boss / UI effects. Consecutive calls
avoid repeating the same recording. Gun reports combine a sharp initial crack,
low body resonance, cycling mechanical parts and a short courtyard tail.

Local feedback uses `Sfx.play(id, db, pitch)`. World sources use
`Sfx.play_at(id, position, db, pitch)`, which routes spatial voices through
WorldSfx -> Ink -> Master. The small world reverb does not smear local hit
confirmations. A master hard limiter provides peak protection for overlapping
weapons and enemy groups.

## Enemy location cues

Each of the six base sound families has three nonverbal calls (`enemy_<type>`)
and three movement cues (`enemy_step_<type>`). The eight enemy archetypes reuse
these six families: the leaper uses puppet cues and the reaver uses brute cues. All 36 recordings are mono 44.1 kHz
PCM16 for spatial playback. Wraiths rasp and drag their steps; paper puppets
scrape and clack; brutes and the boss have heavier armor / boot transients;
masks use airy cloth sweeps, and lanterns use chain / ring movement sounds.
The two floating types do not receive grounded heel impacts.

Enemy movement cues are admitted from actual displacement by `EnemyAudio`.
The dedicated enemy voice budget does not steal gun-report voices. Sustained
calls follow a live source, cues behind the listener are retained, and solid
walls attenuate / low-pass them. Enemy buses eventually route through WorldSfx
and Ink, so the normal effects volume also controls them.

Regenerate only the 36 enemy recordings without rewriting weapon or music WAVs:

```powershell
python tools/generate_audio.py --enemy-only
```

This incremental mode merges the existing event table and manifest. Its first
run verified all 110 other WAV files were byte-identical. The library now has
146 PCM files and 65 events. `enemy_audio_audit.json` records durations, levels,
variant uniqueness and spectral measurements for the new cues.

## Checks and audition

```powershell
python tools/generate_audio.py --audit-only
& "G:\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/audio_audit.gd
```

`previews/battle_mix.wav` is a ten-second representative stereo battle mix for
listening to the balance. The previews folder is excluded from runtime resource
import. `audio_manifest.json` records sample rates, channel counts, durations,
peaks, RMS and loop seam measurements for all generated WAV files.
