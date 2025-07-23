import {cosmos} from "@unification-com/fundjs";
import {randomAmountFromBalance} from "../libs/utils.mjs";
import {TxFactory} from "../tx/tx_factory.mjs";
import {Logger} from "../libs/logger.mjs";
const {delegate, undelegate, beginRedelegate} = cosmos.staking.v1beta1.MessageComposer.withTypeUrl;
const {withdrawDelegatorReward, withdrawValidatorCommission} = cosmos.distribution.v1beta1.MessageComposer.withTypeUrl;

export class Stake {
    constructor () {}

    static MsgTypes = {
        STAKING_STAKE: "staking_stake",
        STAKING_UNSTAKE: "staking_unstake",
        STAKING_WITHDRAW: "staking_withdraw",
    }

    static ValidRandomMsgTypes = [
        Stake.MsgTypes.STAKING_STAKE,
        Stake.MsgTypes.STAKING_UNSTAKE,
        Stake.MsgTypes.STAKING_WITHDRAW,
    ]

    static randomMsgType() {
        const random = Math.floor(Math.random() * Stake.ValidRandomMsgTypes.length);

        return Stake.ValidRandomMsgTypes[random]
    }

    static getMsg(msgType, params) {
        switch (msgType) {
            default:
                return null
            case Stake.MsgTypes.STAKING_STAKE:
                return Stake.msgDelegate(params)
            case Stake.MsgTypes.STAKING_UNSTAKE:
                return Stake.msgUnDelegate(params)
            case Stake.MsgTypes.STAKING_WITHDRAW:
                return Stake.msgWithdrawDelegatorReward(params)
        }
    }

    static msgDelegate(params) {
        const msg = delegate({
            delegatorAddress: params.fromWallet.meta.wallet_json.address_bech32,
            validatorAddress: params.validator.meta.wallet_json.validator_address,
            amount: params.amount,
        })

        const memo = `${params.fromWallet.meta.wallet_json.account} delegate ${params.amount.amount.toString()}nund to ${params.validator.meta.wallet_json.account}`

        return {msg, memo}
    }

    static msgUnDelegate(params) {
        const msg = undelegate({
            delegatorAddress: params.fromWallet.meta.wallet_json.address_bech32,
            validatorAddress: params.validator.meta.wallet_json.validator_address,
            amount: params.amount,
        })

        const memo = `${params.fromWallet.meta.wallet_json.account} undelegate ${params.amount.amount.toString()}nund from ${params.validator.meta.wallet_json.account}`

        return {msg, memo}
    }

    static msgWithdrawDelegatorReward(params) {
        const msg = withdrawDelegatorReward({
            delegatorAddress: params.fromWallet.meta.wallet_json.address_bech32,
            validatorAddress: params.validator.meta.wallet_json.validator_address,
        })

        const memo = `${params.fromWallet.meta.wallet_json.account} withdraw rewards from ${params.validator.meta.wallet_json.account}`

        return {msg, memo}
    }

    static async sendRandomMsg(queryClient, fromWallet, validator) {
        const delegationBalance = await Stake.getDelegatedBalance(queryClient, fromWallet, validator)
        const delegationAmount = parseInt(delegationBalance?.amount, 10)
        let rndMsgType = Stake.MsgTypes.STAKING_STAKE
        fromWallet.setHasBondedTokens(false)

        if(delegationAmount > 0) {
            fromWallet.setHasBondedTokens(true)
            rndMsgType = Stake.randomMsgType()
        }

        switch(rndMsgType) {
            case Stake.MsgTypes.STAKING_STAKE:
                await Stake.stake(queryClient, fromWallet, validator)
                break
            case Stake.MsgTypes.STAKING_UNSTAKE:
                await Stake.unstake(queryClient, fromWallet, validator, delegationBalance)
                break
            case Stake.MsgTypes.STAKING_WITHDRAW:
                await Stake.withdrawRewards(queryClient, fromWallet, validator)
                break
        }
    }

    static async stake(queryClient, fromWallet, validator) {
        const balance = await queryClient.cosmos.bank.v1beta1.balance({
            address: fromWallet.meta.wallet_json.address_bech32,
            denom: "nund",
        })

        const amount = randomAmountFromBalance(balance.balance.amount, 0.001, 0.002)

        const {msg, memo} = Stake.getMsg(Stake.MsgTypes.STAKING_STAKE, {
            fromWallet,
            validator,
            amount: {
                denom: "nund",
                amount: amount.toString(),
            }
        })

        await TxFactory.sendTx(fromWallet, [msg], memo, null)
    }

    static async unstake(queryClient, fromWallet, validator, delegationBalance) {
        const delegationAmount = parseInt(delegationBalance?.amount, 10)

        if(delegationAmount === 0) {
            Logger.verbose("SKIP", `${fromWallet.meta.wallet_json.account} has zero stake in ${validator.meta.wallet_json.account}`)
            return
        }

        const unbondAmount = randomAmountFromBalance(delegationAmount, 0.75, 1)

        if(unbondAmount === 0) {
            Logger.verbose("SKIP", `${fromWallet.meta.wallet_json.account} not unbonding from ${validator.meta.wallet_json.account}`)
            return
        }

        const {msg, memo} = Stake.getMsg(Stake.MsgTypes.STAKING_UNSTAKE, {
            fromWallet,
            validator,
            amount: {
                denom: "nund",
                amount: unbondAmount.toString(),
            }
        })

        await TxFactory.sendTx(fromWallet, [msg], memo, null)
    }

    static async withdrawRewards(queryClient, fromWallet, validator) {
        const stakeBalance = await this.getDelegatedBalance(fromWallet, validator)

        const stakeAmount = parseInt(stakeBalance?.amount, 10)

        if(stakeAmount === 0) {
            Logger.verbose("SKIP", `${fromWallet.meta.wallet_json.account} has zero stake in ${validator.meta.wallet_json.account}`)
            return
        }

        const {msg, memo} = Stake.getMsg(Stake.MsgTypes.STAKING_WITHDRAW, {
            fromWallet,
            validator,
        })

        await TxFactory.sendTx(fromWallet, [msg], memo, null)
    }

    static async getDelegatedBalance(queryClient, fromWallet, validator) {
        let delegationBalance = {
            amount: "0",
            denom: "nund",
        }
        try {
            const delegationRes = await queryClient.cosmos.staking.v1beta1.delegation({
                delegatorAddr: fromWallet.meta.wallet_json.address_bech32,
                validatorAddr: validator.meta.wallet_json.validator_address,
            })

            delegationBalance = delegationRes?.delegationResponse?.balance
        } catch(e) {

        }

        return delegationBalance
    }
}
