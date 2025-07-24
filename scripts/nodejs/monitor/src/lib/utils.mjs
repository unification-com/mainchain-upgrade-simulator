import {execa} from 'execa';

export const sleep = (delay) => new Promise((resolve) => setTimeout(resolve, delay))

export const getNetworkInfo = (netOverview) => {

    const containers = {}
    const queryNodes = {
        fund: {
            rpc: "",
            ws: "",
            grpc: "",
            rest: "",
            rpc_port: "",
            grpc_port: "",
            rest_port: "",
            container: "",
        },
        gaiad: {
            rpc: "",
            ws: "",
            grpc: "",
            rest: "",
            rpc_port: "",
            grpc_port: "",
            rest_port: "",
            container: "",
        }
    }
    for(let i = 0; i < netOverview.fund_nodes.length; i++){
        const node = netOverview.fund_nodes[i]
        containers[node.name] = {
            container: node.docker_container,
            height: 0,
            upgraded: false,
            up_time: 0,
            und_version: null,
        }

        if(node.name === "rpc1") {
            queryNodes.fund.container = node.docker_container
            queryNodes.fund.rpc = `http://localhost:${node.rpc_port}`
            queryNodes.fund.ws = `ws://localhost:${node.rpc_port}/websocket`
            queryNodes.fund.grpc = `http://localhost:${node.grpc_port}`
            queryNodes.fund.rest = `http://localhost:${node.rest_port}`
            queryNodes.fund.rpc_port = node.rpc_port
            queryNodes.fund.grpc_port = node.grpc_port
            queryNodes.fund.rest_port = node.rest_port
        }
    }

    for(let i = 0; i < netOverview.gaiad_nodes.length; i++) {
        const node = netOverview.gaiad_nodes[i]
        if(node.name === "rpc1") {
            queryNodes.gaiad.container = node.docker_container
            queryNodes.gaiad.rpc = `http://localhost:${node.rpc_port}`
            queryNodes.gaiad.ws = `ws://localhost:${node.rpc_port}/websocket`
            queryNodes.gaiad.grpc = `http://localhost:${node.grpc_port}`
            queryNodes.gaiad.rest = `http://localhost:${node.rest_port}`
            queryNodes.gaiad.rpc_port = node.rpc_port
            queryNodes.gaiad.grpc_port = node.grpc_port
            queryNodes.gaiad.rest_port = node.rest_port
        }
    }

    return [containers, queryNodes]
}

export const rpcIsUp = async(rpcPort) => {

    try {
        await execa`nc -z 127.0.0.1 ${rpcPort.toString()}`
        return true
    } catch {
        return false
    }

}
