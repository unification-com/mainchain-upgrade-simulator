import {RpcQueryClient} from "../queryClient/client.mjs";
import {PaymentStream} from "../modules/stream.mjs";

// Query clients for every RPC node of both chains. Each query picks a node at random, spreading the load as the txs
// are spread.
export class QueryClients {

    #clients

    constructor(clients) {
        this.#clients = clients
    }

    static async create(networks) {
        const clients = {fund: {mainchain: [], cosmos: [], ibc: []}, gaiad: {cosmos: [], ibc: []}}
        for (const [network, kinds] of Object.entries(clients)) {
            for (const rpc of networks[network].rpcs) {
                for (const kind of Object.keys(kinds)) {
                    kinds[kind].push((await RpcQueryClient.createQueryClient(rpc.rpc, kind)).client)
                }
            }
        }
        // the denom-aware client for the multi-denom x/stream lookups only (see stream.mjs)
        PaymentStream.setQueryClient((await RpcQueryClient.createQueryClient(networks.fund.rpcs[0].rpc, "mainchain_v2")).client)
        return new QueryClients(clients)
    }

    // a random node's client of a kind: "mainchain" (FUND only), "cosmos" or "ibc"
    pick(network, kind) {
        const pool = this.#clients[network][kind]
        return pool[Math.floor(Math.random() * pool.length)]
    }
}
