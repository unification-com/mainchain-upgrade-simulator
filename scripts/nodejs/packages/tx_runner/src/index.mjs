import 'dotenv/config'

import {Runner} from "./runner/runner.mjs";
import {waitForNetwork} from "./runner/readiness.mjs";
import {Configuration} from "./config/config.mjs";
import {Logger} from './libs/logger.mjs'

// The node goes away for ~15s at the upgrade height while cosmovisor swaps the binary. Any query
// in flight at that moment rejects, and an unhandled rejection kills the whole runner mid-run -
// which is exactly when we most want it alive. Log and carry on instead: the next block tick
// simply retries. This mirrors what a real integrator's client has to cope with during an upgrade.
process.on('unhandledRejection', (reason) => {
    Logger.error("UNHANDLED", `${reason?.message ?? reason}`)
})
process.on('uncaughtException', (err) => {
    Logger.error("UNCAUGHT", `${err?.message ?? err}`)
})


const run = async () => {

    const logLevel = (process.env.LOG_LEVEL) ? process.env.LOG_LEVEL : "info"
    const config = new Configuration()

    await waitForNetwork(config.config.networks, logLevel)
    const runner = await Runner.createRunner(config)
    runner.run(logLevel)
}

run()
