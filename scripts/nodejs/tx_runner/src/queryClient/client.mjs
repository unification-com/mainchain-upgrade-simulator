import {mainchain, cosmos, ibc } from '@unification-com/fundjs';
// See the note in modules/stream.mjs: vaxildan's multi-denom x/stream adds a `denom` to the stream
// QUERY requests as well as the messages, and fundjs 0.1.0 cannot encode it. This client is used
// only for the stream lookups; with denom = "" its requests are byte-identical to 0.1.0's, so it is
// safe on both sides of the upgrade.
import {mainchain as mainchainV2} from 'fundjs2';

const {createRPCQueryClient: createMainchainRPCQueryClient} = mainchain.ClientFactory;
const {createRPCQueryClient: createMainchainV2RPCQueryClient} = mainchainV2.ClientFactory;
const {createRPCQueryClient: createCosmosRPCQueryClient} = cosmos.ClientFactory;
const {createRPCQueryClient: createIbcRPCQueryClient} = ibc.ClientFactory;

export class RpcQueryClient {
    #client = null
    constructor(client) {
        this.#client = client;
    }

    static async createQueryClient(rpc, clientType) {
        let client = null
        switch (clientType) {
            case "mainchain":
                client = await createMainchainRPCQueryClient({rpcEndpoint: rpc})
                break
            case "mainchain_v2":
                client = await createMainchainV2RPCQueryClient({rpcEndpoint: rpc})
                break
            case "ibc":
                client = await createIbcRPCQueryClient({rpcEndpoint: rpc})
                break
            default:
            case "cosmos":
                client = await createCosmosRPCQueryClient({rpcEndpoint: rpc})
                break
        }

        return new RpcQueryClient(client)
    }

    get client() {
        return this.#client
    }
}
