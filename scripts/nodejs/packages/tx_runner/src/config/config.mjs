import path from "path"
import {endpoints, generatedDir as sharedGeneratedDir, loadOverview} from "@simulator/shared";

export class Configuration {
    #config = {}

    constructor() {

        const generatedDir = sharedGeneratedDir()
        const netOverview = loadOverview()

        const walletsDir = path.resolve(netOverview.wallets_dir)
        const fundWalletsDir = path.resolve(walletsDir, "und")
        const gaiadWalletsDir = path.resolve(walletsDir, "gaiad")

        // a chain's RPC nodes, which the runner spreads its queries and txs across
        const rpcNodes = (nodes) => nodes.filter((node) => node.type === "rpc").map((node) => ({
            name: node.name,
            ...endpoints(node),
            rpc_port: node.rpc_port,
            grpc_port: node.grpc_port,
            rest_port: node.rest_port,
            container: node.docker_container,
        }))

        const fund = {
            chain: {
                bech32_prefix: "und",
                slip44: 5555,
            },
            name: "fund",
            chain_id: netOverview.fund_chain_id,
            rpcs: rpcNodes(netOverview.fund_nodes),
        }
        const gaiad = {
            chain: {
                bech32_prefix: "cosmos",
                slip44: 118,
            },
            name: "gaiad",
            chain_id: netOverview.gaiad_chain_id,
            rpcs: rpcNodes(netOverview.gaiad_nodes),
        }

        this.#config = {
            dirs: {
                generated: generatedDir,
                wallets: {
                    root: walletsDir,
                    fund: fundWalletsDir,
                    gaiad: gaiadWalletsDir,
                },
            },
            networks: {
                fund,
                gaiad,
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

