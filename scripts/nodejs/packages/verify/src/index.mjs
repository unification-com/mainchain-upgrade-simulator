import {loadOverview} from "@simulator/shared";
import {bold, green, red} from "console-log-colors";
import {buildChecks} from "./checks.mjs";

// Runs every check against the live network and prints one [PASS]/[FAIL] line each. Exits non-zero if any fail,
// so `make verify` can gate a rehearsal. A check that throws (node down, route missing) counts as a FAIL.
const run = async () => {

    const overview = loadOverview()
    console.log(bold(`verify: ${overview.fund_upgrade_plan} at height ${overview.fund_upgrade_height} on ${overview.fund_chain_id}`))

    const checks = buildChecks(overview)
    let failed = 0
    for (const check of checks) {
        let result
        try {
            result = await check.run()
        } catch (e) {
            result = {pass: false, detail: e.message}
        }
        if (!result.pass) failed++
        console.log(`${result.pass ? green("[PASS]") : red("[FAIL]")} ${check.name}: ${result.detail}`)
    }

    console.log(failed === 0 ? green(bold(`all ${checks.length} checks passed`)) : red(bold(`${failed} of ${checks.length} checks failed`)))
    process.exit(failed === 0 ? 0 : 1)
}

run()
