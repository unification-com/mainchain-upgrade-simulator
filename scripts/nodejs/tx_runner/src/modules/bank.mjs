import {cosmos} from "@unification-com/fundjs";
import {TxFactory} from "../tx/tx_factory.mjs";
import {randomAmountFromBalance} from "../libs/utils.mjs";

const {send} = cosmos.bank.v1beta1.MessageComposer.withTypeUrl;

export class Bank {
    constructor() {}

    static MsgTypes = {
        BANK_SEND: "bank_send",
    }

    static ValidRandomMsgTypes = [
        Bank.MsgTypes.BANK_SEND,
    ]

    static randomMsgType() {
        const random = Math.floor(Math.random() * Bank.ValidRandomMsgTypes.length);

        return Bank.ValidRandomMsgTypes[random]
    }

    static getMsg(msgType, params) {
        switch (msgType) {
            default:
                return null
            case Bank.MsgTypes.BANK_SEND:
                return Bank.msgBankSend(params)
        }
    }

    static msgBankSend(params) {

        const msg = send({
            fromAddress: params.fromWallet.meta.wallet_json.address_bech32,
            toAddress: params.toWallet.meta.wallet_json.address_bech32,
            amount: [
                {
                    denom: "nund",
                    amount: params.amount.toString(),
                }
            ],
        })

        const memo = `${params.fromWallet.meta.wallet_json.account} send ${params.amount}nund to ${params.toWallet.meta.wallet_json.account}`

        return {msg, memo}
    }

    static async sendRandomMsg(queryClient, fromWallet, toWallet) {
        const rndMsgType = Bank.randomMsgType()
        switch(rndMsgType) {
            case Bank.MsgTypes.BANK_SEND:
                await Bank.bankSend(queryClient, fromWallet, toWallet)
                break
        }
    }

    static async bankSend(queryClient, fromWallet, toWallet) {
        const balance = await Bank.getBalanceByDenom(queryClient, fromWallet, "nund")

        const amount = randomAmountFromBalance(balance.balance.amount, 0.01, 0.02)

        const {msg, memo} = Bank.getMsg(Bank.MsgTypes.BANK_SEND, {
            fromWallet,
            toWallet,
            amount,
        })

        await TxFactory.sendTx(fromWallet, [msg], memo, null)
    }

    static async getBalanceByDenom(queryClient, wallet, denom) {
        return await queryClient.cosmos.bank.v1beta1.balance({
            address: wallet.meta.wallet_json.address_bech32,
            denom,
        })
    }

    static async getSpendableBalance(queryClient, wallet, denom) {
        const balances = await queryClient.cosmos.bank.v1beta1.spendableBalances({
            address: wallet.meta.wallet_json.address_bech32,
        })

        for(let j = 0; j < balances.balances.length; j++) {
            if(balances.balances[j].denom === denom) {
                return balances.balances[j]
            }
        }

        return {
            amount: "0",
            denom,
        }
    }
}
