import {portIsOpen, sleep} from "@simulator/shared";
import {Logger} from "../libs/logger.mjs";

// Whether every RPC node of a network is accepting connections.
const rpcsUp = async (networks, network) => {
    const rpcs = networks[network].rpcs
    let numUp = 0
    for (const rpc of rpcs) {
        const isUp = await portIsOpen(rpc.rpc_port)
        Logger.verbose("WAIT", `RPC ${rpc.name} on ${network} up = ${isUp}`)
        if (isUp) {
            numUp += 1
        }
    }
    Logger.info("WAIT", `${numUp} of ${rpcs.length} ${network} RPCs up`)
    return numUp === rpcs.length
}

const latestHeight = async (rpc) => {
    const status = await (await fetch(`${rpc}/status`)).json()
    return parseInt(status?.result?.sync_info?.latest_block_height, 10)
}

// Waits until both chains' RPC nodes are up and each chain has produced a block - the runner starts before the network
// does, and its query clients and websockets need both.
export const waitForNetwork = async (networks, logLevel) => {
    const waiting = (what) => {
        console.clear()
        Logger.info("WAIT", `Log Level: ${logLevel}`)
        Logger.info("WAIT", what)
    }

    const bothUp = async () => {
        const fund = await rpcsUp(networks, "fund")
        const gaiad = await rpcsUp(networks, "gaiad")
        return fund && gaiad
    }
    while (!(await bothUp())) {
        waiting("wait for FUND and Gaiad RPC up")
        await sleep(1000)
    }

    let fundBlock = 0
    let gaiadBlock = 0
    while (!(fundBlock >= 1) || !(gaiadBlock >= 1)) {
        waiting("wait for first blocks")
        await sleep(500)
        try {
            fundBlock = await latestHeight(networks.fund.rpcs[0].rpc)
            gaiadBlock = await latestHeight(networks.gaiad.rpcs[0].rpc)
        } catch (err) {}
    }
}
