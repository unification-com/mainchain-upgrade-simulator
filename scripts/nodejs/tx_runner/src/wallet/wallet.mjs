import {
    cosmosAminoConverters,
    cosmosProtoRegistry,
    ibcAminoConverters,
    ibcProtoRegistry,
    mainchainAminoConverters,
    mainchainProtoRegistry
} from '@unification-com/fundjs';
import {Registry} from "@cosmjs/proto-signing";
import { AminoTypes, SigningStargateClient, GasPrice } from "@cosmjs/stargate";

import {getOfflineSignerProtoAccNum} from '../libs/signer.mjs';

const registries = {
    fund: new Registry([
        ...cosmosProtoRegistry,
        ...ibcProtoRegistry,
        ...mainchainProtoRegistry,
    ]),
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
