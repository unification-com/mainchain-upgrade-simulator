import {Logger} from "../libs/logger.mjs";
import {TxFactory} from "../tx/tx_factory.mjs";
import {EFUND_ACTION_STEP} from "../wallet/wallet.mjs";
import {mainchain} from "@unification-com/fundjs";
import {getWalletByAddress} from "../libs/wallet_utils.mjs";
const {
    whitelistAddress,
    undPurchaseOrder,
    processUndPurchaseOrder
} = mainchain.enterprise.v1.MessageComposer.withTypeUrl;

export class Enterprise{
    constructor(){}

    static MsgTypes = {
        ENTERPRISE_WHITELIST_ADD: "enterprise_whitelist_add",
        ENTERPRISE_RAISE_PO: "enterprise_raise_po",
        ENTERPRISE_ACCEPT_PO: "enterprise_accept_po",
    }

    static getMsg(msgType, params) {
        switch (msgType) {
            default:
                return null
            case Enterprise.MsgTypes.ENTERPRISE_WHITELIST_ADD:
                return Enterprise.msgEnterpriseWhitelistAdd(params)
            case Enterprise.MsgTypes.ENTERPRISE_RAISE_PO:
                return Enterprise.msgEnterpriseRaisePo(params)
            case Enterprise.MsgTypes.ENTERPRISE_ACCEPT_PO:
                return Enterprise.msgEnterpriseAcceptPo(params)
        }
    }

    static msgEnterpriseWhitelistAdd(params) {
        const msg = whitelistAddress({
            address: params.address,
            signer: params.wallet.meta.wallet_json.address_bech32,
            whitelistAction: mainchain.enterprise.v1.WhitelistAction.WHITELIST_ACTION_ADD,
        })

        const memo = `${params.wallet.meta.wallet_json.account} whitelist address`
        return {msg, memo}
    }

    static msgEnterpriseRaisePo(params) {
        const msg = undPurchaseOrder({
            purchaser: params.wallet.meta.wallet_json.address_bech32,
            amount: {
                denom: "nund",
                amount: "100000000000000"
            }
        })

        const memo = `${params.wallet.meta.wallet_json.account} purchase eFUND`

        return {msg, memo}
    }

    static msgEnterpriseAcceptPo(params) {
        const msg = processUndPurchaseOrder({
            purchaseOrderId: params.poId,
            decision: mainchain.enterprise.v1.PurchaseOrderStatus.STATUS_ACCEPTED,
            signer: params.wallet.meta.wallet_json.address_bech32,
        })

        return {msg, memo: ""}
    }

    static async runActions(queryClient, enterpriseWallets, eFundWallets, currentBlockHeight){
        const whitelistWallets = []

        for(let i = 0; i < eFundWallets.length; i++) {
            const wallet = eFundWallets[i]
            if(currentBlockHeight < wallet.eFundActionFromBlock) {
                Logger.info("SKIP", `${wallet.meta.wallet_json.account} wait until block ${wallet.eFundActionFromBlock}`)
                continue
            }

            Logger.debug("DEBUG", `eFundActions ${wallet.meta.wallet_json.account} wallet.eFundStatus ${wallet.eFundStatus}`)

            switch (wallet.eFundStatus) {
                case EFUND_ACTION_STEP.NOT_WHITELISTED:
                    whitelistWallets.push(wallet)
                    break
                case EFUND_ACTION_STEP.WHITELIST_TX_SENT:
                    await Enterprise.checkWhitelistedWalletStatus(queryClient, wallet)
                    break
                case EFUND_ACTION_STEP.WHITELISTED:
                    await Enterprise.purchaseEfund(wallet)
                    break
                case EFUND_ACTION_STEP.PO_TX_SENT:
                    // noop - will run Enterprise.processEfundPos below
                    break
                case EFUND_ACTION_STEP.PO_PROCESSING:
                    await Enterprise.checkPoStatus(queryClient, wallet)
                    break
            }
        }

        if(whitelistWallets.length > 0) {
            await Enterprise.whitelistAddresses(enterpriseWallets[0], whitelistWallets)
        }

        await Enterprise.processEfundPos(queryClient, enterpriseWallets, eFundWallets)
    }

