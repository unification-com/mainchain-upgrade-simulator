import {Enterprise} from "./enterprise.mjs";
import {Module} from "./module.mjs";
import {Logger} from "../libs/logger.mjs";
import { TxFactory} from "../tx/tx_factory.mjs";
import {createTmpLocalWallet, deleteTmpLocalWallets} from "../libs/wallet_utils.mjs";
import {execa} from "execa";
import {bytesToHex} from "@noble/hashes/utils";
import {sha256} from "@cosmjs/crypto";
import {EFUND_ACTION_STEP} from "../wallet/wallet.mjs";
import {mainchain} from "@unification-com/fundjs";
const { createHmac } = await import('node:crypto');
const {registerWrkChain, recordWrkChainBlock} = mainchain.wrkchain.v1.MessageComposer.withTypeUrl;

export class WrkChain {
    constructor () {}

    static MsgTypes = {
        WRKCHAIN_REGISTER: "wrkchain_register",
        WRKCHAIN_RECORD: "wrkchain_record",
    }

    static getMsg(msgType, params) {
        switch (msgType) {
            default:
                return null
            case WrkChain.MsgTypes.WRKCHAIN_REGISTER:
                return WrkChain.msgRegisterWrkchain(params)
            case WrkChain.MsgTypes.WRKCHAIN_RECORD:
                return WrkChain.msgRecordWrkchainBlock(params)
        }
    }

    static msgRegisterWrkchain(params) {

        const hash = createHmac('sha256', params.wallet.meta.wallet_json.account)
            .update(`${params.wallet.meta.wallet_json.address_bech32} 1 ${new Date()}`)
            .digest('hex')
            .toUpperCase();

        const msg = registerWrkChain({
            moniker: params.wallet.meta.wallet_json.account,
            name: params.wallet.meta.wallet_json.account,
            genesisHash: hash,
            baseType: "cosmos",
            owner: params.wallet.meta.wallet_json.address_bech32,
        })

        const memo = `${params.wallet.meta.wallet_json.account} register WrkChain`

        return {msg, memo}
    }

    static msgRecordWrkchainBlock(params) {

        const hash = createHmac('sha256', params.wallet.meta.wallet_json.account)
            .update(`${params.wallet.meta.wallet_json.address_bech32} ${params.height} ${new Date()}`)
            .digest('hex')
            .toUpperCase();

        const msg = recordWrkChainBlock({
            wrkchainId: params.wrkchainId,
            height: params.height,
            blockHash: hash,
            owner: params.wallet.meta.wallet_json.address_bech32,
        })

        const memo = `${params.wallet.meta.wallet_json.account} record`

        return {msg, memo}
    }

    static async runActions(queryClient, wallets, currentHeight, upgradeHeight, config) {
        const regFee = await WrkChain.getFee(queryClient, "register")
        const recordFee = await WrkChain.getFee(queryClient, "record")

        for(let i = 0; i < wallets.length; i++) {
            const wallet = wallets[i]
            if(!wallet.beaconOrWrkChainRegTxSent && wallet.eFundStatus === EFUND_ACTION_STEP.PO_COMPLETE) {
                // register
                if(currentHeight < upgradeHeight) {
                    await WrkChain.register(queryClient, wallet, regFee)
                } else {
                    await WrkChain.registerUsingUndBinary(wallet, config)
                }
                continue
            }

            if(wallet.beaconOrWrkChainRegTxSent && wallet.beaconOrWrkChainId === 0) {
                // get ID
                await WrkChain.getAndSetIdForWallet(queryClient, wallet)
                continue
            }

            if(wallet.beaconOrWrkChainId > 0) {
                // record
                await WrkChain.recordBlock(queryClient, wallet, (currentHeight + 1), recordFee)
            }
        }
    }

    static async register(queryClient, wallet, fee) {
        Logger.info("RUN", "register wrkchain")

        if(wallet.pendingTxs.length > 0) {
            return
        }
        const canRegister = await WrkChain.canRegister(queryClient, wallet.meta.wallet_json.address_bech32)

        if(!canRegister) {
            Logger.info("WAIT", `${wallet.meta.wallet_json.account} cannot register yet`)
            return
        }

        const {msg, memo} = WrkChain.getMsg(WrkChain.MsgTypes.WRKCHAIN_REGISTER, {wallet})

        await TxFactory.sendTx(wallet, [msg], memo, fee)
        wallet.setBeaconOrWrkChainRegTxSent(true)
    }

