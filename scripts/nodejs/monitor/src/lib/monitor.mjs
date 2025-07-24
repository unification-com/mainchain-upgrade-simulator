import ReconnectingWebSocket from 'reconnecting-websocket'
import WS from 'ws';
import { sha256 } from '@noble/hashes/sha2'
import { bytesToHex } from '@noble/hashes/utils'
import { color, bold } from 'console-log-colors';
import { Table }  from 'console-table-printer'
import fs from "fs-extra";
import path from "path";
import readline from 'node:readline';
import cliCursor from 'cli-cursor';

import {
    checkNodeUpgradedFromLogs,
    dockerComposeIsUp, getCurrentSoftwareVersion,
    getDockerLogs, getHermesCreateStatus, getHermesStarted,
    getLastHeightFromLogs,
    getTotalTxData
} from "./docker.mjs";
import {getNetworkInfo, rpcIsUp, sleep} from "./utils.mjs";

const OPT_KEYS = {
    E: {key: "e", opt: "efund", cycle: true},
    I: {key: "i", opt: "ibc", cycle: true},
    O: {key: "o", opt: "overview", cycle: true},
    P: {key: "p", opt: "streams", cycle: true},
    B: {key: "b", opt: "beacons", cycle: true},
    W: {key: "w", opt: "wrkchains", cycle: true},
    C: {key: "c", opt: "cycle", cycle: false},
    Q: {key: "q", opt: "quit", cycle: false},
}

const ERRS = {
    NOT_EXIST: "not_exist",
}

export class UpgradeMonitor {

    #netOverview = null
    #containers = null
    #queryNodes = null

    #numContainers = 0
    #numContainersUp = 0
    #dockerIsUp = false
    #fundRpcIsIUp = false
    #gaiadRpcIsIUp = false
    #networkUpgraded = false
    #networkUpgradeStatus = "NOT UPGRADED \u{1F634}"
    #numUpgraded = 0
    #heightBeforeUpgrade = 0
    #upgradeHeight = 0
    #upgradeProposalStatus = "Not Submitted"

    #ws = null
    #wsOptions = null

    #currentBlockHeight = 0
    #totalValidTxs = 0
    #totalInvalidTxs = 0
    #blockValidTxs = 0
    #blockInvalidTxs = 0

    #totalFundSupply = 0
    #totalEfundSupply = 0
    #totalSpentEfund = 0
    #totalFundOnIbcChain = 0
    #totalFundDecOnIbcChain = 0

    #communityPool = 0
    #communityPoolDenom = ""
    #bondedTokens = 0
    #notBondedTokens = 0

    #raisedPos = 0
    #acceptedPos = 0
    #completedPos = 0
    #purchaseOrders = []

    #fundIbcChannel = null
    #gaiadIbcChannel = null
    #fundIbcChannelState = "UNRECOGNIZED"
    #gaiadIbcChannelState = "UNRECOGNIZED"
    #ibcDenom = ""

    #ibcHermesStatus = ""

    #numActiveStreams = 0
    #streamSenderReceiverPairs = []
    #paymentStreams = []

    #streamSender = null
    #streamReceiver = null

    #numReggedBeacons = 0
    #numReggedWrkchains = 0
    #beacons = []
    #wrkchains = []

    #eFundPurchaseOrders = []

    #displayOption = OPT_KEYS.O.key
    #cycleDisplays = false

