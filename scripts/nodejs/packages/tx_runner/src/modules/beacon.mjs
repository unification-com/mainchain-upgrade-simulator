import {Enterprise} from "./enterprise.mjs";
import {Module} from "./module.mjs";
import {Logger} from "../libs/logger.mjs";
import {TxFactory} from "../tx/tx_factory.mjs";
import {EFUND_ACTION_STEP} from "../wallet/wallet.mjs";
import {mainchain} from "@unification-com/fundjs";
// vaxildan (#129) adds an optional `metadata` field to BEACON timestamps, which fundjs 0.1.0 cannot
// encode — so the composer for recordBeaconTimestamp comes from 0.2.1 (aliased as fundjs2). With
// metadata = "" it encodes byte-identically to 0.1.0, so the same call is correct on both sides of
// the upgrade; the runner sets a value once the chain has crossed the boundary.
// TODO: drop the alias and move wholesale to fundjs >= 0.2.1 once vaxildan is live.
import {mainchain as mainchainV2} from "fundjs2";
const {registerBeacon} = mainchain.beacon.v1.MessageComposer.withTypeUrl;
const {recordBeaconTimestamp} = mainchainV2.beacon.v1.MessageComposer.withTypeUrl;
const { createHmac } = await import('node:crypto');

export class Beacon {

    // Optional BEACON timestamp metadata (vaxildan #129, 256-byte cap on chain). Empty until the
    // chain crosses the upgrade height — pre-vaxildan the field does not exist and the SDK rejects
    // unknown fields.
    static beaconMetadata = ""

    // Called by the runner each block so records match the running consensus version.
    static setBeaconMetadata(currentHeight, upgradeHeight) {
        const meta = (upgradeHeight > 0 && currentHeight >= upgradeHeight)
            ? `sim;h=${currentHeight}` : ""
        if ((meta === "") !== (Beacon.beaconMetadata === "")) {
            Logger.info("BEACON METADATA", `recording timestamps with metadata from height ${currentHeight}`)
        }
        Beacon.beaconMetadata = meta
    }
    constructor () {}

    static MsgTypes = {
        BEACON_REGISTER: "beacon_register",
        BEACON_RECORD: "beacon_record",
    }

    static getMsg(msgType, params) {
        switch (msgType) {
            default:
                return null
            case Beacon.MsgTypes.BEACON_REGISTER:
                return Beacon.msgRegisterBeacon(params)
            case Beacon.MsgTypes.BEACON_RECORD:
                return Beacon.msgRecordBeaconTimestamp(params)
        }
    }

    static msgRegisterBeacon(params) {
        const msg = registerBeacon({
            moniker: params.wallet.meta.wallet_json.account,
            name: params.wallet.meta.wallet_json.account,
            owner: params.wallet.meta.wallet_json.address_bech32,
        })

        const memo = `${params.wallet.meta.wallet_json.account} register BEACON`

        return {msg, memo}
    }

    static msgRecordBeaconTimestamp(params) {
        const submitTime = Math.floor(Date.now() / 1000)
        const hash = createHmac('sha256', params.wallet.meta.wallet_json.account)
            .update(`${params.wallet.meta.wallet_json.address_bech32} ${new Date()}`)
            .digest('hex')
            .toUpperCase();

        const msg = recordBeaconTimestamp({
            beaconId: params.beaconId,
            submitTime: submitTime,
            hash: hash,
            owner: params.wallet.meta.wallet_json.address_bech32,
            metadata: Beacon.beaconMetadata,
        })

        const memo = `${params.wallet.meta.wallet_json.account} record`

        return {msg, memo}
    }

    static async runActions(queryClient, wallets) {

        const regFee = await Beacon.getFee(queryClient, "register")
        const recordFee = await Beacon.getFee(queryClient, "record")

        for(let i = 0; i < wallets.length; i++) {
            const wallet = wallets[i]
            if(!wallet.beaconOrWrkChainRegTxSent && wallet.eFundStatus === EFUND_ACTION_STEP.PO_COMPLETE) {
                //register
                await Beacon.register(queryClient, wallet, regFee)
                continue
            }

            if(wallet.beaconOrWrkChainRegTxSent && wallet.beaconOrWrkChainId === 0) {
                // get ID
                await Beacon.getAndSetIdForWallet(queryClient, wallet)
                continue
            }

            if(wallet.beaconOrWrkChainId > 0) {
                // record
                await Beacon.recordTimestamp(queryClient, wallet, recordFee)
            }
        }
    }

    static async register(queryClient, wallet, fee) {
        Logger.info("RUN", "register beacons")

        if(wallet.pendingTxs.length > 0) {
            return
        }
        const canRegister = await Beacon.canRegister(queryClient, wallet.meta.wallet_json.address_bech32)

        if(!canRegister) {
            Logger.info("WAIT", `${wallet.meta.wallet_json.account} cannot register yet`)
            return
        }

        const {msg, memo} = Beacon.getMsg(Beacon.MsgTypes.BEACON_REGISTER, {wallet})

        await TxFactory.sendTx(wallet, [msg], memo, fee)
        wallet.setBeaconOrWrkChainRegTxSent(true)
    }

    static async recordTimestamp(queryClient, wallet, fee) {
        const beaconId = wallet.beaconOrWrkChainId
        if(beaconId === null || beaconId === 0) {
            Logger.info("WAIT", `${wallet.meta.wallet_json.account} beacon not registered yet`)
            return
        }

        const {msg, memo} = Beacon.getMsg(Beacon.MsgTypes.BEACON_RECORD, {
            wallet,
            beaconId,
        })

        await TxFactory.sendTx(wallet, [msg], memo, fee)
    }

    static async canRegister(queryClient, address) {
        const eFund = await Enterprise.getLockedEFundByAddress(queryClient, address)

        if(eFund.amount.amount === "0") {
            return false
        }

        const res = await Beacon.getFiltered(queryClient, address)

        const hasNum = res.beacons.length

        return hasNum <= 0;
    }

    static async getAndSetIdForWallet(queryClient, wallet) {
        const beaconId = await Beacon.getId(queryClient, wallet.meta.wallet_json.address_bech32)

        if(beaconId !== null) {
            Logger.debug("RESULT", `${wallet.meta.wallet_json.account} beacon id = ${beaconId}`)
            wallet.setBeaconOrWrkChainId(beaconId)
        }
    }

    static async getFiltered(queryClient, address) {
        return await queryClient.mainchain.beacon.v1.beaconsFiltered({
            moniker: "",
            owner: address,
        })
    }

    static async getId(queryClient, address) {
        const res = await Beacon.getFiltered(queryClient, address)
        return (res.beacons[0]?.beaconId) ? res.beacons[0]?.beaconId : 0
    }

    static async getFee(queryClient, what) {
        const params = await Module.getParams(queryClient, "mainchain", "beacon", "v1")

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