    static async whitelistAddresses(signingWallet, whitelistWallets) {
        Logger.info("RUN", "send enterprise whitelist tx")

        const msgs = []

        for(let i = 0; i < whitelistWallets.length; i++) {
            const wallet = whitelistWallets[i]
            const msgParams = {
                wallet: signingWallet,
                address: wallet.meta.wallet_json.address_bech32,
            }
            const {msg,} = Enterprise.getMsg(Enterprise.MsgTypes.ENTERPRISE_WHITELIST_ADD, msgParams)

            msgs.push(msg)

            Logger.info("MSG_ADD", `${wallet.meta.wallet_json.account} added to enterprise whitelist msgs`)
            wallet.setEFundStatus(EFUND_ACTION_STEP.WHITELIST_TX_SENT)
        }

        const memo = `${signingWallet.meta.wallet_json.account} whitelist addresses`

        await TxFactory.sendTx(signingWallet, msgs, memo, null)
    }

    static async checkWhitelistedWalletStatus(queryClient, wallet) {
        Logger.debug("DEBUG", `checkWhitelistedWalletsStatus for ${wallet.meta.wallet_json.address_bech32}`)
        try {
            const isWhitelisted = await queryClient.mainchain.enterprise.v1.whitelisted({
                address: wallet.meta.wallet_json.address_bech32,
            })
            Logger.debug("DEBUG", `isWhitelisted for ${wallet.meta.wallet_json.address_bech32} = ${isWhitelisted.whitelisted}`)
            if (isWhitelisted.whitelisted) {
                wallet.setEFundStatus(EFUND_ACTION_STEP.WHITELISTED)
            }
        } catch(e) {}
    }

    static async purchaseEfund(wallet) {

        if(wallet.pendingTxs.length > 0) {
            return
        }

        Logger.debug("DEBUG", `purchaseEfund for ${wallet.meta.wallet_json.address_bech32}`)

        try {
            const {msg, memo} = Enterprise.getMsg(Enterprise.MsgTypes.ENTERPRISE_RAISE_PO, {wallet})

            await TxFactory.sendTx(wallet, [msg], memo, null)

            wallet.setEFundStatus(EFUND_ACTION_STEP.PO_TX_SENT)
        } catch (e) {
            Logger.debug("DEBUG", `sendTx failed: ${e.message}`)
        }
    }

    static async processEfundPos(queryClient, enterpriseWallets, eFundWallets) {

        const pos = await queryClient.mainchain.enterprise.v1.enterpriseUndPurchaseOrders({
            purchaser: "",
            status: mainchain.enterprise.v1.PurchaseOrderStatus.STATUS_RAISED
        })

        Logger.info("RUN", "check and process enterprise POs")

        if(pos?.purchaseOrders.length > 0) {
            Logger.info("OK", "found raised purchase orders")
            for(let i = 0; i < enterpriseWallets.length; i++) {
                const wallet = enterpriseWallets[i]
                const msgs = []
                if(wallet.pendingTxs.length > 0) {
                    continue
                }

                for(let j = 0; j < pos.purchaseOrders.length; j++) {
                    const poId = pos.purchaseOrders[j].id
                    const purchaser = pos.purchaseOrders[j].purchaser
                    const purchaserWallet = getWalletByAddress(eFundWallets, purchaser)
                    purchaserWallet.setEfundPoId(poId)
                    const {msg, } = Enterprise.getMsg(Enterprise.MsgTypes.ENTERPRISE_ACCEPT_PO, {poId, wallet})
                    msgs.push(msg)
                    purchaserWallet.setEFundStatus(EFUND_ACTION_STEP.PO_PROCESSING)
                }

                const memo = `${wallet.meta.wallet_json.account} process all eFUND POs`
                await TxFactory.sendTx(wallet, msgs, memo, null)
            }

        } else {
            Logger.info("NOOP", "no POs to process")
        }

    }

    static async checkPoStatus(queryClient, wallet) {
        const poStatus = await queryClient.mainchain.enterprise.v1.enterpriseUndPurchaseOrder({
            purchaseOrderId: wallet.eFundPoId
        })

        Logger.debug("DEBUG", `${wallet.meta.wallet_json.account} PO status ${poStatus.purchaseOrder.status}`)

        if(poStatus.purchaseOrder.status === mainchain.enterprise.v1.PurchaseOrderStatus.STATUS_COMPLETED) {
            wallet.setEFundStatus(EFUND_ACTION_STEP.PO_COMPLETE)
        }
    }

    static async getLockedEFundByAddress(queryClient, address) {
        return await queryClient.mainchain.enterprise.v1.lockedUndByAddress({
            owner: address,
        })
    }
}
