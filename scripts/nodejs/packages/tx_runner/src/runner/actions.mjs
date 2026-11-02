import {loadCustomTxs, sleep} from "@simulator/shared";
import {Logger} from "../libs/logger.mjs";
import {getRandomWallet, getRandomWalletNotThis} from "../libs/wallet_utils.mjs";
import {TxFactory} from "../tx/tx_factory.mjs";
import {Bank} from "../modules/bank.mjs";
import {Beacon} from "../modules/beacon.mjs";
import {Enterprise} from "../modules/enterprise.mjs";
import {Gov} from "../modules/gov.mjs";
import {IBC} from "../modules/ibc.mjs";
import {Module} from "../modules/module.mjs";
import {Stake} from "../modules/stake.mjs";
import {PaymentStream} from "../modules/stream.mjs";
import {WrkChain} from "../modules/wrkchain.mjs";

const NAMES = {fund: "FUND", gaiad: "Gaiad"}

// What the runner does on each new block of each chain: settle the last block's txs, then send the next round.
export class BlockActions {

    #config // the Configuration; #config.config is the plain config
    #wallets
    #clients
    #upgradeHeight
    #height = 0
    #proposalSubmitted = false
    #ibcOpen = false
    #ibcDenom = ""
    #customTxs = loadCustomTxs()
    #customDone = {gov: new Set(), msgs: new Set()} // indexes of the custom txs sent

    constructor(config, wallets, clients, upgradeHeight) {
        this.#config = config
        this.#wallets = wallets
        this.#clients = clients
        this.#upgradeHeight = upgradeHeight
    }

