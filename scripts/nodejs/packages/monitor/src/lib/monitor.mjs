import ReconnectingWebSocket from 'reconnecting-websocket'
import WS from 'ws';
import readline from 'node:readline';
import cliCursor from 'cli-cursor';
import {portIsOpen, sleep} from "@simulator/shared";
import {dockerComposeIsUp, getDockerLogs, getTotalTxData} from "./docker.mjs";
import {getNetworkInfo} from "./utils.mjs";
import {Display} from "./display.mjs";
import {NodeTracker} from "./nodes.mjs";
import * as queries from "./queries.mjs";
import {render, renderWaitForDocker, renderWaitForRpc} from "./render.mjs";

// Watches a running simulator network through its upgrade: waits for the containers and RPCs, follows each block over
// the FUND RPC's websocket, and redraws every second from REST queries and container logs.
export class UpgradeMonitor {

    #overview
    #query // each chain's first RPC node: {rpc, ws, grpc, rest, rpc_port, container}
    #nodes
    #display = new Display()
    #ws = null
    #upgradeHeight
    #fundRpcUp = false
    #gaiadRpcUp = false

    // what the screen shows besides the node table and the upgrade's progress
    #state = {
        proposalStatus: "Not Submitted",
        currentBlockHeight: 0,
        blockValidTxs: 0,
        totalValidTxs: 0,
        fundSupply: 0,
        fundOnIbc: 0,
        fundDecOnIbc: 0,
        efundLocked: 0,
        efundSpent: 0,
        bondedTokens: 0,
        notBondedTokens: 0,
        communityPool: 0,
        purchaseOrders: [],
        raisedPos: 0,
        acceptedPos: 0,
        completedPos: 0,
        fundIbcChannel: null,
        fundIbcChannelState: "UNRECOGNIZED",
        gaiadIbcChannel: null,
        gaiadIbcChannelState: "UNRECOGNIZED",
        ibcDenom: "",
        hermesStatus: "",
        streamPairs: [],
        paymentStreams: [],
        numActiveStreams: 0,
        numBeacons: 0,
        beacons: [],
        numWrkchains: 0,
        wrkchains: [],
    }

    constructor(netOverview) {
        this.#overview = netOverview
        const [rows, query] = getNetworkInfo(netOverview)
        this.#query = query
        this.#upgradeHeight = parseInt(netOverview.fund_upgrade_height, 10)
        this.#nodes = new NodeTracker(rows, this.#upgradeHeight)
    }

    #redraw() {
        render(this.#overview, this.#nodes, this.#state, this.#display)
    }

    async #checkRpcs() {
        this.#fundRpcUp = await portIsOpen(this.#query.fund.rpc_port)
        this.#gaiadRpcUp = await portIsOpen(this.#query.gaiad.rpc_port)
    }

    async run() {
        readline.emitKeypressEvents(process.stdin);
        if (process.stdin.isTTY) {
            process.stdin.setRawMode(true);
        }
        process.stdin.on('keypress', (chunk, key) => {
            if (key && this.#display.press(key.name)) {
                this.#redraw()
            }
        });
        cliCursor.hide()

        let up = 0
        while (up !== this.#nodes.count) {
            renderWaitForDocker(up, this.#nodes.count)
            up = await dockerComposeIsUp(this.#overview.fund_container_prefix)
            await sleep(500)
        }
        while (!this.#fundRpcUp || !this.#gaiadRpcUp) {
            renderWaitForRpc()
            await this.#checkRpcs()
            await sleep(500)
        }

        const [totalValidTxs] = getTotalTxData(await getDockerLogs(this.#query.fund.container, "all"))
        this.#state.totalValidTxs = totalValidTxs

        console.log(`Connect to WS ${this.#query.fund.ws}`)
        this.#ws = new ReconnectingWebSocket(this.#query.fund.ws, [], {WebSocket: WS, connectionTimeout: 1000, maxRetries: 100});
        this.#ws.addEventListener('open', () => this.#onOpen())
        this.#ws.addEventListener('message', (msg) => this.#onBlock(msg))

        // a failed refresh (e.g. a container being removed under it by `make down`) skips one update rather than
        // crashing the monitor with an unhandled rejection
        setInterval(async () => {
            try {
                await this.#refresh()
            } catch (e) {}
        }, 1000);
        setInterval(() => this.#display.advance(), 5000)
    }

    #onOpen() {
        console.log("subscribe to NewBlock")
        this.#ws.send(JSON.stringify({"jsonrpc": "2.0", "method": "subscribe", "params": ["tm.event='NewBlock'"], "id": 1}))
        this.#redraw()
    }

    // Counts the new block's txs from the FUND RPC node's log, and on the block before the upgrade starts watching the
    // nodes upgrade.
    async #onBlock(msg) {
        const block = JSON.parse(msg.data)?.result?.data?.value?.block
        if (!block) {
            return
        }
        const s = this.#state
        s.currentBlockHeight = parseInt(block.header.height, 10)
        const logs = await getDockerLogs(this.#query.fund.container, 400)
        const [blockValidTxs] = getTotalTxData(logs, s.currentBlockHeight >= this.#upgradeHeight, s.currentBlockHeight)
        s.totalValidTxs += blockValidTxs
        s.blockValidTxs = blockValidTxs

        if (s.currentBlockHeight === this.#upgradeHeight - 1) {
            await this.#nodes.watchUpgrade(() => this.#redraw())
        }
    }

    async #refresh() {
        const s = this.#state
        const {fund, gaiad} = this.#query
        Object.assign(s, await queries.hermesStatus(this.#overview.hermes.docker_container))
        Object.assign(s, await queries.fundSupply(fund))
        if (this.#fundRpcUp && this.#gaiadRpcUp) {
            Object.assign(s, await queries.ibcChannels(fund, gaiad, s))
        }
        if (this.#gaiadRpcUp && s.ibcDenom !== "") {
            Object.assign(s, await queries.fundOnIbc(gaiad, s.ibcDenom))
        }
        await this.#checkRpcs()
        await this.#nodes.refresh(s.currentBlockHeight)
        for (const query of [queries.proposalStatus, queries.beacons, queries.wrkchains, queries.purchaseOrders,
            queries.efundLocked, queries.efundSpent, queries.communityPool, queries.stakingPool]) {
            Object.assign(s, await query(fund))
        }
        Object.assign(s, await queries.paymentStreams(fund, s.streamPairs))
        this.#redraw()
    }
}
