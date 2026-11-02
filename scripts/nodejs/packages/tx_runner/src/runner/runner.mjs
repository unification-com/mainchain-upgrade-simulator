import {Logger} from '../libs/logger.mjs'
import {BlockActions} from "./actions.mjs";
import {subscribeToBlocks} from "./blocks.mjs";
import {QueryClients} from "./clients.mjs";
import {WalletSet} from "./wallets.mjs";

// Drives transactions on both chains block by block, through the upgrade: every new block runs that chain's actions.
// Start it once the network is up (readiness.mjs).
export class Runner {

    #config
    #actions

    constructor(config, actions) {
        this.#config = config
        this.#actions = actions
    }

    static async createRunner(config) {
        const networks = config.config.networks
        const upgradeHeight = parseInt(config.config.net_overview.fund_upgrade_height, 10)
        const wallets = await WalletSet.create(config)
        wallets.setEFundActionBlocks(upgradeHeight)
        const clients = await QueryClients.create(networks)
        return new Runner(config, new BlockActions(config, wallets, clients, upgradeHeight))
    }

    run(logLevel = "info") {
        Logger.setLevel(logLevel)
        const networks = this.#config.config.networks
        subscribeToBlocks("fund", networks.fund.rpcs[0].ws, (block) => this.#actions.onFundBlock(block))
        subscribeToBlocks("gaiad", networks.gaiad.rpcs[0].ws, () => this.#actions.onGaiadBlock())
    }
}
