import {composeContainers} from "@simulator/shared";

// Blocks the chain must reach past the upgrade height before the upgrade counts as healthy.
const MIN_BLOCKS_AFTER_UPGRADE = 10
// A latest block older than this means the chain has stalled.
const MAX_BLOCK_AGE_S = 60
// Recent blocks in which every validator must have signed at least once.
const SIGNING_WINDOW = 10
// CometBFT's flag for a precommit included in a commit (1 = absent, 3 = nil).
const BLOCK_ID_FLAG_COMMIT = 2

// Messages that must have landed successfully on the FUND chain both before the upgrade (old binary) and from the
// upgrade height on (new binary - the upgrade block itself is the first one it runs). `beforeOnly` marks messages
// that only make sense once. RecvPacket/Acknowledgement are Hermes relaying. A failed tx records no message.action,
// so every match counts as a success.
const EXPECTED_MSGS = [
    {type: "/cosmos.gov.v1.MsgSubmitProposal", beforeOnly: true},
    {type: "/cosmos.gov.v1beta1.MsgSubmitProposal"},
    {type: "/cosmos.gov.v1.MsgVote"},
    {type: "/cosmos.bank.v1beta1.MsgSend"},
    {type: "/cosmos.staking.v1beta1.MsgDelegate"},
    {type: "/cosmos.staking.v1beta1.MsgUndelegate"},
    {type: "/cosmos.distribution.v1beta1.MsgWithdrawDelegatorReward"},
    {type: "/mainchain.beacon.v1.MsgRegisterBeacon"},
    {type: "/mainchain.beacon.v1.MsgRecordBeaconTimestamp"},
    {type: "/mainchain.wrkchain.v1.MsgRegisterWrkChain"},
    {type: "/mainchain.wrkchain.v1.MsgRecordWrkChainBlock"},
    {type: "/mainchain.enterprise.v1.MsgUndPurchaseOrder"},
    {type: "/mainchain.enterprise.v1.MsgProcessUndPurchaseOrder"},
    {type: "/mainchain.enterprise.v1.MsgWhitelistAddress"},
    {type: "/mainchain.stream.v1.MsgCreateStream"},
    {type: "/mainchain.stream.v1.MsgClaimStream"},
    {type: "/mainchain.stream.v1.MsgTopUpDeposit"},
    {type: "/mainchain.stream.v1.MsgUpdateFlowRate"},
    {type: "/mainchain.stream.v1.MsgCancelStream"},
    {type: "/ibc.applications.transfer.v1.MsgTransfer"},
    {type: "/ibc.core.channel.v1.MsgRecvPacket"},
    {type: "/ibc.core.channel.v1.MsgAcknowledgement"},
]

const getJson = async (url) => {
    const res = await fetch(url, {signal: AbortSignal.timeout(10_000)})
    if (!res.ok) throw new Error(`HTTP ${res.status} from ${url}`)
    return res.json()
}

// Every check is {name, run}, run resolving to {pass, detail}. All queries go to rpc1 on each chain, which the
// generator always creates with the tx indexer on.
export const buildChecks = (overview) => {

    const upgradeHeight = Number(overview.fund_upgrade_height)
    const plan = overview.fund_upgrade_plan
    const rpc1 = (nodes) => nodes.find((n) => n.name === "rpc1")
    const fundRpc = `http://localhost:${rpc1(overview.fund_nodes).rpc_port}`
    const fundRest = `http://localhost:${rpc1(overview.fund_nodes).rest_port}`
    const gaiadRest = `http://localhost:${rpc1(overview.gaiad_nodes).rest_port}`
    const numValidators = overview.fund_nodes.filter((n) => n.type === "validator").length

    const countMsgs = async (type, heightOp) => {
        const query = encodeURIComponent(`message.action='${type}' AND tx.height${heightOp}${upgradeHeight}`)
        return Number((await getJson(`${fundRest}/cosmos/tx/v1beta1/txs?query=${query}&limit=1`)).total)
    }

    const openTransferChannels = async (rest) => (await getJson(`${rest}/ibc/core/channel/v1/channels`)).channels
        .filter((c) => c.port_id === "transfer" && c.state === "STATE_OPEN")
        .map((c) => c.channel_id)

    return [
        {
            name: "upgrade applied",
            run: async () => {
                const {height} = await getJson(`${fundRest}/cosmos/upgrade/v1beta1/applied_plan/${plan}`)
                return {pass: Number(height) === upgradeHeight, detail: `${plan} applied at height ${height} (expected ${upgradeHeight})`}
            },
        },
        {
            name: "chain producing blocks",
            run: async () => {
                const {sync_info: s} = (await getJson(`${fundRpc}/status`)).result
                const height = Number(s.latest_block_height)
                const age = Math.round((Date.now() - Date.parse(s.latest_block_time)) / 1000)
                const pass = height >= upgradeHeight + MIN_BLOCKS_AFTER_UPGRADE && age <= MAX_BLOCK_AGE_S && !s.catching_up
                const catchingUp = s.catching_up ? ", rpc1 still catching up" : ""
                return {pass, detail: `height ${height} (need ${upgradeHeight + MIN_BLOCKS_AFTER_UPGRADE}+), last block ${age} s ago${catchingUp}`}
            },
        },
        {
            name: "containers running",
            run: async () => {
                const expected = [...overview.fund_nodes, ...overview.gaiad_nodes, overview.hermes].map((n) => n.docker_container)
                const running = new Set((await composeContainers()).filter((c) => c.State === "running").map((c) => c.Name))
                const down = expected.filter((name) => !running.has(name))
                return {pass: down.length === 0, detail: down.length ? `not running: ${down.join(", ")}` : `${expected.length} of ${expected.length}`}
            },
        },
        {
            // a window, not one block: a commit only needs 2/3 of the precommits, so a live validator is often missing
            // from any single one
            name: "validators signing",
            run: async () => {
                const latest = Number((await getJson(`${fundRpc}/status`)).result.sync_info.latest_block_height)
                const heights = Array.from({length: SIGNING_WINDOW}, (_, i) => latest - i).filter((h) => h > 0)
                const commits = await Promise.all(heights.map((h) => getJson(`${fundRpc}/commit?height=${h}`)))
                const signers = new Set(commits
                    .flatMap((c) => c.result.signed_header.commit.signatures)
                    .filter((sig) => sig.block_id_flag === BLOCK_ID_FLAG_COMMIT)
                    .map((sig) => sig.validator_address))
                return {pass: signers.size >= numValidators, detail: `${signers.size} of ${numValidators} validators signed in blocks ${heights.at(-1)}-${latest}`}
            },
        },
        {
            name: "IBC transfer channel open",
            run: async () => {
                const [fund, gaiad] = await Promise.all([openTransferChannels(fundRest), openTransferChannels(gaiadRest)])
                const list = (ids) => ids.join(", ") || "none"
                return {pass: fund.length > 0 && gaiad.length > 0, detail: `FUND ${list(fund)} / Gaia ${list(gaiad)}`}
            },
        },
        ...EXPECTED_MSGS.map(({type, beforeOnly}) => ({
            name: type,
            run: async () => {
                const [before, after] = await Promise.all([countMsgs(type, "<"), countMsgs(type, ">=")])
                const pass = before > 0 && (beforeOnly || after > 0)
                return {pass, detail: `successful txs: ${before} before, ${after} from the upgrade on${beforeOnly ? " (only needed before)" : ""}`}
            },
        })),
    ]
}
