"""Offline original sound design for Ink Tide. No sampled/licensed source audio.
Run: python tools/generate_audio.py [--audit-only | --enemy-only]
Requires numpy and scipy for development only; the game loads the baked WAV files.
Music: D minor pentatonic, 80 BPM, 16 bars / 48 seconds, synchronized stems.
All outputs are deterministic PCM16; music is stereo, spatial sound effects mono.
"""
from __future__ import annotations
import argparse, hashlib, json, math, re, wave
from pathlib import Path
import numpy as np
from scipy.signal import butter, sosfilt

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/audio'
SFX_RATE = 44100
MUSIC_RATE = 22050
BPM = 80
BEAT = 60 / BPM
BARS = 16
MUSIC_SECONDS = BARS * 4 * BEAT
TAU = np.pi * 2
BANK: dict[str, list[str]] = {}
REPORT: dict[str, dict] = {}
ENEMY_TYPES = ("wraith", "puppet", "brute", "mask", "lantern", "boss")


def random_for(key: str) -> np.random.Generator:
    return np.random.default_rng(int.from_bytes(hashlib.sha256(key.encode()).digest()[:8], 'little'))


def clock(duration: float, sr: int = SFX_RATE) -> np.ndarray:
    return np.arange(round(duration * sr), dtype=np.float64) / sr


def noise(duration: float, rng: np.random.Generator, low: float = 60, high: float = 7000, sr: int = SFX_RATE) -> np.ndarray:
    n = len(clock(duration, sr))
    x = rng.normal(0, 1, n)
    high = min(high, sr * 0.47)
    if low <= 0:
        sos = butter(2, high, 'lowpass', fs=sr, output='sos')
    else:
        sos = butter(2, [low, high], 'bandpass', fs=sr, output='sos')
    y = sosfilt(sos, x)
    return y / max(float(np.sqrt(np.mean(y*y))), 0.001)


def tone(duration: float, start: float, end: float | None = None, decay: float = 7, sr: int = SFX_RATE, attack: float = .001) -> np.ndarray:
    t = clock(duration, sr)
    end = start if end is None else end
    # Fast pitch drop then a stable body, instead of a synthetic laser sweep.
    frequency = end + (start - end) * np.exp(-t * 28)
    phase = TAU * np.cumsum(frequency) / sr
    return np.sin(phase) * np.exp(-t * decay) * np.minimum(t / max(attack, 1/sr), 1)


def add(destination: np.ndarray, event: np.ndarray, at: float = 0, gain: float = 1, sr: int = SFX_RATE, pan: float = 0, wrap: bool = False) -> None:
    start = round(at * sr)
    if destination.ndim == 2 and event.ndim == 1:
        angle = (max(-1, min(1, pan)) + 1) * np.pi / 4
        event = np.column_stack((event * np.cos(angle), event * np.sin(angle)))
    event = event * gain
    if wrap:
        ids = (np.arange(len(event)) + start) % len(destination)
        np.add.at(destination, ids, event)
    else:
        n = min(len(event), len(destination) - start)
        if n > 0:
            destination[start:start+n] += event[:n]


def attack_noise(duration: float, rng: np.random.Generator, decay: float, low=60, high=7000, sr=SFX_RATE) -> np.ndarray:
    t = clock(duration, sr)
    return noise(duration, rng, low, high, sr) * np.exp(-decay * t) * np.minimum(t / .0007, 1)


def room_tail(x: np.ndarray, sr=SFX_RATE, amount=.2) -> np.ndarray:
    y = x.copy()
    for seconds, gain in [(.031, .39), (.067, -.24), (.109, .16), (.173, -.095), (.247, .06)]:
        delay = round(seconds * sr)
        if delay < len(x):
            y[delay:] += x[:-delay] * gain * amount
    return y


