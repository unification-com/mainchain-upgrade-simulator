
import {Logger} from "../libs/logger.mjs";
import util from "util";
import {TxRaw} from "cosmjs-types/cosmos/tx/v1beta1/tx.js";
import {execa} from "execa";

// The und CLI inside a FUND node container: cosmovisor/current is always the binary the network is running - the
// genesis release before the upgrade, the upgrade build after it.
const NODE_UND = "/root/.und_mainchain/cosmovisor/current/bin/und"

export class TxFactory {

    static async sendTx(wallet, msgs, memo, fee) {

        const signer = wallet.meta.wallet_json.address_bech32
        let actualFee = fee
        let txHash = null
        let usedSequence = null

        try {
            if(!fee) {
                const gasEstimate = await wallet.signingClient.simulate(signer, msgs, memo)

                actualFee = wallet.calculateFee(gasEstimate)
            }

            // Sign with the locally tracked sequence rather than letting cosmjs re-read it from
            // committed state — see Wallet's signer-data comment for why that races.
            const signerData = await wallet.signerData()
            usedSequence = signerData.sequence
            const txRaw = await wallet.signingClient.sign(signer, msgs, actualFee, memo, signerData)
            txHash = await wallet.signingClient.broadcastTxSync(TxRaw.encode(txRaw).finish())

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
            // Only once a sequence was reserved: the broadcast was rejected by CheckTx. A sequence mismatch names the
            // sequence CheckTx wants - take it. Any other rejection never entered the mempool, so hand the reserved
            // sequence back rather than leaving a gap that would invalidate every subsequent tx.
            if (usedSequence !== null) {
                const mismatch = /account sequence mismatch, expected (\d+)/.exec(e.toString())
                if (mismatch) {
                    wallet.adoptSequence(parseInt(mismatch[1], 10))
                } else {
                    wallet.releaseSequence(usedSequence)
                }
            }
        }

        return txHash

    }

    // Sends a tx through the und CLI instead of the signing client, so the CLI's own code paths (proposal files,
    // client-side fee calculation) are exercised on the version under test - run inside the first FUND RPC node's
    // container, so no host binary is needed. The wallet's key is recovered from its mnemonic into a throwaway keyring
    // that lasts for the one call. `input` is fed to the tx command's stdin (e.g. a proposal file passed as
    // /dev/stdin). Like sendTx, returns the tx hash, or null if nothing was broadcast.
    static async sendCliTx(config, wallet, txArgs, memo, input = "") {
        const rpc = config.networks.fund.rpcs[0]
        const script = [
            'set -e',
            'home=$(mktemp -d)',
            'trap \'rm -rf "$home"\' EXIT',
            `echo "$MNEMONIC" | ${NODE_UND} keys add signer --recover --keyring-backend test --home "$home" > /dev/null 2>&1`,
            `${NODE_UND} "$@" --from signer --keyring-backend test --home "$home" --node tcp://localhost:${rpc.rpc_port} ` +
                `--chain-id ${config.networks.fund.chain_id} --gas auto --gas-adjustment 1.5 --output json --yes`,
        ].join("\n")

        try {
            const {stdout} = await execa("docker",
                ["exec", "-i", "-e", `MNEMONIC=${wallet.meta.wallet_json.mnemonic}`, rpc.container, "sh", "-c", script, "sh", ...txArgs],
                {input})
            const res = JSON.parse(stdout)
            if (res.code !== 0) {
                Logger.error("SEND_TX_CLI", "net=fund", `"${memo}" rejected:`, res.raw_log)
                return null
            }
            Logger.info("SEND_TX_CLI", "net=fund", `rpc=${rpc.name}`, `txHash=${TxFactory.trimTxHash(res.txhash)}`, `"${memo}"`)
            wallet.addSentTx(res.txhash)
            return res.txhash
        } catch (e) {
            Logger.error("SEND_TX_CLI", "net=fund", `"${memo}"`, e.stderr || e.toString())
            return null
        }
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
