import { useEffect, useRef } from 'react'
import { palette } from '../lib/theme'

export type Mood = 'idle' | 'working' | 'attention' | 'paused' | 'offline'

const reduceMotion = () => window.matchMedia('(prefers-reduced-motion: reduce)').matches

/** Resolve any CSS colour to rgb components via a scratch canvas. */
const colorCache = new Map<string, [number, number, number]>()
function rgb(color: string): [number, number, number] {
  const hit = colorCache.get(color)
  if (hit) return hit
  const c = document.createElement('canvas').getContext('2d')!
  c.fillStyle = color
  c.fillRect(0, 0, 1, 1)
  const [r, g, b] = c.getImageData(0, 0, 1, 1).data
  const out: [number, number, number] = [r, g, b]
  colorCache.set(color, out)
  return out
}
const rgba = (color: string, a: number) => { const [r, g, b] = rgb(color); return `rgba(${r},${g},${b},${a})` }

/**
 * The presence of an AI employee. Calm when idle, a travelling signal while it
 * works, amber breathing when it needs you, dim when paused. A port of the
 * Mac app's AgentOrb, drawn the same way.
 */
export function AgentOrb({ mood = 'idle', tint = palette.ice, size = 44 }: { mood?: Mood; tint?: string; size?: number }) {
  const ref = useRef<HTMLCanvasElement>(null)
  useEffect(() => {
    const canvas = ref.current!
    const dpr = window.devicePixelRatio || 1
    canvas.width = size * dpr
    canvas.height = size * dpr
    const ctx = canvas.getContext('2d')!
    const color = mood === 'attention' ? palette.amber : mood === 'paused' || mood === 'offline' ? '#8b8c90' : tint
    let frame = 0
    const still = reduceMotion() || mood === 'paused' || mood === 'offline'
    const draw = (now: number) => {
      const t = now / 1000
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
      ctx.clearRect(0, 0, size, size)
      const c = size / 2, r = size / 2
      const breathe = mood === 'attention' ? (Math.sin(t * 3.2) + 1) / 2 : (Math.sin(t * 1.3) + 1) / 2

      const halo = ctx.createRadialGradient(c, c, r * 0.1, c, c, r)
      halo.addColorStop(0, rgba(color, 0.1 + 0.14 * breathe))
      halo.addColorStop(1, rgba(color, 0))
      ctx.fillStyle = halo
      ctx.beginPath(); ctx.arc(c, c, r, 0, Math.PI * 2); ctx.fill()

      const ringR = r - r * 0.16 - 0.5
      ctx.lineWidth = Math.max(0.6, size / 90)
      ctx.strokeStyle = `rgba(255,255,255,${mood === 'offline' ? 0.08 : 0.16})`
      ctx.beginPath(); ctx.arc(c, c, ringR, 0, Math.PI * 2); ctx.stroke()

      if (mood !== 'paused' && mood !== 'offline') {
        const speed = mood === 'working' ? 2.6 : 0.5
        const start = t * speed
        const sweep = Math.PI * 2 * (mood === 'working' ? 0.34 : 0.22)
        const grad = ctx.createLinearGradient(c - r, c, c + r, c)
        grad.addColorStop(0, rgba(color, 0)); grad.addColorStop(0.5, rgba(color, 1)); grad.addColorStop(1, '#ffffff')
        ctx.strokeStyle = grad
        ctx.lineWidth = Math.max(1.1, size / 40)
        ctx.lineCap = 'round'
        ctx.beginPath(); ctx.arc(c, c, ringR, start, start + sweep); ctx.stroke()
        if (mood === 'working') {
          const innerR = ringR - r * 0.18
          ctx.strokeStyle = rgba(color, 0.55)
          ctx.lineWidth = Math.max(0.8, size / 70)
          ctx.beginPath(); ctx.arc(c, c, innerR, -t * 1.7, -t * 1.7 + 1.1); ctx.stroke()
        }
      }

      const core = r * (0.15 + 0.03 * breathe)
      ctx.save()
      ctx.filter = `blur(${Math.max(1, r * 0.18)}px)`
      ctx.fillStyle = rgba(color, mood === 'offline' ? 0.1 : 0.7)
      ctx.beginPath(); ctx.arc(c, c, core * 1.6, 0, Math.PI * 2); ctx.fill()
      ctx.restore()
      ctx.fillStyle = mood === 'paused' || mood === 'offline' ? palette.text3 : palette.text
      ctx.beginPath(); ctx.arc(c, c, core, 0, Math.PI * 2); ctx.fill()
      if (!still) frame = requestAnimationFrame(draw)
    }
    frame = requestAnimationFrame(draw)
    return () => cancelAnimationFrame(frame)
  }, [mood, tint, size])
  return <canvas ref={ref} style={{ width: size, height: size, flex: 'none' }} aria-hidden />
}

