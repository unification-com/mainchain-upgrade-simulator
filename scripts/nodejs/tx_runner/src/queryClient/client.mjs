import {mainchain, cosmos, ibc } from '@unification-com/fundjs';

const {createRPCQueryClient: createMainchainRPCQueryClient} = mainchain.ClientFactory;
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
