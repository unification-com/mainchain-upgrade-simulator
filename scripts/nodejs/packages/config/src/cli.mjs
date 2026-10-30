// Usage: node src/cli.mjs [path/to/config.json]   (defaults to the repo's config.json)
// A relative path is taken from the repo root - yarn runs workspace scripts from the package directory, so the
// caller's own working directory is not available.
import fs from 'fs'
import path from 'path'
import {repoRoot} from '@simulator/shared'
import {validateConfig} from './validate.mjs'

const configPath = path.resolve(repoRoot, process.argv[2] ?? 'config.json')
// repo-relative for files in the repo, absolute for anything outside it
const relative = path.relative(repoRoot, configPath)
const name = relative && !relative.startsWith('..') ? relative : configPath

let config
try {
    config = JSON.parse(fs.readFileSync(configPath, 'utf8'))
} catch (e) {
    console.error(`${name}: cannot be read as JSON - ${e.message}`)
    process.exit(1)
}

const {errors, warnings} = validateConfig(config)
for (const w of warnings) console.warn(`warning: ${w}`)
if (errors.length > 0) {
    console.error(`${name} is invalid (${errors.length} problem${errors.length === 1 ? '' : 's'}):`)
    for (const e of errors) console.error(`  - ${e}`)
    process.exit(1)
}
console.log(`${name}: valid`)