export function Wordmark({ size = 12 }: { size?: number }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: size * 0.7 }} aria-label="Syph">
      <AgentOrb size={size * 2} />
      <span style={{ fontSize: size, fontWeight: 500, letterSpacing: size * 0.5, color: palette.text }}>SYPH</span>
    </div>
  )
}

/** Void canvas, one cold halo drifting at the top, faint horizon lines. */
export function Backdrop({ intensity = 1 }: { intensity?: number }) {
  const ref = useRef<HTMLCanvasElement>(null)
  useEffect(() => {
    const canvas = ref.current!
    const ctx = canvas.getContext('2d')!
    let frame = 0
    let last = 0
    const resize = () => {
      const dpr = window.devicePixelRatio || 1
      canvas.width = canvas.clientWidth * dpr
      canvas.height = canvas.clientHeight * dpr
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
    }
    resize()
    window.addEventListener('resize', resize)
    const draw = (now: number) => {
      if (now - last > 50 || last === 0) {
        last = now
        const w = canvas.clientWidth, h = canvas.clientHeight
        const t = now / 1000
        ctx.fillStyle = palette.void
        ctx.fillRect(0, 0, w, h)
        const drift = Math.sin(t / 9) * w * 0.08
        const big = Math.max(w, h) * 0.75
        const g1 = ctx.createRadialGradient(w * 0.62 + drift, -h * 0.05, 0, w * 0.62 + drift, -h * 0.05, big)
        g1.addColorStop(0, `rgba(74,99,217,${0.26 * intensity})`)
        g1.addColorStop(0.45, `rgba(74,99,217,${0.05 * intensity})`)
        g1.addColorStop(1, 'rgba(74,99,217,0)')
        ctx.fillStyle = g1; ctx.fillRect(0, 0, w, h)
        const g2 = ctx.createRadialGradient(w * 0.12 - drift, h * 1.05, 0, w * 0.12 - drift, h * 1.05, w * 0.55)
        g2.addColorStop(0, `rgba(127,220,184,${0.07 * intensity})`)
        g2.addColorStop(1, 'rgba(127,220,184,0)')
        ctx.fillStyle = g2; ctx.fillRect(0, 0, w, h)
        ctx.strokeStyle = `rgba(255,255,255,${0.018 * intensity})`
        ctx.lineWidth = 0.5
        const horizon = h * 0.78
        ctx.beginPath()
        for (let i = 0; i < 7; i++) {
          const y = horizon + Math.pow(i / 6, 2) * (h - horizon)
          ctx.moveTo(0, y); ctx.lineTo(w, y)
        }
        ctx.stroke()
      }
      if (!reduceMotion()) frame = requestAnimationFrame(draw)
    }
    frame = requestAnimationFrame(draw)
    return () => { cancelAnimationFrame(frame); window.removeEventListener('resize', resize) }
  }, [intensity])
  return <canvas ref={ref} style={{ position: 'absolute', inset: 0, width: '100%', height: '100%' }} aria-hidden />
}

export function moodFor(employee: { status?: string }, working?: { active: boolean } | null, waiting?: boolean): Mood {
  if (employee.status === 'paused') return 'paused'
  if (waiting) return 'attention'
  if (working?.active) return 'working'
  return 'idle'
}
