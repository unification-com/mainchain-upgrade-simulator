import ReconnectingWebSocket from 'reconnecting-websocket'
import WS from 'ws';

import {
    createWallets,
    getRandomWallet,
    getRandomWalletNotThis
} from "../libs/wallet_utils.mjs";
import {RpcQueryClient} from "../queryClient/client.mjs";
import {isIdxOdd, portIsOpen, sleep} from "../libs/utils.mjs";
import { TxFactory} from "../tx/tx_factory.mjs";
import {Logger} from '../libs/logger.mjs'
import {Gov} from "../modules/gov.mjs";
import {Enterprise} from "../modules/enterprise.mjs";
import {Beacon} from "../modules/beacon.mjs";
import {WrkChain} from "../modules/wrkchain.mjs";
import {Module} from "../modules/module.mjs";
import {Bank} from "../modules/bank.mjs";
import {Stake} from "../modules/stake.mjs";
import {PaymentStream} from "../modules/stream.mjs";
import {IBC} from "../modules/ibc.mjs";

export class Runner {
    #config = null
    #wallets = null
    #queryClients = null

    #fundRpcIsIUp = false
    #gaiadRpcIsIUp = false

    #fundWs = null
    #gaiadWs = null
    #wsOptions = null

    #upgradeHeight = 0
    #currentBlockHeight = 0
    #currentGaiadHeight = 0

    #upgradeProposalSubmitted = false

    #ibcChannelOpen = false
    #ibcDenom = ""

