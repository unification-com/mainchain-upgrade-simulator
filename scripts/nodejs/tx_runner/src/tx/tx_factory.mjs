
import {Logger} from "../libs/logger.mjs";
import util from "util";

export class TxFactory {

    static async sendTx(wallet, msgs, memo, fee) {

        const signer = wallet.meta.wallet_json.address_bech32
        let actualFee = fee
        let txHash = null

        try {
            if(!fee) {
                const gasEstimate = await wallet.signingClient.simulate(signer, msgs, memo)

                actualFee = wallet.calculateFee(gasEstimate)
            }

            txHash = await wallet.signingClient.signAndBroadcastSync(signer, msgs, actualFee, memo);

            Logger.info(
                "SEND_TX",
                `net=${wallet.meta.network.name}`,
                `rpc=${wallet.meta.selected_rpc}`,
                `msg=${msgs[0].typeUrl}`,
                `txHash=${TxFactory.trimTxHash(txHash)}`,
                `"${memo}"`
            )

            wallet.addSentTx(txHash)

        } catch (e) {
            Logger.error("SEND_TX", `net=${wallet.meta.network.name}`, e.toString())
        }

        return txHash

    }

    static moveSentToPending(wallet) {
        for(let i = 0; i < wallet.sentTxs.length; i++) {
            const txHash = wallet.sentTxs[i]
            Logger.debug("TX_RESULT", `move ${txHash} from sent to pending queue`)
            wallet.removeSentTx(i)
            wallet.addPendingTx(txHash)
        }
    }

    static async checkWalletTxs(wallet, queryClient) {

        for(let i = 0; i < wallet.pendingTxs.length; i++) {
            const txHash = wallet.pendingTxs[i]
            Logger.debug("TX_RESULT", `check ${txHash} and remove from pending queue`)
            const res = queryClient.cosmos.tx.v1beta1.getTx({hash: txHash})
            wallet.addTxResult(res)
            wallet.removePendingTx(i)
        }

        // check for rejected promises from previous attempts
        for(let j = 0; j < wallet.txResults.length; j++) {
            if(util.inspect(wallet.txResults[j]).includes("rejected")) {
                Logger.verbose("CLEAN", "remove rejected tx from queue. See previous output for error")
                wallet.removeTxResult(j)
            }
        }

        // resolve promises
        Promise.all(wallet.txResults).then((x) => {
            for(let i = 0; i < x.length; i++) {
                const tx = x[i]
                if(tx.txResponse.code === 0) {
                    Logger.info(
                        "TX_RESULT",
                        `net=${wallet.meta.network.name}`,
                        TxFactory.trimTxHash(tx.txResponse.txhash),
                        `success "${tx.tx.body.memo}"`,
                        "height",
                        tx.txResponse.height.toString()
                    )
                } else {
                    Logger.error(
                        "TX_RESULT",
                        `net=${wallet.meta.network.name}`,
                        TxFactory.trimTxHash(tx.txResponse.txhash),
                        `FAILED "${tx.tx.body.memo}"`,
                        "code", tx.txResponse.code,
                        "codespace", tx.txResponse.codespace,
                        "log", tx.txResponse.rawLog)
                }

                wallet.removeTxResult(i)
            }
        }).catch(err => {
            const errStr = err.toString()

            if(errStr.includes("tx not found")) {
                // attempt to extract and recheck tx hash
                const eArr = errStr.split(": ")
                const txHash = eArr[eArr.length - 2]
                Logger.warn("TX_RESULT", `tx ${TxFactory.trimTxHash(txHash)} not yet indexed. Will check in next block`)
                wallet.addPendingTx(txHash)
            } else {
                Logger.error("TX_RESULT", errStr)
            }
        });
    }

    static trimTxHash(txHash, length = 6) {
        if(!txHash) {
            return txHash
        }
        if (txHash.length > length) {
            return `${txHash.substring(0, length)}...${txHash.substring(txHash.length -length)}`;
        }
        return txHash
    }
}
