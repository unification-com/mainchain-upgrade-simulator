import 'dotenv/config'

import {Runner} from "./runner/runner.mjs";
import {Configuration} from "./config/config.mjs";
import {sleep} from "./libs/utils.mjs";
import {Logger} from './libs/logger.mjs'


const run = async () => {

    const logLevel = (process.env.LOG_LEVEL) ? process.env.LOG_LEVEL : "info"
    const config = new Configuration()

    // wait for RPC up
    let fundRpcIsIUp = await Runner.checkRpcsUp("fund", config.config.networks)
    let gaiadRpcIsIUp = await Runner.checkRpcsUp("gaiad", config.config.networks)
    let fundBlock = 0
    let gaiadBlock = 0

    while(!fundRpcIsIUp || !gaiadRpcIsIUp) {
        console.clear()
        Logger.info("WAIT", `Log Level: ${logLevel}`)
        Logger.info("WAIT", "wait for FUND and Gaiad RPC up")
        fundRpcIsIUp = await Runner.checkRpcsUp("fund", config.config.networks)
        gaiadRpcIsIUp = await Runner.checkRpcsUp("gaiad", config.config.networks)
        await sleep(1000)
    }

    while(fundBlock < 1 || gaiadBlock < 1) {
        console.clear()
        Logger.info("WAIT", `Log Level: ${logLevel}`)
        Logger.info("WAIT", "wait for first blocks")
        await sleep(500)
        try {
            const fundRes = await fetch(`${config.config.networks.fund.rpcs[0].rpc}/status`)
            const fundStatus = await fundRes.json()
            fundBlock = parseInt(fundStatus?.result?.sync_info?.latest_block_height, 10)

            const gaiadRes = await fetch(`${config.config.networks.gaiad.rpcs[0].rpc}/status`)
            const gaiadStatus = await gaiadRes.json()
            gaiadBlock = parseInt(gaiadStatus?.result?.sync_info?.latest_block_height, 10)

        } catch(err) {}
    }

    const runner = await Runner.createRunner(config)

    if(!runner) {
        process.exit(1)
    }

    await runner.run(logLevel)

}

run()