    constructor(config, wallets, queryClients) {
        this.#config = config;
        this.#wallets = wallets;
        this.#queryClients = queryClients;

        this.#upgradeHeight = parseInt(config.config.net_overview.fund_upgrade_height, 10)

        this.#wsOptions = {
            WebSocket: WS, // custom WebSocket constructor
            connectionTimeout: 1000,
            maxRetries: 100,
        }

    }

    static async createRunner(config) {

        const fundRpcIsIUp = await Runner.checkRpcsUp("fund", config.config.networks)
        const gaiadRpcIsIUp = await Runner.checkRpcsUp("gaiad", config.config.networks)

        if(!fundRpcIsIUp || !gaiadRpcIsIUp) {
            Logger.error("NOOP", "network does not seem to be running. Wait until Docker composition is up, then run again")
            return null
        }

        const wallets = {
            fund: await createWallets(config, "fund"),
            gaiad: await createWallets(config, "gaiad")
        }

        const queryClients = {
            fund: {
                mainchainClients: [],
                cosmosClients: [],
                ibcClients: [],
            },
            gaiad: {
                cosmosClients: [],
                ibcClients: [],
            }
        }

        for(let i = 0; i < config.config.networks.fund.rpcs.length; i += 1) {
            const rpc = config.config.networks.fund.rpcs[i]
            const mainchainClient = await RpcQueryClient.createQueryClient(rpc.rpc, "mainchain")
            const cosmosClient = await RpcQueryClient.createQueryClient(rpc.rpc, "cosmos")
            const ibcClient = await RpcQueryClient.createQueryClient(rpc.rpc, "ibc")

            queryClients.fund.mainchainClients.push(mainchainClient)
            queryClients.fund.cosmosClients.push(cosmosClient)
            queryClients.fund.ibcClients.push(ibcClient)
        }

        for(let i = 0; i < config.config.networks.gaiad.rpcs.length; i += 1) {
            const rpc = config.config.networks.gaiad.rpcs[i]
            const cosmosClient = await RpcQueryClient.createQueryClient(rpc.rpc, "cosmos")
            const ibcClient = await RpcQueryClient.createQueryClient(rpc.rpc, "ibc")
            queryClients.gaiad.cosmosClients.push(cosmosClient)
            queryClients.gaiad.ibcClients.push(ibcClient)
        }

        return new Runner(config, wallets, queryClients);
    }

    async run(logLevel = "info") {

        Logger.setLevel(logLevel)

        while(!this.#fundRpcIsIUp || !this.#gaiadRpcIsIUp) {
            await this.setRpcIsUp()
            await sleep(100)
        }

        // set up eFUND from action blocks for beacon/wrkchain wallets
        const beaconWallets = this.getWalletsByNetworkAndType("fund", "beacon")
        this.setEFundActionFromBlockForWallets(beaconWallets)
        const wrkchainWallets = this.getWalletsByNetworkAndType("fund", "wrkchain")
        this.setEFundActionFromBlockForWallets(wrkchainWallets)

        await this.initWebsockets()
    }

    setEFundActionFromBlockForWallets(wallets) {
        for(let i = 0; i < wallets.length; i++) {
            const w = wallets[i]
            w.setEFundActionFromBlock(0)
            if(isIdxOdd(i)) {
                w.setEFundActionFromBlock(this.#upgradeHeight)
            }
        }
    }

    async setRpcIsUp() {
        this.#fundRpcIsIUp = await Runner.checkRpcsUp("fund", this.config.networks)
        this.#gaiadRpcIsIUp = await Runner.checkRpcsUp("gaiad", this.config.networks)
    }

    static async checkRpcsUp(network, netConfig) {
        const numRpcs = netConfig[network].rpcs.length
        let numUp = 0

        for(let i = 0; i < numRpcs; i += 1) {
            const rpc = netConfig[network].rpcs[i]
            const isUp = await portIsOpen(rpc.rpc_port)
            Logger.verbose("WAIT", `RPC ${rpc.name} on ${network} up = ${isUp}`)
            if(isUp) {
                numUp += 1
            }
        }
        Logger.info("WAIT", `${numUp} of ${numRpcs} ${network} RPCs up`)
        return numUp === numRpcs;
    }

    async initWebsockets() {
        Logger.info("RUN", "Connect to FUND WS", this.config.networks.fund.rpcs[0].ws)
        this.#fundWs = new ReconnectingWebSocket(this.config.networks.fund.rpcs[0].ws, [], this.#wsOptions);
        this.#fundWs.addEventListener('open',this.fundWsOnOpen.bind(this))
        this.#fundWs.addEventListener('close',this.fundWsOnClose.bind(this))
        this.#fundWs.addEventListener('message',this.fundWsOnMessage.bind(this))
        this.#fundWs.addEventListener('error',this.fundWsOnError.bind(this))

        Logger.info("RUN", "Connect to Gaiad WS", this.config.networks.gaiad.rpcs[0].ws)
        this.#gaiadWs = new ReconnectingWebSocket(this.config.networks.gaiad.rpcs[0].ws, [], this.#wsOptions);
        this.#gaiadWs.addEventListener('open',this.gaiadWsOnOpen.bind(this))
        this.#gaiadWs.addEventListener('close',this.gaiadWsOnClose.bind(this))
        this.#gaiadWs.addEventListener('message',this.gaiadWsOnMessage.bind(this))
        this.#gaiadWs.addEventListener('error',this.gaiadWsOnError.bind(this))
    }

    async fundWsOnOpen() {
        Logger.info("RUN", "net=fund", "subscribe to NewBlock")
        this.#fundWs.send(JSON.stringify({ "jsonrpc": "2.0", "method": "subscribe", "params":
                ["tm.event='NewBlock'"], "id": 1 }))
    }

    async fundWsOnClose() {
        Logger.warn("WAIT", "net=fund", 'websocket disconnected - probably upgrade in progress');
    }

    async fundWsOnMessage(msg) {
        const res = JSON.parse(msg.data)
        const block = res?.result?.data?.value?.block

        if(block) {
            Logger.info("=== START FUND BLOCK ACTIONS ===")
            this.#currentBlockHeight = parseInt(block?.header?.height, 10)
            Logger.info("FUND BLOCK HEIGHT", this.#currentBlockHeight)
            await this.checkTxs("fund")
            await this.checkIbcChannels()

            await sleep(1000)
            await this.validatorActions()

            if(this.#currentBlockHeight > 4) {
                await this.eFundActions()
                await this.beaconActions()
                await this.wrkChainActions()
                await this.sendTestTxs()
                await this.fundIbcTxs()
                await this.paymentStreamTxs()
            }

            this.moveSentToPending("fund")
            Logger.info("=== END FUND BLOCK ACTIONS ===")
        }
    }

    async fundWsOnError(error) {
        if(error) {
            Logger.error("WAIT", "net=fund", "WebSocket error:", JSON.stringify(error))
        }
    }

    async gaiadWsOnOpen() {
        Logger.info("RUN", "net=gaiad", "subscribe to NewBlock")
        this.#gaiadWs.send(JSON.stringify({ "jsonrpc": "2.0", "method": "subscribe", "params":
                ["tm.event='NewBlock'"], "id": 1 }))
    }

    async gaiadWsOnClose() {
        Logger.warn("WAIT", "net=gaiad", 'websocket disconnected - probably upgrade in progress');
    }

    async gaiadWsOnMessage(msg) {
        const res = JSON.parse(msg.data)
        const block = res?.result?.data?.value?.block

        if (block) {
            this.#currentGaiadHeight = parseInt(block?.header?.height, 10)
            Logger.info("=== START GAIAD BLOCK ACTIONS ===")
            await this.checkIbcChannels()
            await this.checkTxs("gaiad")
            await this.gaiadIbcTxs()
            this.moveSentToPending("gaiad")
            Logger.info("=== END GAIAD BLOCK ACTIONS ===")
        }
    }

    async gaiadWsOnError(error) {
        if(error) {
            Logger.error("WAIT", "net=gaiad", "WebSocket error:", JSON.stringify(error))
        }
    }

    async validatorActions() {

        Logger.info("RUN", "validator actions")

        if(!this.#upgradeProposalSubmitted) {
            const fromWallet = getRandomWallet(this.fundValidatorWallets)
            await Gov.submitUpgradeProposal(fromWallet, this.config)
            this.#upgradeProposalSubmitted = true
        } else {
            await Gov.validatorSubmitOrVote(this.fundCosmosQueryClient, this.fundValidatorWallets, true)
        }
    }

    async eFundActions() {
        const eFundWallets = this.getWalletsByNetworkAndType("fund", ["beacon", "wrkchain"])
        const enterpriseWallets = this.getWalletsByNetworkAndType("fund", "enterprise")
        await Enterprise.runActions(this.fundMainchainQueryClient, enterpriseWallets, eFundWallets, this.#currentBlockHeight)
    }

    async beaconActions() {
        Logger.info("RUN", "beacon actions")
        const wallets = this.getWalletsByNetworkAndType("fund", "beacon")
        await Beacon.runActions(this.fundMainchainQueryClient, wallets)
    }

    async wrkChainActions() {
        Logger.info("RUN", "beacon actions")
        const wallets = this.getWalletsByNetworkAndType("fund", "wrkchain")
        await WrkChain.runActions(this.fundMainchainQueryClient, wallets, this.#currentBlockHeight, this.#upgradeHeight, this.config)
    }

    async sendTestTxs() {
        const wallets = this.getWalletsByNetworkAndType("fund", "test")
        const validators = this.getWalletsByNetworkAndType("fund", "validator")

        const openProposals = await Gov.getOpenProposals(this.fundCosmosQueryClient)

        Logger.info("RUN", "send random test cosmos txs")

        for(let i = 0; i < wallets.length; i++) {
            const wallet = wallets[i]
            if(wallet.pendingTxs.length > 0) {
                continue
            }

            let randomModule
            if(openProposals && openProposals?.proposals.length > 0) {
                randomModule = Module.randomModule(true)
            } else {
                randomModule = Module.randomModule()
            }

            switch(randomModule) {
                case Module.MsgModules.BANK:
                    const toWallet = getRandomWalletNotThis(wallets, i)
                    await Bank.sendRandomMsg(this.fundCosmosQueryClient, wallet, toWallet)
                    break
                case Module.MsgModules.STAKE:
                    const val = getRandomWallet(validators)
                    await Stake.sendRandomMsg(this.fundCosmosQueryClient, wallet, val)
                    break
                case Module.MsgModules.GOV:
                    await Gov.sendRandomMsg(wallet, openProposals?.proposals[0])
                    break
            }
        }
    }

    async checkIbcChannels() {
        if(!this.#ibcChannelOpen) {
            const {open: fundOpen, } = await IBC.checkIbcChannel(this.fundIbcQueryClient, "fund")
            const {open: gaiadOpen, denom: ibcDenom } = await IBC.checkIbcChannel(this.gaiadIbcQueryClient, "gaiad")

            if(fundOpen && gaiadOpen) {
                this.#ibcChannelOpen = true
                this.#ibcDenom = ibcDenom
            }
        }
    }

    async fundIbcTxs() {

        Logger.info("RUN", "send FUND -> Gaiad IBC txs")
        if(!this.#ibcChannelOpen) {
            Logger.info("WAIT", "waiting for IBC channels to open")
            return
        }

        const fundWallets = this.getWalletsByNetworkAndType("fund", "ibc")
        const gaiadWallets = this.getWalletsByNetworkAndType("gaiad", "ibc")

        const rpc = this.configClass.randomRpc("fund")
        const timeoutHeight = await IBC.calculateIbcTimeoutHeight(rpc, "transfer", "channel-0")

        await IBC.runIbcTransfers(this.fundIbcQueryClient, this.gaiadIbcQueryClient, fundWallets, gaiadWallets, timeoutHeight, "nund", this.#ibcDenom, 0.001, 0.002)
    }

    async gaiadIbcTxs() {
        Logger.info("RUN", "send Gaiad -> FUND IBC txs")
        if(!this.#ibcChannelOpen) {
            Logger.info("WAIT", "waiting for IBC channels to open")
            return
        }

        const fundWallets = this.getWalletsByNetworkAndType("fund", "ibc")
        const gaiadWallets = this.getWalletsByNetworkAndType("gaiad", "ibc")

        const rpc = this.configClass.randomRpc("gaiad")
        const timeoutHeight = await IBC.calculateIbcTimeoutHeight(rpc, "transfer", "channel-0")

        await IBC.runIbcTransfers(this.gaiadIbcQueryClient, this.fundIbcQueryClient, gaiadWallets, fundWallets, timeoutHeight, this.#ibcDenom, "nund", 0.90, 0.99)
    }

    async paymentStreamTxs() {
        const senderWallets = this.getWalletsByNetworkAndType("fund", "stream_sender")
        const receiverWallets = this.getWalletsByNetworkAndType("fund", "stream_receiver")

        Logger.info("RUN", "payment stream txs")
        await PaymentStream.runStreamTxs(this.fundMainchainQueryClient, senderWallets, receiverWallets)
    }

    moveSentToPending(network) {
        const wallets = (network === "fund") ? this.fundWallets : this.gaiadWallets
        Logger.info("RUN", `net=${network}`, "move sent txs to pending txs")
        for(let i = 0; i < wallets.length; i++) {
            TxFactory.moveSentToPending(wallets[i])
        }
    }

    async checkTxs(network) {
        Logger.info("RUN", `net=${network}`, "Process previous Tx results")
        const wallets = (network === "fund") ? this.fundWallets : this.gaiadWallets
        for(let i = 0; i < wallets.length; i++) {
            const qc = this.randomQueryClient(network, "cosmosClients")
            await TxFactory.checkWalletTxs(wallets[i], qc)
        }
    }

    getWalletsByNetworkAndType(network, walletTypes) {
        const results = []
        let typesToCheck
        if(Array.isArray(walletTypes)) {
            typesToCheck = walletTypes
        } else {
            typesToCheck = [walletTypes]
        }

        const wallets = this.wallets[network]

        for(let i = 0; i < typesToCheck.length; i++) {
            const walletType = typesToCheck[i]
            for(let j = 0; j < wallets.length; j++) {
                const w = wallets[j]
                if(w.meta.wallet_json.wallet_type === walletType) {
                    results.push(w)
                }
            }
        }

        return results
    }

    getWalletByAddress(network, address) {
        const wallets = this.wallets[network]
        for(let i = 0; i < wallets.length; i++) {
            const w = wallets[i]
            if(w.meta.wallet_json.address_bech32 === address) {
                return w
            }
        }

        return null
    }

    printWaitForRpc() {
        console.clear()
        Logger.info("WAIT", "waiting for FUND/Gaiad RPCs up")
    }

    randomQueryClient(network, clientType) {
        const rnd = Math.floor(Math.random() * this.#queryClients[network][clientType].length)
        return this.#queryClients[network][clientType][rnd].client
    }

    //////////
    // Getters
    //////////

    get wallets() {
        return this.#wallets;
    }

    get fundWallets() {
        return this.#wallets.fund;
    }

    get fundValidatorWallets() {
        return this.getWalletsByNetworkAndType("fund", "validator")
    }

    get gaiadWallets() {
        return this.#wallets.gaiad;
    }

    get queryClients() {
        return this.#queryClients;
    }

    get fundQueryClients() {
        return this.#queryClients.fund;
    }

    get fundMainchainQueryClient() {
        const rnd = Math.floor(Math.random() * this.#queryClients.fund.mainchainClients.length)
        return this.#queryClients.fund.mainchainClients[rnd].client
    }

    get fundCosmosQueryClient() {
        const rnd = Math.floor(Math.random() * this.#queryClients.fund.cosmosClients.length)
        return this.#queryClients.fund.cosmosClients[rnd].client
    }

    get fundIbcQueryClient() {
        const rnd = Math.floor(Math.random() * this.#queryClients.fund.ibcClients.length)
        return this.#queryClients.fund.ibcClients[rnd].client
    }

    get gaiadQueryClients() {
        return this.#queryClients.gaiad;
    }

    get gaiadCosmosQueryClient() {
        const rnd = Math.floor(Math.random() * this.#queryClients.gaiad.cosmosClients.length)
        return this.#queryClients.gaiad.cosmosClients[rnd].client
    }

    get gaiadIbcQueryClient() {
        const rnd = Math.floor(Math.random() * this.#queryClients.gaiad.ibcClients.length)
        return this.#queryClients.gaiad.ibcClients[rnd].client
    }

    get config() {
        return this.#config.config;
    }

    get configClass() {
        return this.#config
    }

}
