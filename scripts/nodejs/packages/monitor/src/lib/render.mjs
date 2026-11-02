import {bold} from 'console-log-colors';
import {Table} from 'console-table-printer'
import {OPT_KEYS} from "./display.mjs";
import {formatNumber, NOT_EXIST} from "./queries.mjs";

// Everything the monitor prints. Each function draws from the monitor's state; nothing here queries or changes it.

const channelState = (state) => (state === "UNRECOGNIZED" ? "" : `(${state})`)

function printNodeTable(nodes) {
    const p = new Table({
        columns: [
            {name: 'node', alignment: 'left', title: "Node"},
            {name: 'container', alignment: 'left', title: "Docker Container"},
            {name: 'height', alignment: 'center', title: "Height"},
            {name: 'upgraded', alignment: 'center', title: "Upgraded"},
            {name: 'up_time', alignment: 'center', title: "Upgrade Time"},
            {name: 'und_version', alignment: 'center', title: "und Version"},
        ],
        charLength: {"\u{274C}": 2, "\u{2705}": 2},
    })
    for (const [name, row] of Object.entries(nodes.rows)) {
        p.addRow({
            node: name,
            container: row.container,
            height: row.height,
            upgraded: (row.upgraded ? "\u{2705}" : "\u{274C}"),
            up_time: row.up_time,
            und_version: row.und_version,
        })
    }
    p.printTable()
}

function printOptions() {
    for (const value of Object.values(OPT_KEYS)) {
        process.stdout.write(`${value.key}: ${value.opt}, `);
    }
}

function printOverview(s) {
    console.log("-- Overview --")
    console.log("")
    console.log(`${bold("Num. Stuffs")} :`, `${bold("BEACONS")} =`, s.numBeacons, `| ${bold("WrkChains")} =`, s.numWrkchains, `| ${bold("Active Streams")} =`, s.numActiveStreams)
    console.log(`${bold("eFUND")}       :`, `${bold("Locked")} =`, s.efundLocked, `| ${bold("Spent")} =`, s.efundSpent, `| ${bold("Num POs")} =`, s.purchaseOrders.length)
    console.log(`${bold("FUND Supply")} :`, s.fundSupply, `| ${bold("FUND on IBC")} = ${s.fundOnIbc}`)
    console.log(`${bold("IBC")}         : ${bold("Hermes")} = ${s.hermesStatus} | ${bold("FUND")} = ${s.fundIbcChannel} ${channelState(s.fundIbcChannelState)} | ${bold("gaiad")} = ${s.gaiadIbcChannel} ${channelState(s.gaiadIbcChannelState)}`)
    // process.stdout on the last line, so no trailing newline scrolls the screen
    process.stdout.write(`${bold("Staking")}     : ${bold("Bonded")} = ${s.bondedTokens} | ${bold("Unbonding")} = ${s.notBondedTokens} | ${bold("Community Pool")} = ${s.communityPool}`);
}

function printEfund(s) {
    console.log("-- eFUND --")
    console.log("")
    console.log(`${bold("eFUND Locked")}  :`, s.efundLocked)
    console.log(`${bold("eFUND Spent")}   :`, s.efundSpent)
    console.log(`${bold("Raised POs")}    :`, s.raisedPos)
    console.log(`${bold("Accepted POs")}  :`, s.acceptedPos)
    console.log(`${bold("Completed POs")} :`, s.completedPos)
}

function printIbc(s) {
    console.log("-- IBC --")
    console.log("")
    console.log(`${bold("Hermes Status")}   :`, s.hermesStatus)
    console.log(`${bold("FUND Channel")}    :`, s.fundIbcChannel, channelState(s.fundIbcChannelState))
    console.log(`${bold("Gaiad Channel")}   :`, s.gaiadIbcChannel, channelState(s.gaiadIbcChannelState))
    console.log(`${bold("IBC Denom")}       : ${s.ibcDenom}`)
    process.stdout.write(`${bold("Supply on Gaiad")} : ${s.fundDecOnIbc} FUND`);
}

function printBeacons(s) {
    console.log("-- BEACONS --")
    console.log("")
    for (const b of s.beacons) {
        console.log(`${bold(b.moniker)} :`, `Num Timestamps = ${b.last_timestamp_id}`)
    }
}

function printWrkchains(s) {
    console.log("-- WrkChains --")
    console.log("")
    for (const w of s.wrkchains) {
        console.log(`${bold(w.moniker)} :`, `Last Block = ${w.lastblock}`)
    }
}

function streamLine(stream) {
    if (stream === NOT_EXIST) {
        return "Cancelled"
    }
    const deposit = formatNumber(stream.stream.deposit.amount / (10 ** 9))
    const lastClaim = new Date(stream.stream.last_outflow_time).toLocaleTimeString("en-GB")
    const depositZeroTime = new Date(stream.stream.deposit_zero_time).toLocaleTimeString("en-GB")
    return `Deposit=${deposit}, Flow=${stream.stream.flow_rate}nund/s, Zero=${depositZeroTime}, Last claim=${lastClaim}`
}

function printStreams(s) {
    console.log("-- Payment Streams --")
    console.log("")
    s.paymentStreams.forEach((stream, i) => {
        const line = `${bold(`Stream #${i + 1}`)} : ${streamLine(stream)}`
        if (i + 1 < s.paymentStreams.length) {
            console.log(line)
        } else {
            process.stdout.write(line);
        }
    })
}

const views = {
    [OPT_KEYS.P.key]: printStreams,
    [OPT_KEYS.E.key]: printEfund,
    [OPT_KEYS.I.key]: printIbc,
    [OPT_KEYS.B.key]: printBeacons,
    [OPT_KEYS.W.key]: printWrkchains,
    [OPT_KEYS.O.key]: printOverview,
}

// The whole screen: the upgrade's progress, the node table, the key help, this block's txs and the selected view.
export function render(overview, nodes, state, display) {
    console.clear()
    console.log(`${bold("Upgrade Plan")}   : ${overview.genesis_version} -> ${overview.upgrade_version} | ${overview.fund_upgrade_plan} at Height ${overview.fund_upgrade_height}`)
    console.log(`${bold("Upgrade Status")} : ${nodes.status} (${nodes.numUpgraded} / ${nodes.count} upgraded) | ${bold("Proposal Status")}: ${state.proposalStatus}`)
    console.log("")
    printNodeTable(nodes)
    console.log("")
    printOptions()
    console.log("")
    console.log("")
    const now = new Date().toLocaleTimeString("en-GB")
    console.log(`${bold("Time :")} ${now} | ${bold("Txs in block")} ${bold(state.currentBlockHeight)} :`, state.blockValidTxs, " | ", `${bold("Total Txs")} :`, state.totalValidTxs, `| ${bold("Cycle")}: ${(display.cycling) ? "on" : "off"}`)
    console.log("")
    const printView = views[display.view] ?? printOverview
    printView(state)
}

export function renderWaitForDocker(up, total) {
    console.clear()
    console.log("waiting for docker up (press q to quit)")
    console.log(`Up: ${up} / ${total}`)
}

export function renderWaitForRpc() {
    console.clear()
    console.log("waiting for FUND RPC up (press q to quit)")
}
