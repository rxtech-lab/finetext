import React from 'react';
import {AbsoluteFill, Img, staticFile, useCurrentFrame} from 'remotion';
import data from './layout.json';

export const COMPOSITION_FPS = 60;
export const COMPOSITION_DURATION_IN_FRAMES = 900;
export const COMPOSITION_WIDTH = 1920;
export const COMPOSITION_HEIGHT = 1080;

type Word = typeof data.before[number];
type State = {word: Word; category: string; reveal: number; strike: number; opacity: number};
const clamp = (n: number) => Math.min(1, Math.max(0, n));
const mix = (a: number, b: number, p: number) => a + (b - a) * p;
const rgb = (category: string) => data.colors[category as keyof typeof data.colors];
const cssColor = (color: number[], alpha = 1) => `rgba(${color.map(x => Math.round(x)).join(',')},${alpha})`;
const settle = (word: Word): State => ({word, category: 'unchanged', reveal: 0, strike: 0, opacity: 1});
const curve = (kind: string, progress: number) => {
  const samples = data.curves[kind as keyof typeof data.curves];
  const x = clamp(progress) * (samples.length - 1), i = Math.floor(x);
  return mix(samples[i], samples[Math.min(i + 1, samples.length - 1)], x - i);
};

// Mirrors AnimatedRefinementText.present(), including invisible staging and the
// WordCanvas opacity, highlight, strike, tint and line-wrap interpolation.
function playback(source: Word[], target: Word[], relocated: string[], seconds: number) {
  const ids = new Set(target.map(w => w.id)), sourceIDs = new Set(source.map(w => w.id));
  const removed = new Set(source.filter(w => !ids.has(w.id)).map(w => w.id));
  const hidden = new Set(relocated), destinations = new Map(target.map(w => [w.id, w]));
  let current = source.map(settle), old = current, progress = 1, start = 0;
  const transition = (duration: number, easing: string, update: (states: State[]) => State[]) => {
    old = current;
    current = update(current);
    if (seconds < start + duration) { progress = clamp(curve(easing, (seconds - start) / duration)); return true; }
    start += duration;
    return false;
  };
  const durations = data.phases.map(p => p.duration);
  const [prepare, mark, fade, stage, morph, hold, cleanup] = durations;
  if (seconds < 0) return {old: current, current, progress: 1};
  current = current.map(s => removed.has(s.word.id) ? {...s, category: s.word.category === 'added' ? 'added' : 'deleted'} : s);
  start += prepare;
  if (seconds < start) return {old: current, current, progress: 1};
  if (transition(mark, 'easeInOut', states => states.map(s => removed.has(s.word.id) ? {...s, reveal: 1, strike: s.category === 'deleted' ? 1 : 0} : s))) return {old, current, progress};
  if (transition(fade, 'easeOut', states => states.map(s => removed.has(s.word.id) || hidden.has(s.word.id) ? {...s, opacity: 0} : s))) return {old, current, progress};
  current = current.filter(s => !removed.has(s.word.id)).map(s => hidden.has(s.word.id) ? {...s, word: destinations.get(s.word.id)!} : s);
  current = [...current, ...target.filter(w => !sourceIDs.has(w.id)).map(w => ({...settle(w), opacity: 0}))];
  start += stage;
  if (seconds < start) return {old: current, current, progress: 1};
  if (transition(morph, 'smooth', states => states.map(s => {
    const word = destinations.get(s.word.id)!;
    return {...s, word, category: word.category, opacity: 1, reveal: word.category === 'unchanged' ? 0 : 1, strike: word.category === 'deleted' ? 1 : 0};
  }))) return {old, current, progress};
  start += hold;
  if (seconds < start) return {old: current, current, progress: 1};
  if (transition(cleanup, 'easeOut', states => states.map(s => ({...s, category: 'unchanged', reveal: 0, strike: 0})))) return {old, current, progress};
  current = target.map(settle);
  return {old: current, current, progress: 1};
}

const WordCanvas = ({source, target, relocated, seconds}: {source: Word[]; target: Word[]; relocated: string[]; seconds: number}) => {
  const {old, current, progress: p} = playback(source, target, relocated, seconds);
  const origins = new Map(old.map(s => [s.word.id, s]));
  return <div style={{position: 'relative', width: data.width, height: 138}}>
    {current.map(item => {
      const from = origins.get(item.word.id) ?? item;
      const rect = {x: mix(from.word.x, item.word.x, p), y: mix(from.word.y, item.word.y, p), w: mix(from.word.w, item.word.w, p), h: mix(from.word.h, item.word.h, p)};
      const fadeProgress = from.opacity < item.opacity ? p * p : p;
      let opacity = mix(from.opacity, item.opacity, fadeProgress);
      if (Math.abs(from.word.y - item.word.y) > .5) opacity *= 1 - .45 * Math.sin(Math.PI * p);
      if (opacity <= .001) return null;
      const reveal = mix(from.reveal, item.reveal, p), strike = mix(from.strike, item.strike, p);
      const tint = rgb(from.category).map((c, i) => mix(c, rgb(item.category)[i], p));
      const alpha = mix(from.category === 'unchanged' ? 0 : .17, item.category === 'unchanged' ? 0 : .17, p);
      return <div key={item.word.id} style={{position: 'absolute', left: rect.x, top: rect.y, width: rect.w, height: rect.h, opacity}}>
        {reveal > .001 && alpha > .001 && <div style={{position: 'absolute', width: (rect.w + 2) * reveal, height: rect.h, borderRadius: 2, background: cssColor(tint, alpha)}}/>}
        <div style={{position: 'absolute', inset: 0, background: cssColor(tint), WebkitMaskImage: `url("${item.word.glyph}")`, maskImage: `url("${item.word.glyph}")`, WebkitMaskSize: '100% 100%', maskSize: '100% 100%', maskRepeat: 'no-repeat'}}/>
        {strike > .001 && <div style={{position: 'absolute', top: rect.h / 2 - .75, height: 1.5, width: rect.w * strike, background: '#ff0000'}}/>}
      </div>;
    })}
  </div>;
};

