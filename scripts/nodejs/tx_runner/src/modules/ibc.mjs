import {ibc} from "@unification-com/fundjs";
import {Logger} from "../libs/logger.mjs";
import {bytesToHex} from "@noble/hashes/utils";
import {sha256} from "@noble/hashes/sha2";
import {TxFactory} from "../tx/tx_factory.mjs";
import {randomAmountFromBalance} from "../libs/utils.mjs";
import {Bank} from "./bank.mjs";
const {transfer} = ibc.applications.transfer.v1.MessageComposer.withTypeUrl;

export class IBC {
    constructor () {}

    static MsgTypes = {
        IBC_TRANSFER: "ibc_transfer",
    }

    static ValidRandomMsgTypes = [
        IBC.MsgTypes.IBC_TRANSFER,
    ]

    static randomMsgType() {
        const random = Math.floor(Math.random() * IBC.ValidRandomMsgTypes.length);

        return IBC.ValidRandomMsgTypes[random]
    }

    static getMsg(msgType, params) {
        switch (msgType) {
            default:
                return null
            case IBC.MsgTypes.IBC_TRANSFER:
                return IBC.msgIbcTransfer(params)
        }
    }

    static msgIbcTransfer(params) {

        const msg = transfer({
            sourcePort: "transfer",
            sourceChannel: "channel-0", // ToDo - paramarizationalize
            token: {
                denom: params.denom,
                amount: params.amount.toString(),
            },
            sender: params.fromWallet.meta.wallet_json.address_bech32,
            receiver: params.toWallet.meta.wallet_json.address_bech32,
            timeoutHeight: params.timeoutHeight,
        })

        const memo = `${params.fromWallet.meta.wallet_json.account} send ${params.amount} ${TxFactory.trimTxHash(params.denom)} to ${params.toWallet.meta.wallet_json.account} on ${params.toWallet.meta.network.name}`

        return {msg, memo}
    }

    static async calculateIbcTimeoutHeight(rpc, port, channel) {
        const timeoutHeight = {
            revisionNumber: 0,
            revisionHeight: 1000
        }

        // just query LCD for now
        const chanelStateRes = await fetch(`${rpc.rest}/ibc/core/channel/v1/channels/${channel}/ports/${port}/client_state`)
        const chanelState = await chanelStateRes.json()

        const latestHeight = chanelState.identified_client_state.client_state.latest_height
        timeoutHeight.revisionNumber += parseInt(latestHeight.revision_number, 10)
        timeoutHeight.revisionHeight += parseInt(latestHeight.revision_height, 10)

        return timeoutHeight
    }

    static async checkIbcChannel(queryClient, network) {
        let ibcOpen = false
        let ibcDenom = null

        const ibcChannelsRes = await queryClient.ibc.core.channel.v1.channels()

        if(ibcChannelsRes.channels.length > 0) {
            if(ibcChannelsRes.channels[0]?.state === ibc.core.channel.v1.State.STATE_OPEN) {
                Logger.info("OK", `${network} IBC Channel open`)
                ibcOpen = true
                const trace = `transfer/${ibcChannelsRes.channels[0]?.channelId}/nund`
                ibcDenom = `ibc/${bytesToHex(sha256(trace)).toUpperCase()}`
            }
        }

        return {
            open: ibcOpen,
            denom: ibcDenom,
        }
    }

    static async runIbcTransfers(fromQueryClient, toQueryClient, fromWallets, toWallets, timeoutHeight, fromDenom, toDenom, minPerc, maxPerc) {
        for(let i = 0; i < fromWallets.length; i++) {
            const fromWallet = fromWallets[i]

            const rndIdx = Math.floor(Math.random() * toWallets.length)
            const toWallet = toWallets[rndIdx]

            if(fromDenom === "nund") {
                const toWalletBalance = await Bank.getSpendableBalance(toQueryClient, toWallet, toDenom)

                const toBalance = parseInt(toWalletBalance.amount, 10)

                if(toBalance >= 1000000000) {
                    Logger.verbose("SKIP", `${toWallet.meta.wallet_json.account} already has ${toBalance} ${TxFactory.trimTxHash(toDenom)} on gaiad`)
                    continue
                }
            }

            const fromWalletBalance = await Bank.getSpendableBalance(fromQueryClient, fromWallet, fromDenom)

            const amount = randomAmountFromBalance(fromWalletBalance.amount, minPerc, maxPerc)

            if(amount === 0) {
                Logger.verbose("SKIP", `${fromWallet.meta.wallet_json.account} has zero balance for ${TxFactory.trimTxHash(fromDenom)}`)
                continue
            }

            await IBC.sendIbcTransfer(fromWallet, toWallet, amount, fromDenom, timeoutHeight)

        }
    }

    static async sendIbcTransfer(fromWallet, toWallet, amount, denom, timeoutHeight) {
        const {msg, memo} = IBC.getMsg(IBC.MsgTypes.IBC_TRANSFER, {
            fromWallet,
            toWallet,
            amount: amount,
            denom: denom,
            timeoutHeight: timeoutHeight,
        })

        await TxFactory.sendTx(fromWallet, [msg], memo, null)
    }

}