    constructor(netOverview) {
        this.#netOverview = netOverview;
        const [containers, queryNodes] = getNetworkInfo(netOverview)

        this.#containers = containers;
        this.#queryNodes = queryNodes;
        this.#numContainers = netOverview.fund_nodes.length

        this.#heightBeforeUpgrade = parseInt(netOverview.fund_upgrade_height, 10) - 1
        this.#upgradeHeight = parseInt(netOverview.fund_upgrade_height, 10)

        this.#wsOptions = {
            WebSocket: WS, // custom WebSocket constructor
            connectionTimeout: 1000,
            maxRetries: 100,
        }
    }

    processKeypress(chunk, key) {
        if(key) {
            switch(key.name) {
                case OPT_KEYS.P.key:
                case OPT_KEYS.O.key:
                case OPT_KEYS.E.key:
                case OPT_KEYS.I.key:
                case OPT_KEYS.B.key:
                case OPT_KEYS.W.key:
                    this.#cycleDisplays = false
                    this.#displayOption = key.name
                    this.printStats()
                    break
                case OPT_KEYS.C.key:
                    this.#cycleDisplays = !this.#cycleDisplays
                    break
                case OPT_KEYS.Q.key:
                    console.log("")
                    process.exit();
            }
        }
    }

    async run() {

        readline.emitKeypressEvents(process.stdin);

        if (process.stdin.isTTY)
            process.stdin.setRawMode(true);

        const doProcessKeypress = this.processKeypress.bind(this)
        process.stdin.on('keypress', doProcessKeypress);

        cliCursor.hide()

        this.#displayOption = OPT_KEYS.O.key

        const walletsDir = path.resolve(this.#netOverview.wallets_dir)
        const srcDir = path.resolve(walletsDir, "und")
        const walletFiles = await fs.readdir(srcDir)
        for(let i = 0; i < walletFiles.length; i++) {
            const walletFile = walletFiles[i]
            const w = await fs.readFile(path.resolve(srcDir, walletFile))
            const wJson = JSON.parse(w)
            if(wJson.account === "stream_sender1") {
                this.#streamSender = wJson.address_bech32
            }
            if(wJson.account === "stream_receiver1") {
                this.#streamReceiver = wJson.address_bech32
            }
        }

        // check docker composition is up
        while (!this.#dockerIsUp) {
            this.printWaitForDocker()
            await this.setDockerIsUp()
            await sleep(500)
        }

        while(!this.#fundRpcIsIUp || !this.#gaiadRpcIsIUp) {
            this.printWaitForRpc()
            await this.setRpcIsUp()
            await sleep(500)
        }

        await this.setTxTotals()

        await this.initWebsocket()

        const runRefreshAndPrint = this.refreshAndPrint.bind(this)

        setInterval(async function () {
            await runRefreshAndPrint()
        }, 1000);

        const runCycleOptions = this.cycleOptions.bind(this)
        let opts = [
            OPT_KEYS.O.key,
            OPT_KEYS.P.key,
            OPT_KEYS.I.key,
            OPT_KEYS.E.key,
            OPT_KEYS.B.key,
            OPT_KEYS.W.key,
        ]
        setInterval(function() {
            opts = runCycleOptions(opts)
        }, 5000)

    }

    async refreshAndPrint() {
        await this.getHermesStatus()
        await this.fetchFundOnIbcSupply()
        await this.getIbcChannels()
        await this.setRpcIsUp()
        await this.processDockerLogs()
        await this.getUpgradeProposalStatus()
        await this.fetchPaymentStreams()
        await this.monitorPaymentStream()
        await this.fetchNumReggedBeacons()
        await this.fetchNumReggedWrkchains()
        await this.fetchEfundPurchaseOrders()
        await this.fetchCommunityPool()
        await this.fetchBondedTokens()
        this.printStats()
    }

    cycleOptions(opts) {
        if(this.#cycleDisplays) {
            const opt = opts.shift()
            this.#displayOption = opt
            opts.push(opt)
        }
        return opts
    }

    async setRpcIsUp() {
        this.#fundRpcIsIUp = await rpcIsUp(this.#queryNodes.fund.rpc_port)
        this.#gaiadRpcIsIUp = await rpcIsUp(this.#queryNodes.gaiad.rpc_port)
    }

    async setDockerIsUp() {
        this.#numContainersUp = await dockerComposeIsUp(this.#netOverview.fund_container_prefix)
        if (this.#numContainersUp === this.#numContainers) {
            this.#dockerIsUp = true
        }
    }

    async setTxTotals() {
        const rpcLogs = await getDockerLogs(this.#queryNodes.fund.container, "all")
        const [totalValidTxs, totalInvalidTxs] = getTotalTxData(rpcLogs)
        this.#totalValidTxs = totalValidTxs
        this.#totalInvalidTxs = totalInvalidTxs
    }

    async initWebsocket() {
        console.log(`Connect to WS ${this.#queryNodes.fund.ws}`)
        this.#ws = new ReconnectingWebSocket(this.#queryNodes.fund.ws, [], this.#wsOptions);
        this.#ws.addEventListener('open',this.wsOnOpen.bind(this))
        this.#ws.addEventListener('message',this.wsOnMessage.bind(this))
    }

    async wsOnOpen() {
        console.log("subscribe to NewBlock")
        this.#ws.send(JSON.stringify({ "jsonrpc": "2.0", "method": "subscribe", "params":
                ["tm.event='NewBlock'"], "id": 1 }))
        this.printStats()
    }

    async wsOnMessage(msg) {
        const res = JSON.parse(msg.data)
        const block = res?.result?.data?.value?.block
        if(block) {
            this.#currentBlockHeight = parseInt(block?.header?.height, 10)

            // total Txs
            const l = await getDockerLogs("t_dn_fund_rpc1", 400)
            let [blockValidTxs, blockInvalidTxs] = getTotalTxData(l, (this.#currentBlockHeight >= this.#upgradeHeight) ,this.#currentBlockHeight)

            this.#totalValidTxs += blockValidTxs
            this.#totalInvalidTxs += blockInvalidTxs
            this.#blockValidTxs = blockValidTxs
            this.#blockInvalidTxs = blockInvalidTxs

            if(this.#currentBlockHeight === this.#heightBeforeUpgrade) {
                await this.monitorUpgradeLogs()
            }
        }
    }

    async processDockerLogs() {
        for (const [container, info] of Object.entries(this.#containers)) {
            const l = await getDockerLogs(info.container, 1000)
            this.#containers[container].height = getLastHeightFromLogs(l)

            if(this.#containers[container].und_version === null && this.#currentBlockHeight < this.#heightBeforeUpgrade) {
                this.#containers[container].und_version = getCurrentSoftwareVersion(l)
            }
            if(this.#containers[container].und_version === null && this.#currentBlockHeight >= this.#upgradeHeight) {
                this.#containers[container].und_version = getCurrentSoftwareVersion(l)
            }
        }
    }

    async fetchFundtotalSupply() {
        try {
            const response = await fetch(`${this.#queryNodes.fund.rest}/cosmos/bank/v1beta1/supply/by_denom?denom=nund`);
            const data = await response.json();
            let amnt = 0
            if (data?.amount?.amount) {
                amnt = parseInt(data.amount.amount, 10) / 10 ** 9
            }
            this.#totalFundSupply = new Intl.NumberFormat("en-GB", {}).format(
                amnt,
            )
        } catch (error) {}
    }

    async fetchEfundtotalSupply() {
        try {
            const response = await fetch(`${this.#queryNodes.fund.rest}/mainchain/enterprise/v1/locked`);
            const data = await response.json();
            let amnt = 0
            if (data?.amount?.amount) {
                amnt = parseInt(data.amount.amount, 10) / 10 ** 9
            }
            this.#totalEfundSupply = new Intl.NumberFormat("en-GB", {}).format(
                amnt,
            )
        } catch (error) {}
    }

    async fetchSpentEfund() {
        try {
            const response = await fetch(`${this.#queryNodes.fund.rest}/mainchain/enterprise/v1/total_spent`);
            const data = await response.json();
            let amnt = 0
            if (data?.amount?.amount) {
                amnt = parseInt(data.amount.amount, 10) / 10 ** 9
            }
            this.#totalSpentEfund = new Intl.NumberFormat("en-GB", {}).format(
                amnt,
            )
        } catch (error) {}
    }

    async fetchFundOnIbcSupply() {
        if(!this.#gaiadRpcIsIUp) {
            return
        }
        try {
            const response = await fetch(`${this.#queryNodes.gaiad.rest}/cosmos/bank/v1beta1/supply/by_denom?denom=${this.#netOverview.ibc_denom}`);
            const data = await response.json();
            let amnt = 0
            if (data?.amount?.amount) {
                amnt = parseInt(data.amount.amount, 10) / 10 ** 9
            }
            this.#totalFundOnIbcChain = new Intl.NumberFormat("en-GB", {}).format(
                Math.round(amnt),
            )
            this.#totalFundDecOnIbcChain = new Intl.NumberFormat("en-GB", {}).format(
                amnt,
            )
        } catch (error) {}
    }

    async fetchNumReggedBeacons() {
        try {
            const response = await fetch(`${this.#queryNodes.fund.rest}/mainchain/beacon/v1/beacons`);
            const data = await response.json();
            if (data?.beacons) {
                this.#numReggedBeacons = data.beacons.length
                this.#beacons = data.beacons
            }
        } catch (error) {}
    }

    async fetchNumReggedWrkchains() {
        try {
            const response = await fetch(`${this.#queryNodes.fund.rest}/mainchain/wrkchain/v1/wrkchains`);
            const data = await response.json();
            if (data?.wrkchains) {
                this.#numReggedWrkchains = data.wrkchains.length
                this.#wrkchains = data.wrkchains
            }
        } catch (error) {}
    }

    async monitorUpgradeLogs() {

        if(this.#networkUpgraded) {
            return
        }

        while(!this.#networkUpgraded) {
            for (const [container, info] of Object.entries(this.#containers)) {
                if(!info.upgraded) {
                    this.#containers[container].und_version = null
                    const l = await getDockerLogs(info.container, 200)
                    const hasUpgraded = checkNodeUpgradedFromLogs(l, this.#netOverview.fund_upgrade_height)
                    if (hasUpgraded) {
                        this.#containers[container].upgraded = true
                        this.#containers[container].up_time = new Date().toLocaleTimeString("en-GB")
                        this.#numUpgraded += 1
                    } else {
                        this.#containers[container].und_version = "upgrading"
                    }
                }
            }
            this.printStats()
            this.#networkUpgradeStatus = "NETWORK UPGRADE STARTED \u{1F62C}"
            if(this.#numUpgraded >= this.#numContainers) {
                this.#networkUpgradeStatus = "UPGRADE SUCCESSFUL! \u{1F60A}"
                this.#networkUpgraded = true
            } else {
                this.#networkUpgradeStatus = "NETWORK UPGRADE IN PROGRESS \u{1F62C}"
            }
            await sleep(1000)
        }
    }

    async getIbcChannels() {

        if(!this.#fundRpcIsIUp || !this.#gaiadRpcIsIUp) {
            return
        }
        try {
            const fundResponse = await fetch(`${this.#queryNodes.fund.rest}/ibc/core/channel/v1/channels`);
            const fundData = await fundResponse.json();

            const gaiadResponse = await fetch(`${this.#queryNodes.gaiad.rest}/ibc/core/channel/v1/channels`);
            const gaiadData = await gaiadResponse.json();

            if (!fundData.channels || !gaiadData.channels) {
                return
            }

            if (fundData?.channels.length > 0) {
                this.#fundIbcChannel = fundData?.channels[0]?.channel_id;
                this.#fundIbcChannelState = fundData?.channels[0]?.state.replace("STATE_", "")
            }

            if (gaiadData?.channels.length > 0) {
                this.#gaiadIbcChannel = gaiadData?.channels[0]?.channel_id;
                this.#gaiadIbcChannelState = gaiadData?.channels[0]?.state.replace("STATE_", "")
            }

            if (this.#fundIbcChannel !== null && this.#gaiadIbcChannel !== null && this.#ibcDenom === "") {
                const trace = `transfer/${this.#gaiadIbcChannel}/nund`
                this.#ibcDenom = `ibc/${bytesToHex(sha256(trace)).toUpperCase()}`
            }
        } catch(e) {
            // probably network upgrade
        }
    }

    async getUpgradeProposalStatus() {
        try {
            const response = await fetch(`${this.#queryNodes.fund.rest}/cosmos/gov/v1beta1/proposals/1`);
            const data = await response.json();

            this.#upgradeProposalStatus = data.proposal.status.replace("PROPOSAL_STATUS_", "")
        } catch (e) {}
    }

    async getHermesStatus() {
        const hermesLogs = await getDockerLogs(this.#netOverview.hermes.docker_container, 100)
        this.#ibcHermesStatus = getHermesCreateStatus(hermesLogs)
    }

    async fetchCommunityPool() {
        try {
            const response = await fetch(`${this.#queryNodes.fund.rest}/cosmos/distribution/v1beta1/community_pool`)
            const data = await response.json();

            let amnt = 0
            let denom = ""
            if (data?.pool?.length > 0) {
                const nund = parseInt(data.pool[0].amount, 10)

                if(nund > 100000000) {
                    amnt = new Intl.NumberFormat("en-GB", {}).format(nund / 10 ** 9)
                    denom = "FUND"
                } else {
                    amnt = "< 0.01"
                }

            }
            this.#communityPool = amnt
            this.#communityPoolDenom = denom
        } catch (e) {}
    }

    async fetchBondedTokens() {
        try {
            const response = await fetch(`${this.#queryNodes.fund.rest}/cosmos/staking/v1beta1/pool`)
            const data = await response.json();

            let bondedAmnt = 0
            let notBondedAmnt = 0
            if (data?.pool?.bonded_tokens) {
                const bondedNund = parseInt(data.pool.bonded_tokens, 10)
                const notBondedNund = parseInt(data.pool.not_bonded_tokens, 10)

                if(bondedNund > 0) {
                    bondedAmnt = new Intl.NumberFormat("en-GB", {}).format(
                        Math.round(bondedNund / 10 ** 9)
                    )
                }

                if(notBondedNund > 0) {
                    notBondedAmnt = new Intl.NumberFormat("en-GB", {}).format(
                        Math.round(notBondedNund / 10 ** 9)
                    )
                }

            }
            this.#bondedTokens = bondedAmnt
            this.#notBondedTokens = notBondedAmnt
        } catch (e) {}


        //{
        //   "pool": {
        //     "not_bonded_tokens": "0",
        //     "bonded_tokens": "946677149108876"
        //   }
        // }
    }

    async fetchSigningInfos() {
        //http://localhost:1320/cosmos/slashing/v1beta1/signing_infos

        //{
        //   "info": [
        //     {
        //       "address": "undvalcons1kd58mse56fhcqys6vpwt004ule5rzw07k3t64e",
        //       "start_height": "0",
        //       "index_offset": "189",
        //       "jailed_until": "1970-01-01T00:00:00Z",
        //       "tombstoned": false,
        //       "missed_blocks_counter": "0"
        //     },
        //     {
        //       "address": "undvalcons1h5l92rp9h7tushmu58qp7wh9xqtdy2q4carppk",
        //       "start_height": "0",
        //       "index_offset": "189",
        //       "jailed_until": "1970-01-01T00:00:00Z",
        //       "tombstoned": false,
        //       "missed_blocks_counter": "0"
        //     },
        //     {
        //       "address": "undvalcons17mmltzzs6vd0uzvknamxxl5hxacn0fq525spdd",
        //       "start_height": "0",
        //       "index_offset": "189",
        //       "jailed_until": "1970-01-01T00:00:00Z",
        //       "tombstoned": false,
        //       "missed_blocks_counter": "0"
        //     }
        //   ],
        //   "pagination": {
        //     "next_key": null,
        //     "total": "3"
        //   }
        // }
    }

    async fetchPaymentStreams() {

        try {
            const response = await fetch(`${this.#queryNodes.fund.rest}/mainchain/stream/v1/streams/all`);
            const data = await response.json();

            if(data?.streams.length > 0) {
                for(let i = 0; i < data.streams.length; i++) {
                    const s = data.streams[i];
                    const pair = `${s.sender}_${s.receiver}`
                    if(!this.#streamSenderReceiverPairs.includes(pair)) {
                        this.#streamSenderReceiverPairs.push(pair)
                    }
                }
            }


        } catch (e) {}
    }

    async fetchEfundPurchaseOrders() {

        try {
            const response = await fetch(`${this.#queryNodes.fund.rest}/mainchain/enterprise/v1/pos`);
            const data = await response.json();

            this.#raisedPos = 0
            this.#acceptedPos = 0
            this.#completedPos = 0
            this.#purchaseOrders = []
            if(data?.purchase_orders.length > 0) {
                this.#purchaseOrders = data.purchase_orders
                for(let i = 0; i < data.purchase_orders.length; i++) {
                    const po = data.purchase_orders[i];
                    if(po.status === "STATUS_RAISED") {
                        this.#raisedPos += 1
                    }
                    if(po.status === "STATUS_ACCEPTED") {
                        this.#acceptedPos += 1
                    }
                    if(po.status === "STATUS_COMPLETED") {
                        this.#completedPos += 1
                    }
                }
            }


        } catch (e) {}
    }

    async getSinglePaymentStream(sender, receiver) {
        let stream = null
        try {
            const response = await fetch(`${this.#queryNodes.fund.rest}/mainchain/stream/v1/streams/receiver/${sender}/${receiver}`);
            const data = await response.json();

            if (data?.message !== undefined || data?.stream.stream === undefined) {
                return ERRS.NOT_EXIST
            }

            this.#numActiveStreams += 1
            return data.stream
        } catch(e) {
            return ERRS.NOT_EXIST
        }
    }

    async monitorPaymentStream() {
        this.#paymentStreams = []
        this.#numActiveStreams = 0
        for(let i = 0; i < this.#streamSenderReceiverPairs.length; i += 1) {
            const pair = this.#streamSenderReceiverPairs[i].split("_");
            const s = await this.getSinglePaymentStream(pair[1], pair[0])

            this.#paymentStreams.push(s)
        }

    }

    printStats() {
        console.clear()
        // console.log(`${bold("Upgrading")}      : ${this.#netOverview.genesis_version} -> ${this.#netOverview.upgrade_version}`)
        console.log(`${bold("Upgrade Plan")}   : ${this.#netOverview.genesis_version} -> ${this.#netOverview.upgrade_version} | ${this.#netOverview.fund_upgrade_plan} at Height ${this.#netOverview.fund_upgrade_height}`)
        console.log(`${bold("Upgrade Status")} : ${this.#networkUpgradeStatus} (${this.#numUpgraded} / ${this.#numContainers} upgraded) | ${bold("Proposal Status")}: ${this.#upgradeProposalStatus}`)
        console.log("")
        // console.log(`${bold("IBC Hermes")}     : ${this.#ibcHermesStatus}`)


        // console.log("")
        // console.table(this.#containers)
        this.printContainerStatusTable()
        console.log("")

        this.printOptions()

        console.log("")
        console.log("")
        const now = new Date().toLocaleTimeString("en-GB")
        console.log(`${bold("Time :")} ${now} | ${bold("Txs in block")} ${bold(this.#currentBlockHeight)} :`, this.#blockValidTxs, " | ", `${bold("Total Txs")} :`, this.#totalValidTxs, `| ${bold("Cycle")}: ${(this.#cycleDisplays) ? "on" : "off"}`)

        console.log("")
        switch(this.#displayOption) {
            case OPT_KEYS.P.key:
                this.printPaymentStreamStats()
                break
            case OPT_KEYS.E.key:
                this.printEfundStats()
                break
            case OPT_KEYS.I.key:
                this.printIbcStats()
                break
            case OPT_KEYS.B.key:
                this.printBeaconStats()
                break
            case OPT_KEYS.W.key:
                this.printWrkChainStats()
                break
            case OPT_KEYS.O.key:
            default:
                this.printOverviewStats()
                break
        }
    }

    printOptions() {
        for (const [, value] of Object.entries(OPT_KEYS)) {
            process.stdout.write(`${value.key}: ${value.opt}, `);
        }
    }

    printBeaconStats() {
        // console.log(`${bold("BEACONS")}      :`, this.#numReggedBeacons)
        console.log("-- BEACONS --")
        console.log("")

        for(let i = 0; i < this.#beacons.length; i++) {
            const b =  this.#beacons[i];
            console.log(`${bold(b.moniker)} :`, `Num Timestamps = ${b.last_timestamp_id}`)
            // console.log(b)
        }
    }

    printWrkChainStats() {
        console.log("-- WrkChains --")
        console.log("")

        for(let i = 0; i < this.#wrkchains.length; i++) {
            const w =  this.#wrkchains[i];
            console.log(`${bold(w.moniker)} :`, `Last Block = ${w.lastblock}`)
            // console.log(w)
        }
    }

    printEfundStats() {
        console.log("-- eFUND --")
        console.log("")

        console.log(`${bold("eFUND Locked")}  :`, this.#totalEfundSupply)
        console.log(`${bold("eFUND Spent")}   :`, this.#totalSpentEfund)
        console.log(`${bold("Raised POs")}    :`, this.#raisedPos)
        console.log(`${bold("Accepted POs")}  :`, this.#acceptedPos)
        console.log(`${bold("Completed POs")} :`, this.#completedPos)
    }

    printIbcStats() {
        console.log("-- IBC --")
        console.log("")

        const fundIbcStatusOut = (this.#fundIbcChannelState === "UNRECOGNIZED") ? "" : `(${this.#fundIbcChannelState})`
        const gaiadIbcStatusOut = (this.#gaiadIbcChannelState === "UNRECOGNIZED") ? "" : `(${this.#gaiadIbcChannelState})`
        console.log(`${bold("Hermes Status")}   :`, this.#ibcHermesStatus)
        console.log(`${bold("FUND Channel")}    :`, this.#fundIbcChannel, fundIbcStatusOut)
        console.log(`${bold("Gaiad Channel")}   :`, this.#gaiadIbcChannel, gaiadIbcStatusOut)
        console.log(`${bold("IBC Denom")}       : ${this.#ibcDenom}`)
        // use process.stdout on last line to prevent newline
        process.stdout.write(`${bold("Supply on Gaiad")} : ${this.#totalFundDecOnIbcChain} FUND`);
    }

    printOverviewStats() {

        console.log("-- Overview --")
        console.log("")
        console.log(`${bold("Num. Stuffs")} :`, `${bold("BEACONS")} =`, this.#numReggedBeacons, `| ${bold("WrkChains")} =`, this.#numReggedWrkchains, `| ${bold("Active Streams")} =`, this.#numActiveStreams)

        console.log(`${bold("eFUND")}       :`, `${bold("Locked")} =`, this.#totalEfundSupply, `| ${bold("Spent")} =`, this.#totalSpentEfund, `| ${bold("Num POs")} =`, this.#purchaseOrders.length)
        console.log(`${bold("FUND Supply")} :`, this.#totalFundSupply, `| ${bold("FUND on IBC")} = ${this.#totalFundOnIbcChain}`)
        const fundIbcStatusOut = (this.#fundIbcChannelState === "UNRECOGNIZED") ? "" : `(${this.#fundIbcChannelState})`
        const gaiadIbcStatusOut = (this.#gaiadIbcChannelState === "UNRECOGNIZED") ? "" : `(${this.#gaiadIbcChannelState})`
        console.log(`${bold("IBC")}         : ${bold("Hermes")} = ${this.#ibcHermesStatus} | ${bold("FUND")} = ${this.#fundIbcChannel} ${fundIbcStatusOut} | ${bold("gaiad")} = ${this.#gaiadIbcChannel} ${gaiadIbcStatusOut}`)
        // console.log(`${bold("IBC Denom")}    : ${this.#ibcDenom}`)
        // use process.stdout on last line to prevent newline
        process.stdout.write(`${bold("Staking")}     : ${bold("Bonded")} = ${this.#bondedTokens} | ${bold("Unbonding")} = ${this.#notBondedTokens} | ${bold("Community Pool")} = ${this.#communityPool}`);
    }

    printPaymentStreamStats() {
        console.log("-- Payment Streams --")
        console.log("")
        // console.log(`${bold("Payment Stream #1")} :`, this.#paymentStream)
        for(let i = 0; i < this.#paymentStreams.length; i++) {
            const stream = this.#paymentStreams[i]
            const last = (i + 1 === this.#paymentStreams.length)
            this.printPaymentStream(stream, last, i + 1)
        }
    }

    printPaymentStream(stream, last = false, num) {

        let s
        let prefix = `${bold(`Stream #${num}`)} : `

        if(stream === ERRS.NOT_EXIST) {
            s = "Cancelled"
        } else {
            const deposit = Intl.NumberFormat("en-GB", {}).format(
                stream.stream.deposit.amount / (10 ** 9)
            )
            const flowRate = stream.stream.flow_rate
            const lastClaim = new Date(stream.stream.last_outflow_time).toLocaleTimeString("en-GB")
            const depositZeroTime = new Date(stream.stream.deposit_zero_time).toLocaleTimeString("en-GB")

            s = `Deposit=${deposit}, Flow=${flowRate}nund/s, Zero=${depositZeroTime}, Last claim=${lastClaim}`
        }

        if(!last) {
            console.log(`${prefix}${s}`)
        } else {
            process.stdout.write(`${prefix}${s}`);
        }
    }

    printContainerStatusTable() {
        const p = new Table({
            columns: [
                { name: 'node', alignment: 'left', title: "Node" }, // with alignment and color
                { name: 'container', alignment: 'left', title: "Docker Container" },
                { name: 'height', alignment: 'center', title: "Height" },
                { name: 'upgraded', alignment: 'center', title: "Upgraded" },
                { name: 'up_time', alignment: 'center', title: "Upgrade Time" },
                { name: 'und_version', alignment: 'center', title: "und Version" },
            ],
            charLength: { "\u{274C}": 2, "\u{2705}": 2 },
        })

        for (const [nodeName, info] of Object.entries(this.#containers)) {
            p.addRow({
                node: nodeName,
                container: info.container,
                height: info.height,
                upgraded: (info.upgraded ? "\u{2705}" : "\u{274C}"),
                up_time: info.up_time,
                und_version: info.und_version,
            });
        }

        p.printTable()
    }

    printWaitForDocker() {
        console.clear()
        console.log("waiting for docker up")
        console.log(`Up: ${this.#numContainersUp} / ${this.#numContainers}`)
    }

    printWaitForRpc() {
        console.clear()
        console.log("waiting for FUND RPC up")
    }
}
