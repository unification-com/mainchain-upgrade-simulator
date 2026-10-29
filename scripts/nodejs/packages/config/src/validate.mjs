import fs from 'fs'
import path from 'path'
import Ajv from 'ajv'
import addFormats from 'ajv-formats'
import {repoRoot} from '@simulator/shared'

export const schemaPath = path.join(repoRoot, 'schema', 'config.schema.json')

// Edit distance, for "did you mean" hints on misspelt keys
const distance = (a, b) => {
    const row = Array.from({length: b.length + 1}, (_, i) => i)
    for (let i = 1; i <= a.length; i++) {
        let prev = row[0]
        row[0] = i
        for (let j = 1; j <= b.length; j++) {
            const cur = row[j]
            row[j] = Math.min(row[j] + 1, row[j - 1] + 1, prev + (a[i - 1] === b[j - 1] ? 0 : 1))
            prev = cur
        }
    }
    return row[b.length]
}

const closest = (key, candidates) => {
    const best = candidates.map((c) => [c, distance(key, c)]).sort((x, y) => x[1] - y[1])[0]
    return best && best[1] <= Math.max(2, Math.floor(key.length / 3)) ? best[0] : null
}

const describe = (err) => {
    const at = err.instancePath || '/'
    if (err.keyword === 'additionalProperties') {
        const key = err.params.additionalProperty
        const hint = closest(key, Object.keys(err.parentSchema.properties ?? {}))
        return `${at}: unknown field "${key}"` + (hint ? ` (did you mean "${hint}"?)` : '')
    }
    if (err.keyword === 'required') return `${at}: missing field "${err.params.missingProperty}"`
    return `${at}: ${err.message}`
}

let compiled = null
const validator = () => {
    if (!compiled) {
        const ajv = new Ajv({allErrors: true, verbose: true, $data: true, strict: true})
        addFormats(ajv)
        compiled = ajv.compile(JSON.parse(fs.readFileSync(schemaPath, 'utf8')))
    }
    return compiled
}

// Problems the schema cannot express, but which are worth flagging without failing the run
const warningsFor = (config) => {
    const und = config?.apps?.und
    const numValidators = und?.nodes?.num_validators
    return (und?.staking?.stake_overrides ?? [])
        .filter((o) => Number.isInteger(numValidators) && o.validator > numValidators)
        .map((o) => `/apps/und/staking/stake_overrides: override for validator ${o.validator} is ignored (num_validators is ${numValidators})`)
}

// Validate a parsed config.json against the schema. Errors stop generation; warnings do not.
export const validateConfig = (config) => {
    const validate = validator()
    const ok = validate(config)
    return {
        errors: ok ? [] : validate.errors.map(describe),
        warnings: ok ? warningsFor(config) : [],
    }
}
