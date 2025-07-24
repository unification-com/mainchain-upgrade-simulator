import {mainchain} from "@unification-com/fundjs";
import { TxFactory} from "../tx/tx_factory.mjs";
import {Logger} from "../libs/logger.mjs";
const {createStream, claimStream, topUpDeposit, updateFlowRate, cancelStream} = mainchain.stream.v1.MessageComposer.withTypeUrl;

export class PaymentStream {
    constructor() {}

    static MsgTypes = {
        STREAM_CREATE: "stream_create",
        STREAM_CLAIM: "stream_claim",
        STREAM_TOPUP: "stream_topup",
        STREAM_UPDATE_FLOW: "stream_update_flow",
        STREAM_CANCEL:  "stream_cancel",
        STREAM_RANDOM: "stream_random",
    }

    static ValidRandomMsgTypes = [
        PaymentStream.MsgTypes.STREAM_TOPUP,
        PaymentStream.MsgTypes.STREAM_UPDATE_FLOW,
        PaymentStream.MsgTypes.STREAM_CANCEL,
    ]

    static randomMsgType() {
        const random = Math.floor(Math.random() * PaymentStream.ValidRandomMsgTypes.length);

        return PaymentStream.ValidRandomMsgTypes[random]
    }

    static getMsg(msgType, params) {
        switch (msgType) {
            default:
                return null
            case PaymentStream.MsgTypes.STREAM_RANDOM:
                return PaymentStream.randomStreamSenderMsg(params)
            case PaymentStream.MsgTypes.STREAM_CREATE:
                return PaymentStream.msgCreateStream(params)
            case PaymentStream.MsgTypes.STREAM_CLAIM:
                return PaymentStream.msgClaimStream(params)
            case PaymentStream.MsgTypes.STREAM_TOPUP:
                return PaymentStream.msgTopUpDeposit(params)
            case PaymentStream.MsgTypes.STREAM_UPDATE_FLOW:
                return PaymentStream.msgUpdateFlowRate(params)
            case PaymentStream.MsgTypes.STREAM_CANCEL:
                return PaymentStream.msgCancelStream(params)
        }
    }

    static randomStreamSenderMsg(params) {
        const rnd = Math.floor(Math.random() * 100)

        if(rnd < 2) {
            return PaymentStream.msgCancelStream(params)
        }

        if(rnd >= 2 && rnd <= 5) {
            return PaymentStream.msgUpdateFlowRate(params)
        }

        if(rnd > 5 && rnd <= 10) {
            return PaymentStream.msgTopUpDeposit(params)
        }

        return {msg: null, memo: null}
    }

    static msgCreateStream(params) {
        // https://rest.unification.io/mainchain/stream/v1/calculate_flow_Rate?coin=100000000000nund&period=2&duration=10
        // 100 FUND 5 minutes = 333333333
        // 100 FUND 2 minutes = 833333333

        const minFlow = 333333333
        const maxFlow = 833333333
        const maxDeposit = 100
        const flow = Math.floor(Math.random() * (maxFlow - minFlow + 1)) + minFlow

        const msg = createStream({
            receiver: params.receiver.meta.wallet_json.address_bech32,
            sender: params.sender.meta.wallet_json.address_bech32,
            deposit: {
                denom: "nund",
                amount: (maxDeposit * (10**9)).toString()
            },
            flowRate: flow,
        })

        const memo = `${params.sender.meta.wallet_json.account} create payment stream to ${params.receiver.meta.wallet_json.account}`

        return {msg, memo}
    }

    static msgClaimStream(params) {
        const msg = claimStream({
            receiver: params.receiver.meta.wallet_json.address_bech32,
            sender: params.sender.meta.wallet_json.address_bech32,
        })

        const memo = `${params.receiver.meta.wallet_json.account} claim from stream`

        return {msg, memo}
    }

    static msgTopUpDeposit(params) {

        const minTopUp = 1
        const maxTopUp = 100
        const topUp = (Math.floor(Math.random() * (maxTopUp - minTopUp + 1)) + minTopUp)
        const topUpNund = topUp * (10**9)

        const msg = topUpDeposit({
            receiver: params.receiver.meta.wallet_json.address_bech32,
            sender: params.sender.meta.wallet_json.address_bech32,
            deposit: {
                denom: "nund",
                amount: topUpNund.toString()
            },
        })

        const memo = `${params.sender.meta.wallet_json.account} top up deposit with ${topUp} FUND to ${params.receiver.meta.wallet_json.account}`

        return {msg, memo}
    }