    async onFundBlock(block) {
        Logger.info("=== START FUND BLOCK ACTIONS ===")
        this.#height = parseInt(block.header.height, 10)
        Logger.info("FUND BLOCK HEIGHT", this.#height)
        // Message shapes follow the binary that will execute them. A tx sent now lands in the next block at the
        // earliest, and the upgrade height is the first block the new binary runs - so switch one block early, or txs
        // sent while the chain halts at the upgrade carry the old shape into the new binary.
        const nextBlockUpgraded = this.#upgradeHeight > 0 && this.#height + 1 >= this.#upgradeHeight
        // x/stream became multi-denom in vaxildan: the denom is only a valid message field post-upgrade.
        PaymentStream.setStreamDenom(nextBlockUpgraded, this.#height)
        // BEACON timestamps gain an optional `metadata` field in vaxildan (#129).
        Beacon.setBeaconMetadata(nextBlockUpgraded, this.#height)
        await this.#checkTxs("fund")
        await this.#checkIbcChannels()

        await sleep(1000)
        // custom txs before any wallet acts this block: a CLI tx is signed with the account's committed sequence, which
        // a tx still in the mempool would make stale
        await this.#customGovTxs()
        await this.#customMsgTxs()
        await this.#validatorActions()

        if (this.#height > 4) {
            await this.#eFundActions()
            await this.#beaconActions()
            await this.#wrkChainActions()
            await this.#testTxs()
            await this.#ibcTransfers("fund", "gaiad")
            await this.#paymentStreamTxs()
        }

        this.#moveSentToPending("fund")
        Logger.info("=== END FUND BLOCK ACTIONS ===")
    }

    async onGaiadBlock() {
        Logger.info("=== START GAIAD BLOCK ACTIONS ===")
        await this.#checkIbcChannels()
        await this.#checkTxs("gaiad")
        await this.#ibcTransfers("gaiad", "fund")
        this.#moveSentToPending("gaiad")
        Logger.info("=== END GAIAD BLOCK ACTIONS ===")
    }

    // results of the txs sent last block, which free each wallet's queue for the next
    async #checkTxs(network) {
        Logger.info("RUN", `net=${network}`, "Process previous Tx results")
        for (const wallet of this.#wallets.all(network)) {
            await TxFactory.checkWalletTxs(wallet, this.#clients.pick(network, "cosmos"))
        }
    }

    #moveSentToPending(network) {
        Logger.info("RUN", `net=${network}`, "move sent txs to pending txs")
        for (const wallet of this.#wallets.all(network)) {
            TxFactory.moveSentToPending(wallet)
        }
    }

    // the upgrade proposal once, then the validators' votes
    async #validatorActions() {
        Logger.info("RUN", "validator actions")
        const validators = this.#wallets.byType("fund", "validator")
        if (!this.#proposalSubmitted) {
            await Gov.submitUpgradeProposal(getRandomWallet(validators), this.#config.config)
            this.#proposalSubmitted = true
        } else {
            await Gov.validatorSubmitOrVote(this.#clients.pick("fund", "cosmos"), validators, this.#customTxs.gov)
        }
    }

    // config.json's custom txs of one kind that are due: not yet sent, and their height reached
    #dueCustomTxs(kind) {
        return [...this.#customTxs[kind].entries()]
            .filter(([i, tx]) => !this.#customDone[kind].has(i) && this.#height >= tx.submit_height)
    }

    // config.json's gov proposals, each submitted by a random validator; one that fails to broadcast is tried again
    // next block
    async #customGovTxs() {
        for (const [i, tx] of this.#dueCustomTxs("gov")) {
            const validator = getRandomWallet(this.#wallets.byType("fund", "validator"))
            if (await Gov.submitProposal(this.#config.config, validator, JSON.stringify(tx.proposal), `custom proposal "${tx.proposal.title}"`)) {
                this.#customDone.gov.add(i)
            }
        }
    }

    // config.json's msg txs, each signed by its wallet. Tried again next block only if it never reached the chain - the
    // script failed, or a stale sequence was rejected (code 32); any other rejection is final, for make verify to judge.
    async #customMsgTxs() {
        for (const [i, tx] of this.#dueCustomTxs("msgs")) {
            const res = await TxFactory.sendUnsignedTx(this.#config.config, this.#wallets.byName("fund", tx.from),
                JSON.stringify(tx.tx), `${tx.from} ${tx.tx.body.memo}`)
            if (res !== null && res.code !== 32) {
                this.#customDone.msgs.add(i)
            }
        }
    }

    async #eFundActions() {
        await Enterprise.runActions(this.#clients.pick("fund", "mainchain"), this.#wallets.byType("fund", "enterprise"),
            this.#wallets.byType("fund", "beacon", "wrkchain"), this.#height)
    }

    async #beaconActions() {
        Logger.info("RUN", "beacon actions")
        await Beacon.runActions(this.#clients.pick("fund", "mainchain"), this.#wallets.byType("fund", "beacon"))
    }

    async #wrkChainActions() {
        Logger.info("RUN", "wrkchain actions")
        await WrkChain.runActions(this.#clients.pick("fund", "mainchain"), this.#wallets.byType("fund", "wrkchain"),
            this.#height, this.#upgradeHeight, this.#config.config)
    }

    // one random bank, staking or gov tx per idle test wallet; gov only while a proposal is open
    async #testTxs() {
        const wallets = this.#wallets.byType("fund", "test")
        const validators = this.#wallets.byType("fund", "validator")
        const cosmosClient = this.#clients.pick("fund", "cosmos")
        const openProposals = await Gov.getOpenProposals(cosmosClient)

        Logger.info("RUN", "send random test cosmos txs")

        for (let i = 0; i < wallets.length; i++) {
            const wallet = wallets[i]
            if (wallet.pendingTxs.length > 0) {
                continue
            }
            switch (Module.randomModule(openProposals?.proposals.length > 0)) {
                case Module.MsgModules.BANK:
                    await Bank.sendRandomMsg(cosmosClient, wallet, getRandomWalletNotThis(wallets, i))
                    break
                case Module.MsgModules.STAKE:
                    await Stake.sendRandomMsg(cosmosClient, wallet, getRandomWallet(validators))
                    break
                case Module.MsgModules.GOV:
                    await Gov.sendRandomMsg(wallet, openProposals?.proposals[0])
                    break
            }
        }
    }

    async #checkIbcChannels() {
        if (this.#ibcOpen) {
            return
        }
        const {open: fundOpen} = await IBC.checkIbcChannel(this.#clients.pick("fund", "ibc"), "fund")
        const {open: gaiadOpen, denom} = await IBC.checkIbcChannel(this.#clients.pick("gaiad", "ibc"), "gaiad")
        if (fundOpen && gaiadOpen) {
            this.#ibcOpen = true
            this.#ibcDenom = denom
        }
    }

    // IBC transfers one way over channel-0: FUND -> Gaia sends a sliver of nund, Gaia -> FUND sends most of it back.
    async #ibcTransfers(from, to) {
        Logger.info("RUN", `send ${NAMES[from]} -> ${NAMES[to]} IBC txs`)
        if (!this.#ibcOpen) {
            Logger.info("WAIT", "waiting for IBC channels to open")
            return
        }
        const [fromDenom, toDenom, minFraction, maxFraction] = from === "fund"
            ? ["nund", this.#ibcDenom, 0.001, 0.002]
            : [this.#ibcDenom, "nund", 0.90, 0.99]
        const timeoutHeight = await IBC.calculateIbcTimeoutHeight(this.#config.randomRpc(from), "transfer", "channel-0")
        await IBC.runIbcTransfers(this.#clients.pick(from, "ibc"), this.#clients.pick(to, "ibc"),
            this.#wallets.byType(from, "ibc"), this.#wallets.byType(to, "ibc"), timeoutHeight, fromDenom, toDenom,
            minFraction, maxFraction)
    }

    async #paymentStreamTxs() {
        Logger.info("RUN", "payment stream txs")
        await PaymentStream.runStreamTxs(this.#clients.pick("fund", "mainchain"),
            this.#wallets.byType("fund", "stream_sender"), this.#wallets.byType("fund", "stream_receiver"))
    }
}
