// Every operation the executor advertises to the server must map to a
// permission scope, or the bridge refuses it as "Unknown operation".
import fs from 'node:fs'

const executor = fs.readFileSync(new URL('../src/main/executor.ts', import.meta.url), 'utf8')
const policy = fs.readFileSync(new URL('../src/main/policy.ts', import.meta.url), 'utf8')
const list = (name) => {
  const m = executor.match(new RegExp(`${name} = \\[([^\\]]+)\\]`))
  if (!m) throw new Error(`${name} not found in executor.ts`)
  return [...m[1].matchAll(/'([a-z_]+)'/g)].map((x) => x[1])
}
const flags = new Set(['element_targets', 'shell_session']) // capabilities, not operations
const advertised = [...list('HOST_OPERATIONS'), ...list('APP_OPERATIONS')].filter((op) => !flags.has(op))
const missing = advertised.filter((op) => !policy.includes(`'${op}'`))
if (missing.length) {
  console.error(`Operations without a scope in policy.ts: ${missing.join(', ')}`)
  process.exit(1)
}
console.log(`${advertised.length} advertised operations all have a scope.`)
