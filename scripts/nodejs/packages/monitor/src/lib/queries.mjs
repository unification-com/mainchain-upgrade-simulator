import {sha256} from '@noble/hashes/sha2'
import {bytesToHex} from '@noble/hashes/utils'
import {getDockerLogs, getHermesCreateStatus} from "./docker.mjs";

// The REST queries behind the monitor's numbers. Each returns the state fields it refreshes, or {} when the node cannot
// answer (e.g. mid-upgrade), so the screen keeps the last values it had.

export const NOT_EXIST = "not_exist"

const NUND_PER_FUND = 10 ** 9

export const formatNumber = (n) => new Intl.NumberFormat("en-GB", {}).format(n)

const getJson = async (url) => (await fetch(url)).json()

const attempt = async (query) => {
    try {
        return await query()
    } catch (e) {
        return {}
    }
}

// the FUND value of an {amount: {amount}} response - a supply or an eFUND total
const fundAmount = async (url) => {
    const data = await getJson(url)
    return data?.amount?.amount ? parseInt(data.amount.amount, 10) / NUND_PER_FUND : 0
}

export const fundSupply = (fund) => attempt(async () => ({
    fundSupply: formatNumber(await fundAmount(`${fund.rest}/cosmos/bank/v1beta1/supply/by_denom?denom=nund`)),
}))

export const efundLocked = (fund) => attempt(async () => ({
    efundLocked: formatNumber(await fundAmount(`${fund.rest}/mainchain/enterprise/v1/locked`)),
}))

export const efundSpent = (fund) => attempt(async () => ({
    efundSpent: formatNumber(await fundAmount(`${fund.rest}/mainchain/enterprise/v1/total_spent`)),
}))

// FUND that has crossed to the Gaia chain, as the IBC denom it has there
export const fundOnIbc = (gaiad, ibcDenom) => attempt(async () => {
    const amount = await fundAmount(`${gaiad.rest}/cosmos/bank/v1beta1/supply/by_denom?denom=${ibcDenom}`)
    return {fundOnIbc: formatNumber(Math.round(amount)), fundDecOnIbc: formatNumber(amount)}
})

export const beacons = (fund) => attempt(async () => {
    const data = await getJson(`${fund.rest}/mainchain/beacon/v1/beacons`)
    return data?.beacons ? {numBeacons: data.beacons.length, beacons: data.beacons} : {}
})

export const wrkchains = (fund) => attempt(async () => {
    const data = await getJson(`${fund.rest}/mainchain/wrkchain/v1/wrkchains`)
    return data?.wrkchains ? {numWrkchains: data.wrkchains.length, wrkchains: data.wrkchains} : {}
})

// Each chain's first channel and its state. Once both channel IDs are known, also nund's IBC denom on the Gaia chain:
// the hash of its trace through the Gaia side's channel.
export const ibcChannels = (fund, gaiad, state) => attempt(async () => {
    const [fundData, gaiadData] = await Promise.all([
        getJson(`${fund.rest}/ibc/core/channel/v1/channels`),
        getJson(`${gaiad.rest}/ibc/core/channel/v1/channels`),
    ])
    if (!fundData.channels || !gaiadData.channels) {
        return {}
    }
    const out = {}
    if (fundData.channels.length > 0) {
        out.fundIbcChannel = fundData.channels[0].channel_id
        out.fundIbcChannelState = fundData.channels[0].state.replace("STATE_", "")
    }
    if (gaiadData.channels.length > 0) {
        out.gaiadIbcChannel = gaiadData.channels[0].channel_id
        out.gaiadIbcChannelState = gaiadData.channels[0].state.replace("STATE_", "")
    }
    const fundChannel = out.fundIbcChannel ?? state.fundIbcChannel
    const gaiadChannel = out.gaiadIbcChannel ?? state.gaiadIbcChannel
    if (fundChannel !== null && gaiadChannel !== null && state.ibcDenom === "") {
        out.ibcDenom = `ibc/${bytesToHex(sha256(`transfer/${gaiadChannel}/nund`)).toUpperCase()}`
    }
    return out
})

// the upgrade proposal is always the chain's first
export const proposalStatus = (fund) => attempt(async () => {
    const data = await getJson(`${fund.rest}/cosmos/gov/v1beta1/proposals/1`)
    return {proposalStatus: data.proposal.status.replace("PROPOSAL_STATUS_", "")}
})

export const hermesStatus = (container) => attempt(async () => ({
    hermesStatus: getHermesCreateStatus(await getDockerLogs(container, 100)),
}))

export const communityPool = (fund) => attempt(async () => {
    const data = await getJson(`${fund.rest}/cosmos/distribution/v1beta1/community_pool`)
    let communityPool = 0
    if (data?.pool?.length > 0) {
        const nund = parseInt(data.pool[0].amount, 10)
        communityPool = nund > 100000000 ? formatNumber(nund / NUND_PER_FUND) : "< 0.01"
    }
    return {communityPool}
})

export const stakingPool = (fund) => attempt(async () => {
    const data = await getJson(`${fund.rest}/cosmos/staking/v1beta1/pool`)
    const wholeFund = (nund) => (nund > 0 ? formatNumber(Math.round(nund / NUND_PER_FUND)) : 0)
    if (!data?.pool?.bonded_tokens) {
        return {bondedTokens: 0, notBondedTokens: 0}
    }
    return {
        bondedTokens: wholeFund(parseInt(data.pool.bonded_tokens, 10)),
        notBondedTokens: wholeFund(parseInt(data.pool.not_bonded_tokens, 10)),
    }
})

// Every stream on chain, from the list route - the same before and after the upgrade, whereas the single-stream
// route gained a {denom} segment in vaxildan (and 501s in the old shape). Pairs are remembered once seen, so a
// cancelled stream still shows as Cancelled.
export const paymentStreams = (fund, knownPairs) => attempt(async () => {
    const data = await getJson(`${fund.rest}/mainchain/stream/v1/streams/all?pagination.limit=1000`)
    const current = new Map()
    const streamPairs = [...knownPairs]
    for (const s of data?.streams ?? []) {
        const pair = `${s.sender}_${s.receiver}_${s.stream?.deposit?.denom}`
        current.set(pair, s)
        if (!streamPairs.includes(pair)) {
            streamPairs.push(pair)
        }
    }
    return {
        streamPairs,
        paymentStreams: streamPairs.map((pair) => current.get(pair) ?? NOT_EXIST),
        numActiveStreams: current.size,
    }
})

export const purchaseOrders = (fund) => attempt(async () => {
    const data = await getJson(`${fund.rest}/mainchain/enterprise/v1/pos`)
    const orders = data?.purchase_orders ?? []
    const count = (status) => orders.filter((po) => po.status === status).length
    return {
        purchaseOrders: orders,
        raisedPos: count("STATUS_RAISED"),
        acceptedPos: count("STATUS_ACCEPTED"),
        completedPos: count("STATUS_COMPLETED"),
    }
})
