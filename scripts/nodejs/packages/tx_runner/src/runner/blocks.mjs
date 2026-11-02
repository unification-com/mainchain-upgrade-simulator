import ReconnectingWebSocket from 'reconnecting-websocket'
import WS from 'ws';
import {Logger} from "../libs/logger.mjs";

// Calls onBlock(block) for each new block of a network, over its first RPC node's websocket. The socket reconnects by
// itself: it drops while the chain halts for the upgrade.
export const subscribeToBlocks = (network, url, onBlock) => {
    Logger.info("RUN", `net=${network}`, "connect to WS", url)
    const ws = new ReconnectingWebSocket(url, [], {WebSocket: WS, connectionTimeout: 1000, maxRetries: 100})
    ws.addEventListener('open', () => {
        Logger.info("RUN", `net=${network}`, "subscribe to NewBlock")
        ws.send(JSON.stringify({"jsonrpc": "2.0", "method": "subscribe", "params": ["tm.event='NewBlock'"], "id": 1}))
    })
    ws.addEventListener('close', () => {
        Logger.warn("WAIT", `net=${network}`, 'websocket disconnected - probably upgrade in progress')
    })
    ws.addEventListener('error', (error) => {
        if (error) {
            Logger.error("WAIT", `net=${network}`, "WebSocket error:", JSON.stringify(error))
        }
    })
    ws.addEventListener('message', async (msg) => {
        const block = JSON.parse(msg.data)?.result?.data?.value?.block
        if (block) {
            await onBlock(block)
        }
    })
    return ws
}
