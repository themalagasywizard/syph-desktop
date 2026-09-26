export const palette = {
  void: '#050507', panel: '#0e1015', text: '#f4f5f7', ice: '#9db8ff', iceDeep: '#4a63d9',
  mint: '#7fdcb8', amber: '#e3a55f', coral: '#ff8a80', violet: '#b79cff',
  text2: 'rgba(244,245,247,0.6)', text3: 'rgba(244,245,247,0.36)', faint: 'rgba(244,245,247,0.18)',
}

export function statusColor(raw: string | undefined): string {
  switch ((raw ?? '').toLowerCase()) {
    case 'active': case 'running': case 'working': case 'approved': case 'succeeded': case 'done': case 'completed': case 'verified':
      return palette.mint
    case 'waiting_for_approval': case 'waiting': case 'blocked': case 'ask': case 'queued': case 'delivered':
      return palette.amber
    case 'error': case 'failed': case 'rejected': case 'denied': case 'expired': case 'cancelled':
      return palette.coral
    case 'paused': case 'sleeping': case 'off':
      return palette.text3
    default:
      return palette.ice
  }
}

/** A stable hue per employee — the same FNV-1a hash as the Mac app, so colours match. */
export function hueFor(id: string): string {
  let hash = 1469598103934665603n
  for (const byte of new TextEncoder().encode(id)) hash = ((hash ^ BigInt(byte)) * 1099511628211n) & 0xffffffffffffffffn
  const hues = [0.62, 0.55, 0.47, 0.72, 0.8, 0.08, 0.4]
  // Mac: HSB(h, 0.45, 1.0) ≡ HSL(h, 100%, 77.5%)
  return `hsl(${Math.round(hues[Number(hash % BigInt(hues.length))] * 360)} 100% 77.5%)`
}

export function alpha(color: string, a: number): string {
  if (color.startsWith('#')) {
    const n = parseInt(color.slice(1), 16)
    return `rgba(${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255}, ${a})`
  }
  if (color.startsWith('hsl(')) return color.replace(')', ` / ${a})`)
  if (color.startsWith('rgba(')) return color.replace(/,\s*[\d.]+\)$/, `, ${a})`)
  return color
}
