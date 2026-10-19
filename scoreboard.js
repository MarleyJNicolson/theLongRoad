import { existsSync, readFileSync, writeFileSync } from 'node:fs'
import { resolve } from 'node:path'

// A Vite dev-server plugin that keeps the scoreboard in a plain text file,
// scoreboard.txt in the project folder. The game posts each finished run to
// /api/scores; the file is rewritten as a ranked table you can read (or edit)
// by hand. Each row is also how the scores are read back in.

const FILE = resolve(import.meta.dirname, 'scoreboard.txt')
const KEEP = 100 // runs kept on the board
const COLUMNS = ['Rank', 'Name', 'Score', 'Distance', 'Felled', 'Gold', 'Region', 'Fate', 'Date']

const pad = (v, n, left = false) => (left ? String(v).padStart(n) : String(v).padEnd(n))

function read() {
  if (!existsSync(FILE)) return []
  return readFileSync(FILE, 'utf8')
    .split('\n')
    .filter((line) => /^\s*\d+\s*\|/.test(line))
    .map((line) => {
      const [, name, score, distance, kills, gold, region, fate, date] = line.split('|').map((c) => c.trim())
      return { name, score: +score, distance: parseInt(distance), kills: +kills, gold: +gold, region, fate, date }
    })
}

function write(runs) {
  const rows = runs.map((r, k) => [k + 1, r.name, r.score, `${r.distance} m`, r.kills, r.gold, r.region, r.fate, r.date])
  const widths = COLUMNS.map((c, i) => Math.max(c.length, ...rows.map((row) => String(row[i]).length)))
  const line = (cells) => cells.map((c, i) => pad(c, widths[i], i === 0 || (i >= 2 && i < 6))).join(' | ')
  const text = [
    'SCOREBOARD',
    'Score = metres travelled + 20 per raider felled + 5 per gold piece',
    '',
    line(COLUMNS),
    widths.map((w) => '-'.repeat(w)).join('-+-'),
    ...rows.map(line),
    '',
  ].join('\n')
  writeFileSync(FILE, text)
}

// e.g. 2026-10-19 18:25, in the local time zone
function localDate(d = new Date()) {
  const two = (n) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${two(d.getMonth() + 1)}-${two(d.getDate())} ${two(d.getHours())}:${two(d.getMinutes())}`
}

export function score({ distance, kills, gold }) {
  return distance + kills * 20 + gold * 5
}

export default function scoreboard() {
  return {
    name: 'scoreboard',
    configureServer(server) {
      server.middlewares.use('/api/scores', (req, res) => {
        const reply = (body) => {
          res.setHeader('Content-Type', 'application/json')
          res.end(JSON.stringify(body))
        }
        if (req.method === 'GET') return reply({ top: read() })
        if (req.method !== 'POST') {
          res.statusCode = 405
          return res.end()
        }
        let body = ''
        req.on('data', (chunk) => (body += chunk))
        req.on('end', () => {
          try {
            const run = JSON.parse(body)
            const clean = (s) => String(s ?? '').replace(/[|\n]/g, ' ').slice(0, 60)
            const entry = {
              name: clean(run.name).slice(0, 20).trim() || 'Anonymous',
              distance: Math.max(0, Math.floor(+run.distance || 0)),
              kills: Math.max(0, Math.floor(+run.kills || 0)),
              gold: Math.max(0, Math.floor(+run.gold || 0)),
              region: clean(run.region),
              fate: clean(run.fate),
              date: localDate(),
            }
            entry.score = score(entry)
            const runs = [...read(), entry].sort((a, b) => b.score - a.score).slice(0, KEEP)
            write(runs)
            const rank = runs.indexOf(entry) + 1 // 0 if it didn't make the board
            reply({ rank, entry, top: runs.slice(0, 10) })
          } catch (e) {
            res.statusCode = 400
            reply({ error: e.message })
          }
        })
      })
    },
  }
}