    static msgUpdateFlowRate(params) {
        const minFlow = 333333333
        const maxFlow = 833333333
        const flow = Math.floor(Math.random() * (maxFlow - minFlow + 1)) + minFlow

        const msg = updateFlowRate({
            receiver: params.receiver.meta.wallet_json.address_bech32,
            sender: params.sender.meta.wallet_json.address_bech32,
            flowRate: flow,
        })

        const memo = `${params.sender.meta.wallet_json.account} update flow rate to ${flow} for ${params.receiver.meta.wallet_json.account}`

        return {msg, memo}
    }

    static msgCancelStream(params) {
        const msg = cancelStream({
            receiver: params.receiver.meta.wallet_json.address_bech32,
            sender: params.sender.meta.wallet_json.address_bech32,
        })

        const memo = `${params.sender.meta.wallet_json.account} cancel stream to ${params.receiver.meta.wallet_json.account}`

        return {msg, memo}
    }

    static async runStreamTxs(queryClient, senderWallets, receiverWallets) {
        for(let i = 0; i < senderWallets.length; i++) {
            const sender = senderWallets[i]
            const receiver = receiverWallets[i]
            sender.setGasMultiplier(2.0)
            receiver.setGasMultiplier(2.5)
            let msgType = PaymentStream.MsgTypes.STREAM_RANDOM
            let streamFlow = null
            let stream = null
            // check stream exists
            try {
                streamFlow = await queryClient.mainchain.stream.v1.streamReceiverSenderCurrentFlow({
                    receiverAddr: receiver.meta.wallet_json.address_bech32,
                    senderAddr: sender.meta.wallet_json.address_bech32,
                })

                stream = await queryClient.mainchain.stream.v1.streamByReceiverSender({
                    receiverAddr: receiver.meta.wallet_json.address_bech32,
                    senderAddr: sender.meta.wallet_json.address_bech32,
                })

                if (parseInt(streamFlow?.currentFlowRate, 10) === 0 || parseInt(stream?.stream?.stream?.deposit?.amount, 10) === 0) {
                    Logger.warn("FORCE", `${sender.meta.wallet_json.account} -> ${receiver.meta.wallet_json.account} stream current flow rate or deposit is zero. Force topup`, `current_flow=${streamFlow?.currentFlowRate}`, `deposit=${stream?.stream?.stream?.deposit?.amount}`)
                    msgType = PaymentStream.MsgTypes.STREAM_TOPUP
                }
            } catch (e) {
                Logger.warn("FORCE", `${sender.meta.wallet_json.account} -> ${receiver.meta.wallet_json.account} stream does not exist. Force create`)
                msgType = PaymentStream.MsgTypes.STREAM_CREATE
            }

            // default params
            const params = {
                sender,
                receiver,
            }

            // sender msg
            let {msg, memo} = PaymentStream.getMsg(msgType, params)

            if (msg !== null) {
                await TxFactory.sendTx(sender, [msg], memo, null)
            } else {
                Logger.verbose("SKIP", `no msg for ${sender.meta.wallet_json.account}`)
            }

            // receiver claim stuff
            if (streamFlow === null || stream === null) {
                Logger.warn("SKIP", `${sender.meta.wallet_json.account} -> ${receiver.meta.wallet_json.account} no stream to claim from`)
            } else if(parseInt(streamFlow?.currentFlowRate, 10) === 0 || parseInt(stream?.stream?.stream?.deposit?.amount, 10) === 0) {
                Logger.warn("SKIP", `${sender.meta.wallet_json.account} -> ${receiver.meta.wallet_json.account} stream current flow rate or deposit is zero`, `current_flow=${streamFlow?.currentFlowRate}`, `deposit=${stream?.stream?.stream?.deposit?.amount}`)
            } else if(msg?.typeUrl === "/mainchain.stream.v1.MsgCancelStream") {
                Logger.warn("SKIP", `${sender.meta.wallet_json.account} -> ${receiver.meta.wallet_json.account} stream was just cancelled`)
            } else {
                let {msg, memo} = PaymentStream.getMsg(PaymentStream.MsgTypes.STREAM_CLAIM, {
                    sender,
                    receiver,
                })
                await TxFactory.sendTx(receiver, [msg], memo, null)
            }
        }
    }
}
