import {test} from 'node:test'
import assert from 'node:assert/strict'
import fs from 'fs'
import path from 'path'
import {repoRoot} from '@simulator/shared'
import {validateConfig} from '../src/validate.mjs'

const example = JSON.parse(fs.readFileSync(path.join(repoRoot, 'example.config.json'), 'utf8'))

// a copy of example.config.json with one change applied
const variant = (change) => {
    const c = structuredClone(example)
    change(c)
    return c
}

const errorsFor = (change) => validateConfig(variant(change)).errors

test('example.config.json is valid', () => {
    assert.deepEqual(validateConfig(example).errors, [])
})

test('a misspelt key is rejected with a suggestion', () => {
    const errors = errorsFor((c) => {
        c.apps.und.nodes.num_validatros = c.apps.und.nodes.num_validators
        delete c.apps.und.nodes.num_validators
    })
    assert.ok(errors.some((e) => e.includes('unknown field "num_validatros"') && e.includes('did you mean "num_validators"')), errors.join('\n'))
    assert.ok(errors.some((e) => e.includes('missing field "num_validators"')), errors.join('\n'))
})

test('an empty upgrade plan name is rejected', () => {
    assert.ok(errorsFor((c) => { c.apps.und.upgrade.upgrade_plan_name = '' }).some((e) => e.startsWith('/apps/und/upgrade/upgrade_plan_name')))
})

test('an upgrade height of 0 is rejected', () => {
    assert.ok(errorsFor((c) => { c.apps.und.upgrade.upgrade_height = 0 }).some((e) => e.startsWith('/apps/und/upgrade/upgrade_height')))
})

test('a run without an RPC node is rejected', () => {
    assert.ok(errorsFor((c) => { c.apps.und.nodes.num_rpcs = 0 }).some((e) => e.startsWith('/apps/und/nodes/num_rpcs')))
})

test('the enterprise acceptance threshold cannot exceed the signers', () => {
    const errors = errorsFor((c) => { c.apps.und.accounts.num_ent_accepts = c.apps.und.accounts.num_ent_signers + 1 })
    assert.ok(errors.some((e) => e.startsWith('/apps/und/accounts/num_ent_accepts')), errors.join('\n'))
})

test('max_stake cannot be below min_stake', () => {
    const errors = errorsFor((c) => { c.apps.und.staking.max_stake = c.apps.und.staking.min_stake - 1 })
    assert.ok(errors.some((e) => e.startsWith('/apps/und/staking/max_stake')), errors.join('\n'))
})

test('a malformed genesis_time is rejected', () => {
    assert.ok(errorsFor((c) => { c.apps.und.genesis_time = 'yesterday' }).some((e) => e.startsWith('/apps/und/genesis_time')))
})

test('a version with a leading v is rejected', () => {
    assert.ok(errorsFor((c) => { c.apps.und.genesis.version = 'v1.12.0' }).some((e) => e.startsWith('/apps/und/genesis/version')))
})

test('a stake override beyond num_validators is a warning, not an error', () => {
    const {errors, warnings} = validateConfig(variant((c) => {
        c.apps.und.nodes.num_validators = 3
        c.apps.und.staking.stake_overrides = [{validator: 1}, {validator: 4}]
    }))
    assert.deepEqual(errors, [])
    assert.deepEqual(warnings, ['/apps/und/staking/stake_overrides: override for validator 4 is ignored (num_validators is 3)'])
})
