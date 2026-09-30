// Builds build/icon.ico (PNG-compressed entries, Vista+) and build/icon.png
// from the Mac app icon set, so both apps ship the same mark.
import fs from 'node:fs'
import path from 'node:path'

const set = path.join(import.meta.dirname, '..', '..', 'mac', 'Syph-Mac', 'Assets.xcassets', 'AppIcon.appiconset')
const sources = [[16, 'icon_16x16.png'], [32, 'icon_32x32.png'], [48, null], [64, 'icon_32x32@2x.png'], [128, 'icon_128x128.png'], [256, 'icon_256x256.png']]
const images = sources.filter(([, f]) => f && fs.existsSync(path.join(set, f))).map(([size, f]) => [size, fs.readFileSync(path.join(set, f))])

const header = Buffer.alloc(6)
header.writeUInt16LE(0, 0); header.writeUInt16LE(1, 2); header.writeUInt16LE(images.length, 4)
const entries = []
let offset = 6 + 16 * images.length
for (const [size, png] of images) {
  const e = Buffer.alloc(16)
  e.writeUInt8(size >= 256 ? 0 : size, 0); e.writeUInt8(size >= 256 ? 0 : size, 1)
  e.writeUInt8(0, 2); e.writeUInt8(0, 3); e.writeUInt16LE(1, 4); e.writeUInt16LE(32, 6)
  e.writeUInt32LE(png.length, 8); e.writeUInt32LE(offset, 12)
  entries.push(e); offset += png.length
}
const out = path.join(import.meta.dirname, '..', 'build')
fs.mkdirSync(out, { recursive: true })
fs.writeFileSync(path.join(out, 'icon.ico'), Buffer.concat([header, ...entries, ...images.map(([, png]) => png)]))
fs.copyFileSync(path.join(set, 'icon_512x512.png'), path.join(out, 'icon.png'))
console.log(`build/icon.ico: ${images.map(([s]) => s).join(', ')} px`)
