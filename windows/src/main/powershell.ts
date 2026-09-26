import { app } from 'electron'
import { spawn } from 'node:child_process'
import path from 'node:path'

export interface ScriptResult { ok: boolean; summary: string; data?: Record<string, unknown> }

function scriptsDir() {
  return app.isPackaged ? path.join(process.resourcesPath, 'ps') : path.join(app.getAppPath(), 'resources', 'ps')
}

const POWERSHELL = path.join(process.env.SystemRoot ?? 'C:\\Windows', 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe')

/** Runs one bundled Windows PowerShell 5.1 script; it prints a single JSON line. */
export function runScript(name: string, args: Record<string, unknown>, timeoutMs = 60_000): Promise<ScriptResult> {
  return new Promise((resolve) => {
    const child = spawn(POWERSHELL, ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', path.join(scriptsDir(), `${name}.ps1`)], {
      env: { ...process.env, SYPH_ARGS: JSON.stringify(args) },
      windowsHide: true,
    })
    let out = ''
    let err = ''
    child.stdout.setEncoding('utf8').on('data', (d) => { out += d })
    child.stderr.setEncoding('utf8').on('data', (d) => { err += d })
    const timer = setTimeout(() => { child.kill(); resolve({ ok: false, summary: `${name} timed out.` }) }, timeoutMs)
    child.on('error', (e) => { clearTimeout(timer); resolve({ ok: false, summary: `PowerShell couldn't start: ${e.message}` }) })
    child.on('close', () => {
      clearTimeout(timer)
      const line = out.trim().split(/\r?\n/).filter(Boolean).pop()
      try {
        resolve(JSON.parse(line ?? '') as ScriptResult)
      } catch {
        resolve({ ok: false, summary: (err.trim().split(/\r?\n/)[0] || `${name} returned nothing.`).slice(0, 300) })
      }
    })
  })
}

export interface ShellOutput { stdout: string; stderr: string; status: number; timedOut: boolean }

/** A user command in PowerShell, run from the first shared folder. */
export function runCommand(command: string, cwd: string, timeoutMs = 120_000): Promise<ShellOutput> {
  return new Promise((resolve) => {
    const prefix = '[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; $ProgressPreference = "SilentlyContinue"; '
    const child = spawn(POWERSHELL, ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', prefix + command], {
      cwd, windowsHide: true,
    })
    let stdout = ''
    let stderr = ''
    let timedOut = false
    child.stdout.setEncoding('utf8').on('data', (d) => { if (stdout.length < 60_000) stdout += d })
    child.stderr.setEncoding('utf8').on('data', (d) => { if (stderr.length < 60_000) stderr += d })
    const timer = setTimeout(() => { timedOut = true; child.kill() }, timeoutMs)
    child.on('error', (e) => { clearTimeout(timer); resolve({ stdout, stderr: e.message, status: -1, timedOut }) })
    child.on('close', (code) => { clearTimeout(timer); resolve({ stdout, stderr, status: code ?? -1, timedOut }) })
  })
}