def master(x: np.ndarray, peak: float, sr: int, loop=False) -> np.ndarray:
    x = np.nan_to_num(x)
    x -= np.mean(x, axis=0)
    if not loop:
        n = min(round(.008 * sr), len(x)//2)
        x[-n:] *= np.linspace(1, 0, n).reshape((-1,)+(1,)*(x.ndim-1))
        n = min(round(.0005 * sr), len(x)//2)
        x[:n] *= np.linspace(0, 1, n).reshape((-1,)+(1,)*(x.ndim-1))
    else:
        # Exact zero endpoints with a short equal-power fade; no hard loop seam.
        n = round(.012 * sr)
        fade = np.sin(np.linspace(0, np.pi/2, n))
        x[:n] *= fade.reshape((-1,)+(1,)*(x.ndim-1))
        x[-n:] *= fade[::-1].reshape((-1,)+(1,)*(x.ndim-1))
    maximum = max(float(np.max(np.abs(x))), 1e-6)
    x = np.tanh(x / maximum * 1.1)
    x *= peak / max(float(np.max(np.abs(x))), 1e-6)
    return x


def write(path: Path, data: np.ndarray, sr: int, loop=False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = np.round(np.clip(data, -.999, .999) * 32767).astype('<i2')
    with wave.open(str(path), 'wb') as output:
        output.setnchannels(1 if data.ndim == 1 else data.shape[1])
        output.setsampwidth(2)
        output.setframerate(sr)
        output.writeframes(pcm.tobytes())
    relative = str(path.relative_to(ROOT)).replace('\\', '/')
    REPORT[relative] = {'seconds': round(len(data)/sr, 4), 'rate': sr,
        'channels': 1 if data.ndim == 1 else data.shape[1],
        'peak': round(float(np.max(np.abs(data))), 5),
        'rms': round(float(np.sqrt(np.mean(data*data))), 5), 'loop': loop,
        'seam': round(float(np.max(np.abs(data[-1]-data[0]))), 6)}


def gun(kind: str, variant: int) -> np.ndarray:
    rng = random_for(f'{kind}:{variant}')
    dur = {'pistol': .54, 'smg': .25, 'shotgun': .92, 'rifle': .82, 'launcher': .85, 'crossbow': .64}[kind]
    b = np.zeros(len(clock(dur)))
    pitch = rng.uniform(.97, 1.03)
    if kind == 'crossbow':
        # Dry latch, flexing bow limbs, a taut string and a brief charged crack.
        add(b, attack_noise(.06,rng,75,1800,11000), gain=.48)
        for harmonic in [1, 2.03, 3.11, 5.08]:
            add(b, tone(.5, 195*harmonic*pitch, 154*harmonic*pitch, 10+harmonic*2), gain=.45/harmonic)
        add(b, attack_noise(.2,rng,20,2800,11000), .035, .23)
        add(b, tone(.18,72,48,19), .015, .32)
    elif kind == 'launcher':
        add(b, tone(.65,130*pitch,42,7), gain=1.2)
        add(b, attack_noise(.3,rng,16,50,1900), gain=.55)
        add(b, attack_noise(.06,rng,63,2100,8500), gain=.48)
        add(b, attack_noise(.18,rng,19,800,4500), .045, .22)
        for f in [327, 683, 1131]:
            add(b, tone(.42,f*pitch,decay=13),.022,.06)
    else:
        body = {'pistol':(185,65,18), 'smg':(240,89,33), 'shotgun':(135,36,8), 'rifle':(176,44,11)}[kind]
        add(b,tone(dur*.8,body[0]*pitch,body[1],body[2]),gain=1.03)
        add(b,attack_noise(.065,rng,82,1100,12500),gain=.93 if kind!='smg' else .66)
        add(b,attack_noise(dur*.68,rng,21 if kind!='shotgun' else 11,65,3200),gain=.46)
        # Separate slide/bolt cycling and reflected courtyard report.
        add(b,attack_noise(.024,rng,110,1700,9500),.037,.25)
        add(b,tone(.075,1280,780,45),.036,.1)
        add(b,attack_noise(dur*.55,rng,9 if kind!='smg' else 24,80,2100),.055,.13)
        if kind == 'shotgun':
            add(b,attack_noise(.12,rng,18,300,2200),.27,.2)
            add(b,attack_noise(.024,rng,90,1600,7500),.39,.27)
    return master(room_tail(b, amount=.34), .85 if kind!='smg' else .73, SFX_RATE)


def impact(kind: str, variant: int) -> np.ndarray:
    rng=random_for(f'{kind}:{variant}')
    dur={'hit_flesh':.26,'hit_armor':.43,'headshot':.27,'kill_confirm':.54,'hurt_flesh':.48,
         'hurt_shield':.45,'melee_hit':.34,'enemy_hit':.34,'impact':.28,'shield_break':.85}[kind]
    b=np.zeros(len(clock(dur)))
    if kind in ['hit_armor','hurt_shield','shield_break']:
        add(b,attack_noise(.08,rng,42,1800,12000),gain=.55)
        for i,f in enumerate([341,719,1297,2113,3277]):
            add(b,tone(dur*.9,f*rng.uniform(.985,1.015),decay=8+i*2),gain=.28/(i+1))
        add(b,tone(.2,135,65,20),gain=.62)
        if kind=='shield_break':
            add(b,attack_noise(.55,rng,7,3000,14000),.035,.25)
            add(b,tone(.7,110,38,5),gain=.45)
    else:
        add(b,tone(dur*.8,160 if kind!='hurt_flesh' else 105,48,18),gain=.9)
        add(b,attack_noise(dur*.75,rng,23,90,2100),gain=.5)
        add(b,attack_noise(.032,rng,95,2300,11000),gain=.45)
        add(b,attack_noise(.09,rng,34,500,4800),.023,.2)
        if kind=='headshot':
            add(b,tone(.18,1720,1230,20),.005,.15)
            add(b,attack_noise(.06,rng,90,4500,14000),gain=.47)
        if kind=='kill_confirm':
            for i,f in enumerate([294,440,587]): add(b,tone(.43,f,decay=8),i*.025,.17/(i+1))
        if kind=='hurt_flesh':
            add(b,tone(.35,68,42,8),.02,.35)
    return master(room_tail(b,amount=.12),.74 if kind.startswith('hurt') else .65,SFX_RATE)


def mechanical(kind: str, variant: int) -> np.ndarray:
    rng=random_for(f'{kind}:{variant}')
    duration={'reload_eject':.28,'reload_insert':.32,'reload_bolt':.27,'reload_start':.45,
              'reload_end':.3,'equip':.33,'empty':.08,'casing':.45,'step_stone':.22,
              'step_paper':.26,'step':.22,'land':.4,'hover':.06,'click':.09}[kind]
    b=np.zeros(len(clock(duration)))
    if kind.startswith('step') or kind=='land':
        add(b,tone(duration*.8,116 if kind!='land' else 83,55,27),gain=.8)
        add(b,attack_noise(duration*.75,rng,25,120,1600),gain=.47)
        add(b,attack_noise(.04,rng,62,2300,7000),gain=.18)
        if kind=='step_paper': add(b,attack_noise(.2,rng,15,1100,10000),.025,.26)
    elif kind=='casing':
        for at,gain in [(0,.45),(.12,.22),(.22,.1)]:
            for i,f in enumerate([1429,2531,4193]): add(b,tone(.13,f*rng.uniform(.99,1.01),decay=38+i*2),at,gain/(i+1))
    else:
        times={'reload_eject':[0,.105],'reload_insert':[0,.045,.17],'reload_bolt':[0,.075],
               'reload_start':[0,.16,.28],'reload_end':[0,.06],'equip':[0,.11,.2],
               'empty':[0],'hover':[0],'click':[0]}[kind]
        for i,at in enumerate(times):
            add(b,attack_noise(.035,rng,110,800,9000),at,.4 if i==0 else .55)
            add(b,tone(.08,950+230*i,decay=44),at,.11)
        if kind.startswith('reload') or kind=='equip':
            add(b,attack_noise(duration*.65,rng,15,150,2400),.015,.12)
            add(b,tone(.11,180,89,30),times[-1],.32)
    return master(b,.42 if kind.startswith('step') else .54,SFX_RATE)


def magic(kind: str, variant=0) -> np.ndarray:
    rng=random_for(f'{kind}:{variant}')
    durations={'pickup':.65,'upgrade':2.4,'wave_start':1.5,'wave_clear':2.5,'boss_spawn':2.6,
        'boss_roar':2.1,'boss_death':3.0,'enemy_windup':.55,'swipe':.3,'slam':1.1,
        'explosion':1.45,'lantern_fuse':1.0,'spawn':.65,'dash':.42,'nova':1.7,'talisman':.65,
        'zap':.45,'player_death':3.0,'revive':1.9,'heartbeat':.95}
    duration=durations.get(kind,.9)
    b=np.zeros(len(clock(duration)))
    if kind in ['wave_start','slam','explosion','nova','boss_spawn','boss_death','player_death']:
        deep = kind in ['slam','explosion','boss_death']
        add(b,tone(duration*.85,92 if not deep else 67,29,3 if deep else 5),gain=1)
        add(b,attack_noise(duration*.7,rng,5,35,2500),gain=.45)
        add(b,attack_noise(.12,rng,33,1800,9500),gain=.28)
        if kind=='wave_start': add(b,tone(.85,71,39,5),.36,.7)
        if kind in ['nova','boss_death']: add(b,tone(1.2,293,decay=4),.08,.2)
    elif kind in ['pickup','upgrade','wave_clear','revive']:
        notes=[293.665,440,587.33,880] if kind!='pickup' else [587.33,880,1174.66]
        for i,f in enumerate(notes):
            add(b,tone(max(.12,duration-i*.13),f,decay=3.5 if duration>1 else 10,attack=.002),i*.12,.45/(1+i*.28))
            add(b,tone(max(.12,duration-i*.13),f*2.01,decay=9),i*.12,.09)
    elif kind=='heartbeat':
        add(b,tone(.3,66,43,14),gain=.8)
        add(b,tone(.28,71,45,17),.22,.57)
    elif kind.startswith('enemy_') or kind=='boss_roar':
        root={'enemy_wraith':98,'enemy_puppet':210,'enemy_brute':57,'enemy_mask':175,'enemy_lantern':330,'boss_roar':46,'enemy_windup':112}.get(kind,100)
        t=clock(duration)
        env=(np.sin(np.pi*np.minimum(t/duration,1))**.7)*np.exp(-t*1.6)
        phase=TAU*np.cumsum(root*(1+.03*np.sin(t*TAU*6)))/SFX_RATE
        for h in [1,2,3,5,7]: b+=np.sin(phase*h)*env*(.6/h)
        b+=noise(duration,rng,200,2300)*env*.15
        if kind in ['enemy_mask','enemy_lantern']:
            add(b,tone(duration,root*4.13,decay=3),gain=.22)
    elif kind=='lantern_fuse':
        t=clock(duration)
        b+=noise(duration,rng,1900,9000)*(.12+.26*t/duration)
        add(b,tone(duration,360,1200,1.5),gain=.1)
    else:
        t=clock(duration)
        b+=noise(duration,rng,500,9000)*np.sin(np.pi*t/duration)*np.exp(-t*4)*.35
        add(b,tone(duration,700 if kind=='zap' else 270,125,13),gain=.3)
        if kind=='zap':
            for at in [0,.08,.18]: add(b,attack_noise(.07,rng,55,5000,16000),at,.3)
    return master(room_tail(b,amount=.22),.72 if kind not in ['heartbeat','spawn'] else .45,SFX_RATE)


def _vocal_excitation(duration: float, fundamental: float, rng: np.random.Generator,
                      formants: list[tuple[float,float,float]], roughness: float = .3,
                      breath: float = .2) -> np.ndarray:
    """Nonverbal creature timbre: rough glottal excitation plus noise formants.
    This is synthesis, not a human speech sample or pitch-shifted instrument.
    Midrange formants retain localization cues even on small speakers.
    """
    t=clock(duration)
    phase_offset=rng.uniform(0,TAU)
    pitch= fundamental * (1+.035*np.sin(TAU*4.2*t+phase_offset)+
                            .015*np.sin(TAU*17.7*t))
    pitch *= 1+.08*np.sin(np.pi*np.minimum(t/duration,1))
    phase=TAU*np.cumsum(pitch)/SFX_RATE
    excitation=np.zeros(len(t))
    for harmonic in range(1,35):
        excitation+=np.sin(phase*harmonic)/(harmonic**.82)
    # Amplitude irregularity supplies a throat-rattle rather than a clean synth note.
    excitation*=.75+roughness*.45*np.sin(TAU*26.5*t+phase_offset)
    y=excitation*.13
    for frequency,width,gain in formants:
        lo=max(35,frequency-width)
        hi=min(SFX_RATE*.45,frequency+width)
        sos=butter(2,[lo,hi],'bandpass',fs=SFX_RATE,output='sos')
        colored=sosfilt(sos,excitation)
        colored/=max(float(np.sqrt(np.mean(colored*colored))),.001)
        y+=colored*gain
    y+=noise(duration,rng,180,5200)*breath
    return y


def enemy_voice(key: str, variant: int) -> np.ndarray:
    """Three distinct, spatializable calls per enemy; no intelligible speech."""
    kind=key.removeprefix('enemy_')
    rng=random_for(f'new-enemy-voice:{kind}:{variant}')
    nominal={'wraith':1.10,'puppet':.83,'brute':1.18,'mask':1.22,'lantern':1.00,'boss':1.39}
    duration=nominal[kind]+(-.045,.025,.065)[variant]
    t=clock(duration)
    envelope=np.minimum(t/.035,1) * np.minimum((duration-t)/.12,1)
    envelope*=np.exp(-t*.65)
    b=np.zeros(len(t))
    if kind=='wraith':
        # Wet, low throat rasp with a clear unvoiced inhalation at its onset.
        b=_vocal_excitation(duration,79*rng.uniform(.94,1.06),rng,
            [(290,150,.20),(680,220,.14),(1290,350,.065)],.85,.26)
        b*=envelope*(.7+.3*np.sin(TAU*7*t)**2)
        add(b,attack_noise(.22,rng,10,500,3600),gain=.24)
    elif kind=='puppet':
        # Paper dragged across lacquer and irregular wooden jaw clicks.
        flutter=(.25+.75*np.maximum(np.sin(TAU*(10+variant)*t),0))
        b=noise(duration,rng,900,6800)*envelope*flutter*.48
        b+=noise(duration,rng,160,1100)*envelope*.12
        for index,at in enumerate([.025,.15,.33,.53,.67]):
            at+=rng.uniform(-.012,.012)
            add(b,attack_noise(.045,rng,60,1500,8500),at,.14)
            add(b,tone(.09,330+index*91,decay=35),at,.15)
    elif kind=='brute':
        # Low compressed grunt with heavy breastplate / chain resonance.
        b=_vocal_excitation(duration,58*rng.uniform(.94,1.06),rng,
            [(210,100,.24),(520,190,.16),(1040,240,.08)],1.0,.16)
        b*=envelope*(.7+.3*np.sin(TAU*18*t)**2)
        for index,f in enumerate([263,521,1043]):
            add(b,tone(duration*.9,f*rng.uniform(.98,1.02),decay=5+index),.045,.13/(index+1))
        add(b,attack_noise(.19,rng,14,200,3100),gain=.16)
    elif kind=='mask':
        # Breath-led, airy descending wail; explicitly no footfall-like low thud.
        b=_vocal_excitation(duration,218*rng.uniform(.94,1.06),rng,
            [(810,230,.12),(1530,330,.16),(2860,420,.055)],.10,.44)
        b*=envelope*(.65+.35*np.sin(np.pi*t/duration)**2)
        phase=TAU*np.cumsum(760-240*t/duration)/SFX_RATE
        b+=np.sin(phase)*envelope*.12
    elif kind=='lantern':
        # Inhaled furnace breath, torn flame and a thin ceramic-mouth resonance.
        flicker=.58+.22*np.sin(TAU*13.8*t)+.12*np.sin(TAU*31.4*t)
        b=(noise(duration,rng,100,1650)*.38+noise(duration,rng,1600,6200)*.16)
        b*=envelope*flicker
        for f,gain in [(432,.13),(927,.075),(1619,.04)]:
            b+=tone(duration,f*rng.uniform(.97,1.03),decay=2.5,attack=.05)*gain
    else:
        # Broad, nonverbal war cry. Formants carry direction while the sub-body
        # makes the boss recognizable; it is not the long encounter stinger.
        b=_vocal_excitation(duration,47*rng.uniform(.94,1.06),rng,
            [(250,140,.25),(760,250,.19),(1670,400,.105)],1.0,.20)
        b*=envelope*(.78+.22*np.sin(TAU*12*t)**2)
        add(b,tone(duration*.9,96,39,3.4),gain=.33)
        for f,gain in [(341,.12),(717,.065),(1439,.035)]:
            add(b,tone(duration*.8,f,decay=4),.055,gain)
    peak={'wraith':.69,'puppet':.58,'brute':.73,'mask':.63,'lantern':.64,'boss':.77}[kind]
    return master(room_tail(b,amount=.10),peak,SFX_RATE)


def enemy_step(key: str, variant: int) -> np.ndarray:
    """Ground enemies have footfalls; floaters get cloth / chain movement cues."""
    kind=key.removeprefix('enemy_step_')
    rng=random_for(f'new-enemy-move:{kind}:{variant}')
    nominal={'wraith':.34,'puppet':.25,'brute':.42,'mask':.32,'lantern':.38,'boss':.46}
    duration=nominal[kind]+(-.02,.0,.025)[variant]
    b=np.zeros(len(clock(duration)))
    if kind=='wraith':
        add(b,tone(.20,103,49,22),gain=.47)
        add(b,attack_noise(.21,rng,20,90,1700),gain=.29)
        drag=noise(duration-.045,rng,450,3100)
        drag*=np.sin(np.pi*clock(duration-.045)/(duration-.045))**1.4
        add(b,drag,.045,.14)
    elif kind=='puppet':
        add(b,attack_noise(duration*.85,rng,19,1350,9200),gain=.48)
        add(b,tone(.12,255,148,30),gain=.15)
        add(b,attack_noise(.045,rng,75,2500,11000),.015,.18)
        add(b,attack_noise(.065,rng,35,850,5400),.12,.12)
    elif kind in ['brute','boss']:
        massive=kind=='boss'
        add(b,tone(duration*.72,88 if massive else 118,38 if massive else 53,10 if massive else 14),gain=.80)
        add(b,attack_noise(.15,rng,26,70,2200),gain=.50)
        # Heel -> toe impact and armor resonance distinguish these from a blast.
        add(b,attack_noise(.07,rng,33,1100,7200),.08,.21)
        for index,f in enumerate([294,603,1187,2213]):
            add(b,tone(duration*.85,f*(.83 if massive else 1)*rng.uniform(.98,1.02),
                       decay=13+index*2),.022,.22/(index+1))
        add(b,attack_noise(.14,rng,22,700,4300),.15,.13)
    elif kind=='mask':
        # A small cloth sweep and suspended charm scrape; no heel/bass impulse.
        t=clock(duration)
        b=noise(duration,rng,650,3800)*np.sin(np.pi*t/duration)**1.5*.28
        for f,gain in [(1471,.075),(2293,.045),(3589,.025)]:
            add(b,tone(duration*.7,f,decay=17,attack=.006),.035,gain)
    else:
        # Loose metal chain and a lantern ring, plus a light flame/air flutter.
        t=clock(duration)
        b=noise(duration,rng,420,2800)*np.sin(np.pi*t/duration)**2*.10
        for at,gain in [(.01,.22),(.092,.12),(.19,.065)]:
            for index,f in enumerate([763,1537,2789]):
                add(b,tone(.17,f*rng.uniform(.985,1.015),decay=25+index*4),at,gain/(index+1))
    peak={'wraith':.55,'puppet':.48,'brute':.66,'mask':.34,'lantern':.40,'boss':.70}[kind]
    return master(b,peak,SFX_RATE)


def make_sfx() -> dict[str,np.ndarray]:
    previews={}
    groups=[(['pistol','shotgun','smg','rifle','launcher','crossbow'],3,gun),
        (['hit_flesh','hit_armor','hurt_flesh'],3,impact),
        (['headshot','kill_confirm','hurt_shield'],2,impact),
        (['melee_hit','enemy_hit','impact','shield_break'],2,impact),
        (['reload_eject','reload_insert','reload_bolt','reload_start','reload_end','equip','empty','casing'],3,mechanical),
        (['step_stone','step_paper','step'],4,mechanical),(['land','hover','click'],2,mechanical),
        (['pickup','upgrade','wave_start','wave_clear','boss_spawn','boss_roar','boss_death','enemy_windup',
          'swipe','slam','explosion','lantern_fuse','spawn','dash','nova','talisman','zap','player_death','revive','heartbeat'],1,magic),
        ([f'enemy_{kind}' for kind in ENEMY_TYPES],3,enemy_voice),
        ([f'enemy_step_{kind}' for kind in ENEMY_TYPES],3,enemy_step)]
    for ids,variants,recipe in groups:
        for key in ids:
            BANK[key]=[]
            for variant in range(variants):
                data=recipe(key,variant)
                filename=f'sfx/{key}_{variant+1}.wav'
                write(OUT/filename,data,SFX_RATE)
                BANK[key].append('res://assets/audio/'+filename)
                if variant==0: previews[key]=data
    # Compatibility aliases use the improved material impact/confirmation assets.
    BANK['hit']=BANK['hit_flesh']
    BANK['kill']=BANK['kill_confirm']
    BANK['hurt']=BANK['hurt_flesh']
    return previews


def midi(note: int) -> float:
    return 440*2**((note-69)/12)


def pluck(note: int,duration: float=2.8,velocity:float=1,sr=MUSIC_RATE) -> np.ndarray:
    t=clock(duration,sr); f=midi(note)
    # Plucked string modal dispersion: rounded fundamental, bright nail transient.
    y=np.zeros(len(t))
    for h,level in [(1,1),(2,.32),(3,.15),(4,.075),(6,.03)]:
        y+=level*np.sin(TAU*f*h*(1+h*h*.00008)*t)*np.exp(-t*(1.55+h*.65))
    attack=np.minimum(t/.003,1)
    return y*attack*velocity


def bowed(note: int,duration:float,sr=MUSIC_RATE) -> np.ndarray:
    t=clock(duration,sr); f=midi(note)
    env=np.sin(np.pi*np.minimum(t/duration,1))**.7
    y=np.zeros(len(t))
    vibrato=.0025*np.sin(TAU*4.7*t)
    phase=TAU*f*(t+vibrato/(TAU*4.7))
    for h in [1,2,3,4,5,7]: y+=np.sin(phase*h)*(.6/h**1.4)
    return y*env


def stereo_echo(b:np.ndarray,amount=.24,sr=MUSIC_RATE) -> np.ndarray:
    result=b.copy()
    for beats,gain in [(1/3,.34),(2/3,.21),(1,.14)]:
        delay=round(BEAT*beats*sr)
        result+=np.roll(b[:,::-1],delay,axis=0)*gain*amount
    return result


def drum(duration:float=.7,high=False) -> np.ndarray:
    rng=random_for(f'drum:{high}')
    sr=MUSIC_RATE
    b=tone(duration,153 if high else 91,81 if high else 45,10 if high else 6,sr)
    b+=attack_noise(duration,rng,20,100 if high else 40,1800 if high else 950,sr)*(.18 if high else .22)
    return b


def make_music() -> dict[str,np.ndarray]:
    frames=round(MUSIC_SECONDS*MUSIC_RATE)
    stems={name:np.zeros((frames,2)) for name in ['menu','melody','strings','drums','boss','ambience']}
    # Four four-bar phrases; Dm -> Bb -> Gm -> Asus, closing back to D.
    roots=[50,46,43,45]
    melody=[74,69,67,65, 62,65,69,67, 65,62,60,62, 69,67,65,62]
    answer=[62,65,67,69, 74,72,69,67, 65,67,69,65, 64,67,69,73]
    for bar in range(BARS):
        base=bar*4*BEAT
        root=roots[bar//4]
        # Menu is a distinct sparse response melody over open fifths.
        add(stems['menu'],bowed(root+12,4*BEAT),base,.09, MUSIC_RATE, -.22,True)
        add(stems['menu'],bowed(root+19,4*BEAT),base,.055,MUSIC_RATE,.24,True)
        for beat,note,vel,pan in [(0,melody[bar],.25,-.25),(2.5,answer[bar],.14,.35)]:
            add(stems['menu'],pluck(note,3),base+beat*BEAT,vel,MUSIC_RATE,pan,True)
        # Main theme: an eight-note question followed by an eight-note answer.
        phrase_note=melody[bar] if bar<8 else answer[bar]
        add(stems['melody'],pluck(phrase_note,3.2),base,.29,MUSIC_RATE,-.2,True)
        add(stems['melody'],pluck(phrase_note-12,2.4),base+1.5*BEAT,.11,MUSIC_RATE,.27,True)
        if bar%2==1:
            add(stems['melody'],pluck(answer[bar],2.8),base+3*BEAT,.19,MUSIC_RATE,.25,True)
        third=3 if bar//4!=3 else 5
        for interval,gain,pan in [(0,.12,-.4),(7,.065,.4),(third+12,.038,0)]:
            add(stems['strings'],bowed(root+interval,4.25*BEAT),base,gain,MUSIC_RATE,pan,True)
        # Steady martial pulse becomes audible through the wave-based mixer.
        for beat,gain in [(0,.46),(1.5,.20),(2,.33),(3.5,.16)]:
            add(stems['drums'],drum(.75),base+beat*BEAT,gain,MUSIC_RATE,(-.15 if beat<2 else .15),True)
        for beat in [1,3]:
            add(stems['drums'],drum(.32,True),base+beat*BEAT,.19,MUSIC_RATE,.28,True)
        for beat in np.arange(.5,4,.5):
            tick=attack_noise(.08,random_for(f'tick{bar}{beat}'),50,1800,7800,MUSIC_RATE)
            add(stems['drums'],tick,base+beat*BEAT,.025,MUSIC_RATE,-.4,True)
        # Boss arrangement: bowed ostinato + double drums and bronze gong accents.
        boss_notes=[root,root+7,root+12,root+10,root+7,root+3,root+7,root+12]
        for i,note in enumerate(boss_notes):
            add(stems['boss'],bowed(note+12,.62*BEAT),base+i*.5*BEAT,.11,MUSIC_RATE,(-.32 if i%2 else .32),True)
        for beat in [0,.75,1.5,2,2.75,3.5]:
            add(stems['boss'],drum(.6,beat%1>0),base+beat*BEAT,.28,MUSIC_RATE,.1,True)
        if bar%4==0:
            for h,gain in [(1,.14),(1.43,.07),(2.11,.035),(3.77,.015)]:
                add(stems['boss'],tone(5,midi(root+12)*h,decay=1.1,sr=MUSIC_RATE,attack=.009),base,gain,MUSIC_RATE,0,True)
    # Breathing wind without the previous overwhelming endless bass drone.
    t=clock(MUSIC_SECONDS,MUSIC_RATE)
    for channel,seed in enumerate([41,84]):
        rng=random_for(f'wind{seed}')
        wind=noise(MUSIC_SECONDS,rng,70,1200,MUSIC_RATE)
        phase=.6+.25*np.sin(TAU*t/MUSIC_SECONDS*3+channel)
        stems['ambience'][:,channel]=wind*phase*.024
    for at,note,pan in [(5,86,-.5),(18,81,.4),(31,84,-.35),(43,88,.55)]:
        add(stems['ambience'],pluck(note,3.4),at,.035,MUSIC_RATE,pan,True)
    peaks={'menu':.38,'melody':.40,'strings':.24,'drums':.55,'boss':.48,'ambience':.18}
    for name,b in stems.items():
        if name!='drums': b=stereo_echo(b,.4 if name=='melody' else .25)
        b=master(b,peaks[name],MUSIC_RATE,True)
        stems[name]=b
        write(OUT/f'music/{name}.wav',b,MUSIC_RATE,True)
    return stems


def make_preview(sounds:dict[str,np.ndarray],music:dict[str,np.ndarray]) -> None:
    # A representative 10-second gameplay mix for auditioning peaks and balance.
    seconds=10
    frames=round(seconds*MUSIC_RATE)
    b=(music['melody'][:frames]*.35+music['strings'][:frames]*.30+
       music['drums'][:frames]*.42+music['ambience'][:frames]*.11)
    from scipy.signal import resample_poly
    for at,key,pan,gain in [(1,'pistol',0,.6),(1.1,'hit_flesh',.1,.48),(2.1,'rifle',0,.6),
        (2.22,'headshot',0,.45),(3.5,'hurt_flesh',-.5,.6),(4.5,'reload_eject',0,.5),
        (5.1,'reload_insert',0,.5),(5.5,'reload_bolt',0,.5),(6.5,'shotgun',0,.65),
        (6.62,'kill_confirm',.2,.52),(8.2,'crossbow',0,.62),(8.3,'hit_armor',.3,.45)]:
        add(b,resample_poly(sounds[key],1,2),at,gain,MUSIC_RATE,pan)
    b=master(b,.89,MUSIC_RATE)
    write(OUT/'previews/battle_mix.wav',b,MUSIC_RATE)


def write_bank() -> None:
    lines=['class_name AudioBank','extends RefCounted','','## Generated by tools/generate_audio.py. Original procedural recordings.','const SOUNDS := {']
    for key,paths in BANK.items(): lines.append('\t'+json.dumps(key)+': '+json.dumps(paths)+',')
    lines.extend(['}','','const MUSIC := {'])
    for name in ['menu','melody','strings','drums','boss','ambience']:
        lines.append(f'\t"{name}": "res://assets/audio/music/{name}.wav",')
    lines.extend(['}',''])
    p=ROOT/'scripts/audio/audio_bank.gd';p.parent.mkdir(parents=True,exist_ok=True)
    p.write_text('\n'.join(lines),encoding='utf-8')


def audit() -> None:
    problems=[]
    for path in OUT.rglob('*.wav'):
        with wave.open(str(path),'rb') as f:
            rate=f.getframerate();channels=f.getnchannels();data=np.frombuffer(f.readframes(f.getnframes()),dtype='<i2').astype(float)/32767
            data=data.reshape(-1,channels)
        peak=float(np.max(np.abs(data)));rms=float(np.sqrt(np.mean(data*data)))
        if not .02 < peak < .95: problems.append(f'{path.name}: peak {peak}')
        if rms<.002: problems.append(f'{path.name}: almost silent')
        if path.parent.name=='music':
            if channels!=2 or abs(len(data)/rate-48)>.001: problems.append(f'{path.name}: stem format/length')
            if np.max(np.abs(data[-1]-data[0]))>.001: problems.append(f'{path.name}: loop discontinuity')
            if np.sqrt(np.mean((data[:,0]-data[:,1])**2))<.001: problems.append(f'{path.name}: no stereo field')
    if problems: raise SystemExit('\n'.join(problems))
    print(f'PASS audio audit: {len(list(OUT.rglob("*.wav")))} PCM16 recordings; no clipping/silent files; six synchronized stereo 48s stems; zero loop seams.')


def _enemy_asset(path: Path) -> bool:
    return re.fullmatch(r'enemy_(?:step_)?(?:wraith|puppet|brute|mask|lantern|boss)_[123]\.wav',path.name) is not None


def _load_existing_bank() -> None:
    """Read only the generated string/array table, never execute GDScript."""
    source=(ROOT/'scripts/audio/audio_bank.gd').read_text(encoding='utf-8-sig')
    match=re.search(r'const SOUNDS := (\{.*?\n\})',source,re.S)
    if match is None:
        raise SystemExit('Existing AudioBank SOUNDS table was not found; use a full generation first.')
    body=re.sub(r',\s*}', '}', match.group(1))
    existing=json.loads(body)
    if not isinstance(existing,dict) or not all(isinstance(k,str) and isinstance(v,list) for k,v in existing.items()):
        raise SystemExit('Unexpected AudioBank table; refusing an incremental overwrite.')
    BANK.update(existing)


def make_enemies_only() -> None:
    """Change exactly 36 cue WAVs and merge their table into the existing bank."""
    _load_existing_bank()
    manifest_path=OUT/'audio_manifest.json'
    manifest=json.loads(manifest_path.read_text(encoding='utf-8-sig')) if manifest_path.exists() else {'files':{}}
    REPORT.update(manifest.get('files',{}))
    protected={str(p.relative_to(OUT)):hashlib.sha256(p.read_bytes()).hexdigest()
               for p in OUT.rglob('*.wav') if not _enemy_asset(p)}
    changed=[]
    for kind in ENEMY_TYPES:
        for prefix,recipe in [('enemy_',enemy_voice),('enemy_step_',enemy_step)]:
            key=prefix+kind
            BANK[key]=[]
            for variant in range(3):
                path=OUT/f'sfx/{key}_{variant+1}.wav'
                write(path,recipe(key,variant),SFX_RATE)
                BANK[key].append('res://assets/audio/sfx/'+path.name)
                changed.append(str(path.relative_to(OUT)))
    write_bank()
    manifest['files']=REPORT
    manifest['enemy_audio']={'revision':1,'recordings':36,'variants_per_event':3,
        'spatial_format':'mono PCM16 / 44100 Hz',
        'movement_note':'mask and lantern use cloth/chain movement cues, not grounded footfalls',
        'original_non_enemy_files_unchanged':len(protected)}
    manifest_path.write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    modified=[name for name,digest in protected.items()
              if hashlib.sha256((OUT/name).read_bytes()).hexdigest()!=digest]
    if modified:
        raise SystemExit('Unexpected non-enemy asset modification: '+', '.join(modified))
    print(f'Generated {len(changed)} enemy cue recordings; all {len(protected)} other WAV files are byte-identical.')


def audit_enemy_audio() -> None:
    rows=[]
    for kind in ENEMY_TYPES:
        for prefix in ['enemy_','enemy_step_']:
            hashes=[]
            for variant in range(1,4):
                path=OUT/f'sfx/{prefix}{kind}_{variant}.wav'
                with wave.open(str(path),'rb') as source:
                    channels=source.getnchannels();rate=source.getframerate()
                    signal=np.frombuffer(source.readframes(source.getnframes()),dtype='<i2').astype(float)/32767
                duration=len(signal)/rate
                rms=float(np.sqrt(np.mean(signal*signal)))
                peak=float(np.max(np.abs(signal)))
                moving=prefix=='enemy_step_'
                low,high=(.20,.51) if moving else (.70,1.50)
                if channels!=1 or rate!=44100 or not low<=duration<=high:
                    raise SystemExit(f'{path.name}: invalid spatial cue format/duration')
                if not .025<rms<.35 or not .30<peak<.80:
                    raise SystemExit(f'{path.name}: inadequate cue level rms={rms:.4f}, peak={peak:.4f}')
                if signal[0]!=0 or signal[-1]!=0:
                    raise SystemExit(f'{path.name}: audible boundary discontinuity')
                hashes.append(hashlib.sha256(path.read_bytes()).hexdigest())
                spectrum=np.abs(np.fft.rfft(signal))**2
                centroid=float(np.sum(spectrum*np.fft.rfftfreq(len(signal),1/rate))/max(np.sum(spectrum),1e-12))
                rows.append({'event':prefix+kind,'variant':variant,'seconds':round(duration,3),
                             'channels':channels,'rate':rate,'rms':round(rms,4),'peak':round(peak,4),
                             'spectral_centroid_hz':round(centroid,1)})
            if len(set(hashes))!=3:
                raise SystemExit(f'{prefix}{kind}: repeated audio variant')
    report={'status':'PASS','recordings':len(rows),'rows':rows}
    (OUT/'enemy_audio_audit.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(f'PASS enemy audio: {len(rows)} distinct mono 44.1k cues; duration, RMS, peak and silent endpoints verified.')


def main() -> None:
    parser=argparse.ArgumentParser()
    mode=parser.add_mutually_exclusive_group()
    mode.add_argument('--audit-only',action='store_true')
    mode.add_argument('--enemy-only',action='store_true',help='Regenerate only enemy voices/movement and merge the existing bank')
    args=parser.parse_args()
    if args.enemy_only:
        make_enemies_only()
    elif not args.audit_only:
        sounds=make_sfx();music=make_music();make_preview(sounds,music);write_bank()
        (OUT/'audio_manifest.json').write_text(json.dumps({'composition':{'bpm':BPM,'bars':BARS,'seconds':MUSIC_SECONDS,'key':'D minor pentatonic','copyright':'Original synthesized composition and sound effects for Ink Tide; no external audio samples'},'files':REPORT},indent=2),encoding='utf-8')
        print(f'Generated {len(REPORT)} files; {len(BANK)} sound events.')
    audit()
    audit_enemy_audio()

if __name__=='__main__': main()