    static async registerUsingUndBinary(wallet, config){
        const memo = `${wallet.meta.wallet_json.account} register WrkChain using und binary`
        await createTmpLocalWallet(wallet, config.dirs.wallets.tmp)

        Logger.info("RUN", "register wrkchain using binary")

        const undBin = `${config.dirs.thirdPartyBin}/und_scanlan`

        const genesisHash = bytesToHex(sha256(`${wallet.meta.wallet_json.address_bech32} 1 ${new Date()}`)).toUpperCase()

        const {stdout} = await execa`${undBin} tx wrkchain register --moniker ${wallet.meta.wallet_json.account} --genesis ${genesisHash} --name ${wallet.meta.wallet_json.account} --base cosmos --note "${memo}" --from ${wallet.meta.wallet_json.account} --node ${config.networks.fund.rpcs[0].rpc} --output json --gas auto --gas-adjustment 1.5 --chain-id ${config.networks.fund.chain_id} --keyring-backend test --yes --home ${config.dirs.wallets.tmp}`;

        const res = JSON.parse(stdout);

        if(res.code === 0) {
            Logger.info(
                "SEND_TX_BINARY",
                `net=${wallet.meta.network.name}`,
                `msg=/mainchain.wrkchain.v1.MsgRegisterWrkChain`,
                `txHash=${TxFactory.trimTxHash(res.txhash)}`,
                `"${memo}"`
            )
            wallet.addSentTx(res.txhash)
        } else {
            Logger.error("SEND_TX_BINARY", "Submit register wrkchain failed:", res.raw_log)
        }

        await deleteTmpLocalWallets(config.dirs.wallets.tmp)
        wallet.setBeaconOrWrkChainRegTxSent(true)
    }

    static async recordBlock(queryClient, wallet, height, fee) {
        const wrkchainId = wallet.beaconOrWrkChainId
        if(wrkchainId === null || wrkchainId === 0) {
            Logger.info("WAIT", `${wallet.meta.wallet_json.account} wrkchain not registered yet`)
            return
        }

        const {msg, memo} = WrkChain.getMsg(WrkChain.MsgTypes.WRKCHAIN_RECORD, {
            wallet,
            wrkchainId,
            height,
        })

        await TxFactory.sendTx(wallet, [msg], memo, fee)
    }

    static async canRegister(queryClient, address) {
        const eFund = await Enterprise.getLockedEFundByAddress(queryClient, address)

        if(eFund.amount.amount === "0") {
            return false
        }

        const res = await WrkChain.getFiltered(queryClient, address)

        const hasNum = res.wrkchains.length

        return hasNum <= 0;
    }

    static async getAndSetIdForWallet(queryClient, wallet) {
        const wrkchainId = await WrkChain.getId(queryClient, wallet.meta.wallet_json.address_bech32)

        if(wrkchainId !== null) {
            Logger.debug("RESULT", `${wallet.meta.wallet_json.account} wrkchain id = ${wrkchainId}`)
            wallet.setBeaconOrWrkChainId(wrkchainId)
        }
    }

    static async getFiltered(queryClient, address) {
        return await queryClient.mainchain.wrkchain.v1.wrkChainsFiltered({
            moniker: "",
            owner: address,
        })
    }

    static async getId(queryClient, address) {
        const res = await WrkChain.getFiltered(queryClient, address)
        return (res.wrkchains[0]?.wrkchainId) ? res.wrkchains[0]?.wrkchainId : 0
    }

    static async getFee(queryClient, what) {
        const params = await Module.getParams(queryClient, "mainchain", "wrkchain", "v1")

        const amount = (what === "register") ? params.params.feeRegister.toString() : params.params.feeRecord.toString()

        return {
            amount: [
                {
                    denom: params.params.denom,
                    amount: amount,
                }
            ],
            gas: "150000"
        }
    }
}
