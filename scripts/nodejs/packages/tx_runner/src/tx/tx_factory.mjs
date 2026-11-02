
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
            // committed state - see Wallet's signer-data comment for why that races.
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

    // Runs und commands in the first FUND RPC node's container - its cosmovisor/current is the version under test, and
    // no host binary is needed - signing as the wallet, whose key is recovered from its mnemonic into a throwaway
    // keyring that lasts for the one call. `commands(flags)` gives the script's command lines; flags points them at the
    // keyring and node. `args` are the script's "$@" and `input` its stdin. Logs the outcome and tracks an accepted tx
    // like any other. Returns the tx response, or null if the script failed before broadcasting.
    static async #inNode(config, wallet, commands, args, input, memo) {
        const rpc = config.networks.fund.rpcs[0]
        const flags = `--keyring-backend test --home "$home" --node tcp://localhost:${rpc.rpc_port} --chain-id ${config.networks.fund.chain_id}`
        const script = [
            'set -e',
            'home=$(mktemp -d)',
            'trap \'rm -rf "$home"\' EXIT',
            `echo "$MNEMONIC" | ${NODE_UND} keys add signer --recover --keyring-backend test --home "$home" > /dev/null 2>&1`,
            ...commands(flags),
        ].join("\n")

        let res
        try {
            const {stdout} = await execa("docker",
                ["exec", "-i", "-e", `MNEMONIC=${wallet.meta.wallet_json.mnemonic}`, rpc.container, "sh", "-c", script, "sh", ...args],
                {input})
            res = JSON.parse(stdout)
        } catch (e) {
            Logger.error("SEND_TX_CLI", "net=fund", `"${memo}"`, e.stderr || e.toString())
            return null
        }
        if (res.code !== 0) {
            Logger.error("SEND_TX_CLI", "net=fund", `"${memo}" rejected:`, res.raw_log)
        } else {
            Logger.info("SEND_TX_CLI", "net=fund", `rpc=${rpc.name}`, `txHash=${TxFactory.trimTxHash(res.txhash)}`, `"${memo}"`)
            wallet.addSentTx(res.txhash)
        }
        return res
    }

    // Sends a tx through the und CLI instead of the signing client, so the CLI's own code paths (proposal files,
    // client-side fee calculation) are exercised on the version under test. `input` is fed to the tx command's stdin
    // (e.g. a proposal file passed as /dev/stdin). Like sendTx, returns the tx hash, or null if nothing was broadcast.
    static async sendCliTx(config, wallet, txArgs, memo, input = "") {
        const res = await TxFactory.#inNode(config, wallet,
            (flags) => [`${NODE_UND} "$@" --from signer ${flags} --gas auto --gas-adjustment 1.5 --output json --yes`],
            txArgs, input, memo)
        return res?.code === 0 ? res.txhash : null
    }

    // Signs an unsigned tx (its JSON text) as the wallet and broadcasts it - any message the running binary knows,
    // with no per-type code here. Returns the broadcast response (code 0 = accepted into the mempool), or null if it
    // was not broadcast.
    static async sendUnsignedTx(config, wallet, unsignedTx, memo) {
        return await TxFactory.#inNode(config, wallet, (flags) => [
            'cat > "$home/unsigned.json"',
            `${NODE_UND} tx sign "$home/unsigned.json" --from signer ${flags} --output-document "$home/signed.json"`,
            `${NODE_UND} tx broadcast "$home/signed.json" ${flags} --output json`,
        ], [], unsignedTx, memo)
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
