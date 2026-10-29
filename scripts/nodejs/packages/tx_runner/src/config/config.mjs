import fs from 'fs'
import path from "path"
import {generatedDir as sharedGeneratedDir, repoRoot} from "@simulator/shared";

export class Configuration {
    #config = {}

    constructor() {

        const generatedDir = sharedGeneratedDir()
        const rootDir = repoRoot
        const netOverviewPath = path.resolve(generatedDir, "network", "overview.json")
        const netOverviewContents = fs.readFileSync(netOverviewPath, 'utf8')
        const netOverview = JSON.parse(netOverviewContents)

        const walletsDir = path.resolve(netOverview.wallets_dir)
        const fundWalletsDir = path.resolve(walletsDir, "und")
        const gaiadWalletsDir = path.resolve(walletsDir, "gaiad")
        const tmpWalletsDir = path.resolve(walletsDir, "tmp")

        const thirdPartyBinDir = path.resolve(rootDir, "third_party", "bin")

        // und CLI used to submit the upgrade proposal: UND_BIN if set (a relative path is from the repo root), otherwise
        // the genesis und that make gen used, as recorded in overview.json. Checked here because a missing binary would
        // otherwise mean no proposal and a silent no-upgrade.
        const undBin = process.env.UND_BIN ? path.resolve(rootDir, process.env.UND_BIN) : netOverview.und_bin
        if (!fs.existsSync(undBin)) {
            throw new Error(`und binary not found at ${undBin} - run make gen, or set UND_BIN in packages/tx_runner/.env`)
        }

        const fund = {
            chain: {
                bech32_prefix: "und",
                slip44: 5555,
            },
            name: "fund",
            chain_id: netOverview.fund_chain_id,
            rpcs: [],
        }
        const gaiad = {
            chain: {
                bech32_prefix: "cosmos",
                slip44: 118,
            },
            name: "gaiad",
            chain_id: netOverview.gaiad_chain_id,
            rpcs: [],
        }

        for(let i = 0; i < netOverview.fund_nodes.length; i++){
            const node = netOverview.fund_nodes[i]
            if(node.type === "rpc") {
                fund.rpcs.push({
                    name: node.name,
                    rpc: `http://localhost:${node.rpc_port}`,
                    ws: `ws://localhost:${node.rpc_port}/websocket`,
                    grpc: `http://localhost:${node.grpc_port}`,
                    rest: `http://localhost:${node.rest_port}`,
                    rpc_port: node.rpc_port,
                    grpc_port: node.grpc_port,
                    rest_port: node.rest_port,
                })
            }
        }

        for(let i = 0; i < netOverview.gaiad_nodes.length; i++){
            const node = netOverview.gaiad_nodes[i]
            if(node.type === "rpc") {
                gaiad.rpcs.push({
                    name: node.name,
                    rpc: `http://localhost:${node.rpc_port}`,
                    ws: `ws://localhost:${node.rpc_port}/websocket`,
                    grpc: `http://localhost:${node.grpc_port}`,
                    rest: `http://localhost:${node.rest_port}`,
                    rpc_port: node.rpc_port,
                    grpc_port: node.grpc_port,
                    rest_port: node.rest_port,
                })
            }
        }

        this.#config = {
            dirs: {
                root: rootDir,
                generated: generatedDir,
                thirdPartyBin: thirdPartyBinDir,
                wallets: {
                    root: walletsDir,
                    fund: fundWalletsDir,
                    gaiad: gaiadWalletsDir,
                    tmp: tmpWalletsDir,
                },
            },
            networks: {
                fund,
                gaiad,
            },
            bins: {
                und: undBin,
            },
            net_overview: netOverview,
        }
    }

    randomRpc(network) {
        const rpcs = this.#config.networks[network].rpcs
        const rnd = Math.floor(Math.random() * rpcs.length)
        return rpcs[rnd]
    }

    get config() {
        return this.#config
    }
}

