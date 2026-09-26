export function parseDate(raw?: string | null): Date | null {
  if (!raw) return null
  let s = raw
  if (!/[zZ]|[+-]\d\d:?\d\d$/.test(s)) s += 'Z'
  const d = new Date(s)
  return isNaN(d.getTime()) ? null : d
}

export function relative(raw?: string | null): string {
  const d = parseDate(raw)
  if (!d) return ''
  const seconds = (Date.now() - d.getTime()) / 1000
  if (Math.abs(seconds) < 45) return 'now'
  const rtf = new Intl.RelativeTimeFormat(undefined, { numeric: 'always', style: 'narrow' })
  const units: [Intl.RelativeTimeFormatUnit, number][] = [['year', 31536000], ['month', 2592000], ['week', 604800], ['day', 86400], ['hour', 3600], ['minute', 60]]
  for (const [unit, size] of units) {
    if (Math.abs(seconds) >= size) return rtf.format(-Math.round(seconds / size), unit)
  }
  return rtf.format(-Math.round(seconds), 'second')
}

export function clock(raw?: string | null): string {
  const d = parseDate(raw)
  if (!d) return ''
  const today = new Date().toDateString() === d.toDateString()
  return today
    ? d.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' })
    : d.toLocaleString(undefined, { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' })
}

export function isPast(raw?: string | null): boolean {
  const d = parseDate(raw)
  return !!d && d.getTime() < Date.now()
}