const icon = staticFile('upload/22BDFD59-94BF-4641-9FFD-A7A9CFB58914.png');

// Plain text controls follow the production before/after replay; motion remains unchanged.
export const MyComposition: React.FC = () => {
  const time = useCurrentFrame() / 60;
  const reverse = time >= 6.5 && time < 10.5;
  const begin = time < 6.5 ? 2 : reverse ? 6.5 : 10.5;
  const seconds = time - begin;
  const scale = 3.65;
  const ending = curve('easeInOut', (time - 12.6) / .4);
  const afterAmount = time < 6.5 ? curve('easeOut', (time - 2) / .16)
    : time < 10.5 ? 1 - curve('easeOut', (time - 6.5) / .16)
    : curve('easeOut', (time - 10.5) / .16);
  const switchTime = time < 6.5 ? 2 : time < 10.5 ? 6.5 : 10.5;
  const pointerOpacity = clamp((time - switchTime + .22) / .08) * (1 - clamp((time - switchTime - .10) / .18));
  const pointerX = switchTime === 6.5 ? 216 : 345;
  return <AbsoluteFill style={{background: '#101113', color: '#f4f4f5', fontFamily: '-apple-system, BlinkMacSystemFont, sans-serif'}}>
    <div style={{position: 'absolute', left: 0, top: 0, width: 1920, height: 1080,
      transform: `scale(${window.innerWidth / 1920})`, transformOrigin: 'top left'}}>
      <div style={{position: 'absolute', inset: 0, opacity: 1 - ending}}>
        <div style={{position: 'absolute', left: 160, top: 158, display: 'flex', alignItems: 'center', gap: 22}}>
          <Img src={icon} style={{width: 104, height: 104}}/>
          <div style={{fontSize: 72, lineHeight: 1, fontWeight: 600, letterSpacing: -2}}>FineText</div>
        </div>
        <div style={{position: 'absolute', left: 168, top: 280, fontSize: 34, lineHeight: 1.2, color: '#a4a6ad'}}>Make it sound like you.</div>
        <div style={{position: 'absolute', left: (1920 - data.width * scale) / 2,
          top: 470, transform: `scale(${scale})`, transformOrigin: 'top left'}}>
          <WordCanvas source={reverse ? data.after : data.before}
            target={reverse ? data.before : data.after}
            relocated={reverse ? data.backwardRelocated : data.forwardRelocated}
            seconds={seconds}/>
        </div>
        <div style={{position: 'absolute', left: 168, top: 803, display: 'flex', gap: 44, alignItems: 'center'}}>
          {['Before', 'After'].map((label, i) => {
            const selected = i === 1 ? afterAmount : 1 - afterAmount;
            const shade = mix(112, 245, selected);
            return <button key={label} aria-pressed={i === 1 ? !reverse && time >= 2 : reverse || time < 2}
              style={{appearance: 'none', border: 0, borderRadius: 0, padding: 0, background: 'transparent',
                font: 'inherit', fontSize: 30, fontWeight: 500, lineHeight: '44px', cursor: 'pointer',
                color: `rgb(${shade},${shade},${shade})`}}>{label}</button>;
          })}
        </div>
        <svg width="27" height="36" viewBox="0 0 27 36" style={{position: 'absolute', left: pointerX, top: 837, opacity: pointerOpacity, filter: 'drop-shadow(0 1px 2px #000a)'}}>
          <path d="M2 2v27l7-7 5 12 5-2-5-12h10L2 2Z" fill="white" stroke="#151515" strokeWidth="2"/>
        </svg>
      </div>
      <div style={{position: 'absolute', inset: 0, opacity: ending, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', transform: `translateY(${(1 - ending) * 12}px)`}}>
        <Img src={icon} style={{width: 184, height: 184, marginBottom: 27}}/>
        <div style={{fontSize: 80, lineHeight: 1.15, fontWeight: 600, letterSpacing: -2.4}}>FineText</div>
        <div style={{marginTop: 25, fontSize: 38, lineHeight: 1.2, color: '#a7b6c2', letterSpacing: .4}}>fintext.app</div>
      </div>
    </div>
  </AbsoluteFill>;
};
