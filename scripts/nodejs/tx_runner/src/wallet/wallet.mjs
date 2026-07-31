import {
    cosmosAminoConverters,
    cosmosProtoRegistry,
    ibcAminoConverters,
    ibcProtoRegistry,
    mainchainAminoConverters,
    mainchainProtoRegistry
} from '@unification-com/fundjs';
import {mainchain as mainchainV2} from 'fundjs2';
import {Registry} from "@cosmjs/proto-signing";
import { AminoTypes, SigningStargateClient, GasPrice } from "@cosmjs/stargate";

import {getOfflineSignerProtoAccNum} from '../libs/signer.mjs';

// Types that gained a field in vaxildan. Composing these with fundjs 0.2.1 is NOT enough: cosmjs
// serialises via the Registry codec for the typeUrl, so a 0.1.0 codec silently drops the new field
// (the denom arrives as "" and x/stream rejects it at ValidateBasic). Override the codecs too.
const vaxildanTypeOverrides = [
    ["/mainchain.stream.v1.MsgClaimStream", mainchainV2.stream.v1.MsgClaimStream],
    ["/mainchain.stream.v1.MsgCancelStream", mainchainV2.stream.v1.MsgCancelStream],
    ["/mainchain.stream.v1.MsgUpdateFlowRate", mainchainV2.stream.v1.MsgUpdateFlowRate],
    ["/mainchain.beacon.v1.MsgRecordBeaconTimestamp", mainchainV2.beacon.v1.MsgRecordBeaconTimestamp],
]

const fundRegistry = new Registry([
    ...cosmosProtoRegistry,
    ...ibcProtoRegistry,
    ...mainchainProtoRegistry,
])
for (const [typeUrl, type] of vaxildanTypeOverrides) {
    fundRegistry.register(typeUrl, type)
}

const registries = {
    fund: fundRegistry,
    gaiad: new Registry([
        ...cosmosProtoRegistry,
        ...ibcProtoRegistry,
    ])
}

const aminoTypes = {
    fund: new AminoTypes({
        ...cosmosAminoConverters,
        ...ibcAminoConverters,
        ...mainchainAminoConverters,
    }),
    gaiad: new AminoTypes({
        ...cosmosAminoConverters,
        ...ibcAminoConverters,
    }),
}

export const EFUND_ACTION_STEP = {
    NOT_WHITELISTED: 0,
    WHITELIST_TX_SENT: 1,
    WHITELISTED: 2,
    PO_TX_SENT: 3,
    PO_PROCESSING: 4,
    PO_COMPLETE: 5,
}

export class Wallet {

    #signer = null
    #signingClient = null
    #meta = {}
    #gasPrice = null
    #gasMultiplier = 1.7

    // Locally tracked signing data.
    //
    // Txs are broadcast with broadcastTxSync (fire-and-forget), so a tx sits in the mempool without
    // the committed account sequence advancing. cosmjs re-reads the sequence from committed state on
    // every sign, so a second tx from the same wallet in the same block window gets the SAME sequence
    // and is rejected with "account sequence mismatch ... expected N+1, got N" — always short by
    // exactly one. Tracking the sequence here and passing it explicitly to sign() removes the race;
    // resyncSignerData() re-reads from chain whenever a tx errors, so we self-heal.
    #accountNumber = null
    #sequence = null
    #chainId = null
    #seqInit = null

    // tx queues
    #sentTxs = []
    #pendingTxs = []
    #txResults = []

    // eFUND specific
    #eFundActionFromBlock = 0
    #eFundStatus = EFUND_ACTION_STEP.NOT_WHITELISTED
    #eFundPoId = 0

    // BEACON/WrkChain
    #beaconOrWrkChainRegTxSent = false
    #beaconOrWrkChainId = 0

    // Staking
    #hasBondedTokens = false

    // governance
    #lastProposalVotedId = 0

    constructor(signer, signingClient, meta) {
        this.#signer = signer
        this.#signingClient = signingClient
        this.#meta = meta
        this.#gasPrice = Wallet.getGasPriceForNetwork(meta.network.name)
    }

    static async createWallet(config, network, walletJson) {
        const networkConfig = config.config.networks[network]
        const rpc = config.randomRpc(network)

        const meta = {
            network: networkConfig,
            wallet_json: walletJson,
            selected_rpc: rpc.name,
        }

        let gasPrice = null
        switch (network) {
            case "fund":
                gasPrice = GasPrice.fromString("25.0nund")
                break
            case "gaiad":
                gasPrice = GasPrice.fromString("0stake")
                break
        }

        const signer = await getOfflineSignerProtoAccNum({
            mnemonic: walletJson.mnemonic,
            chain: {
                bech32_prefix: walletJson.bech32_prefix,
                slip44: walletJson.slip44,
            },
        })

        const signingClient = await SigningStargateClient.connectWithSigner(rpc.rpc, signer, {
            registry: registries[networkConfig.name],
            aminoTypes: aminoTypes[networkConfig.name],
            gasPrice,
        })

        return new Wallet(signer, signingClient, meta)
    }

