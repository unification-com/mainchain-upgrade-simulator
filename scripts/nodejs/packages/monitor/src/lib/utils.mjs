import {endpoints} from "@simulator/shared";

// The monitor's view of the network: a table row per FUND node, and each chain's first RPC node to query.
export const getNetworkInfo = (netOverview) => {
    const containers = {}
    for (const node of netOverview.fund_nodes) {
        containers[node.name] = {
            container: node.docker_container,
            height: 0,
            upgraded: false,
            up_time: 0,
            und_version: null,
        }
    }

    const rpc1 = (nodes) => {
        const node = nodes.find((n) => n.name === "rpc1")
        return {...endpoints(node), rpc_port: node.rpc_port, container: node.docker_container}
    }

    return [containers, {fund: rpc1(netOverview.fund_nodes), gaiad: rpc1(netOverview.gaiad_nodes)}]
}