    static getGasPriceForNetwork(network) {
        switch (network) {
            case "fund":
                return GasPrice.fromString("25.0nund")
            case "gaiad":
                return GasPrice.fromString("1stake")
        }
    }

    setGasMultiplier(gasMultiplier) {
        this.#gasMultiplier = gasMultiplier
    }

    // Signing data for the next tx, seeded from chain on first use then tracked locally.
    //
    // The sequence is RESERVED synchronously here rather than incremented after the broadcast:
    // sendTx awaits between signing and broadcasting, so two concurrent txs for the same wallet
    // would otherwise both read the same value before either advanced it — the same race, just
    // moved. Handing out N and immediately bumping to N+1 in one synchronous step makes each
    // caller's sequence unique. #seqInit serialises the initial chain read for the same reason.
    async signerData() {
        if (this.#sequence === null) {
            if (this.#seqInit === null) {
                this.#seqInit = this.resyncSignerData().finally(() => { this.#seqInit = null })
            }
            await this.#seqInit
        }
        const data = {
            accountNumber: this.#accountNumber,
            sequence: this.#sequence,
            chainId: this.#chainId,
        }
        this.#sequence += 1
        return data
    }

    // Re-read account number/sequence from the chain. Called on first use and after any tx error,
    // so a genuine mismatch (or a tx that never landed) corrects itself on the next attempt.
    async resyncSignerData() {
        const addr = this.#meta.wallet_json.address_bech32
        const {accountNumber, sequence} = await this.#signingClient.getSequence(addr)
        this.#accountNumber = accountNumber
        this.#sequence = sequence
        if (this.#chainId === null) {
            this.#chainId = await this.#signingClient.getChainId()
        }
    }

    // No-op: the sequence is now reserved in signerData() at hand-out time. Kept so callers that
    // still invoke it stay harmless.
    incrementSequence() {}

    // Return a reserved sequence after a broadcast that never entered the mempool (CheckTx
    // rejection). Only rolls back if nothing else has been reserved since, otherwise a gap would be
    // punched in the middle of a batch of in-flight txs. Do NOT re-read from chain here: committed
    // state lags behind anything still sitting in the mempool, so resyncing mid-flight resets the
    // counter backwards and turns one failure into a cascade of mismatches.
    releaseSequence(seq) {
        if (this.#sequence !== null && this.#sequence === seq + 1) {
            this.#sequence = seq
        }
    }

    calculateFee(gas) {
        const gasMul = Math.round(gas * this.#gasMultiplier)
        const feeAmnt = this.#gasPrice.amount.multiply(gasMul)

        return {
            amount: [
                {
                    denom: this.#gasPrice.denom,
                    amount: feeAmnt.toString()
                }
            ],
            gas: gasMul.toString()
        };
    }

    addSentTx(txHash) {
        this.#sentTxs.push(txHash)
    }

    addPendingTx(txHash) {
        this.#pendingTxs.push(txHash)
    }

    addTxResult(result) {
        this.#txResults.push(result)
    }

    removeSentTx(i) {
        this.#sentTxs.splice(i, 1)
    }

    removePendingTx(i) {
        this.#pendingTxs.splice(i, 1)
    }

    removeTxResult(i) {
        this.#txResults.splice(i, 1)
    }

    async getAccount(idx = 0) {
        const accounts = await this.signer.getAccounts()

        return accounts[idx]
    }

    setEFundActionFromBlock(eFundActionFromBlock) {
        this.#eFundActionFromBlock = eFundActionFromBlock
    }

    setEFundStatus(status) {
        this.#eFundStatus = status
    }

    setEfundPoId(poId) {
        this.#eFundPoId = poId
    }

    setBeaconOrWrkChainId(beaconOrWrkChainId) {
        this.#beaconOrWrkChainId = beaconOrWrkChainId
    }

    setBeaconOrWrkChainRegTxSent(beaconOrWrkChainRegTxSent) {
        this.#beaconOrWrkChainRegTxSent = beaconOrWrkChainRegTxSent
    }

    setHasBondedTokens(hasBondedTokens) {
        this.#hasBondedTokens = hasBondedTokens
    }

    setLastProposalVotedId(lastProposalVotedId) {
        this.#lastProposalVotedId = lastProposalVotedId
    }

    get eFundActionFromBlock() {
        return this.#eFundActionFromBlock
    }

    get eFundStatus() {
        return this.#eFundStatus
    }

    get eFundPoId() {
        return this.#eFundPoId
    }

    get beaconOrWrkChainId() {
        return this.#beaconOrWrkChainId
    }

    get beaconOrWrkChainRegTxSent() {
        return this.#beaconOrWrkChainRegTxSent
    }

    get hasBondedTokens() {
        return this.#hasBondedTokens
    }

    get sentTxs() {
        return this.#sentTxs
    }

    get pendingTxs() {
        return this.#pendingTxs
    }

    get txResults() {
        return this.#txResults
    }

    get signer() {
        return this.#signer;
    }

    get signingClient() {
        return this.#signingClient;
    }

    get meta() {
        return this.#meta;
    }

    get lastProposalVotedId() {
        return this.#lastProposalVotedId
    }
}
