import path from "path"
import { fileURLToPath } from 'url';
import {execa} from 'execa';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const rootDir = path.resolve(__dirname, "..", "..", "..", "..", "..")

const stripFormattingRegEx = /[\u001b\u009b][[()#;?]*(?:[0-9]{1,4}(?:;[0-9]{0,4})*)?[0-9A-ORZcf-nqry=><]/g

export const dockerComposeIsUp = async (prefix) => {
    let numContainersUp = 0
    const {stdout} = await execa`docker compose ps --format json`

    if(stdout) {
        const lines = stdout.split("\n")
        for (const line of lines) {
            const n = JSON.parse(line)
            if(n.Name.includes(prefix)) {
                numContainersUp += 1
            }
        }
    }

    return numContainersUp
}

export const getDockerLogs = async (containerName, numLines) => {

    const {stdout} = await execa`docker logs --tail ${numLines} ${containerName}`
    return stdout
}

export const reverseAndStripLogs = (logs) => {
    const lines = logs.split(/\n/).reverse()
    const linesOut = []
    for (const line of lines) {
        linesOut.push(line.replace(stripFormattingRegEx, ''))
    }

    return linesOut
}

export const getTotalTxData = (logs, afterUpgrade = false, forHeight = null) => {
    const lines = reverseAndStripLogs(logs)

    let validRegEx = /num_valid_txs=(\d+)/g;
    let inValidRegEx = /num_invalid_txs=(\d+)/g;
    let lineMatch = "executed block"
    let heightMatch = (forHeight !== null) ? `height=${forHeight}` : ''

    if(afterUpgrade) {
        validRegEx = /num_txs_res=(\d+)/g;
        inValidRegEx = /num_invalid_txs=(\d+)/g;
        lineMatch = "finalized block block_app_hash"
    }

    let totalValidTxs = 0
    let totalInvalidTxs = 0

    for (const line of lines) {
        if(line.includes(lineMatch) && line.includes(heightMatch)) {
            const validMatches = validRegEx.exec(line)
            const inValidMatches = inValidRegEx.exec(line)
            if(validMatches) {
                totalValidTxs += parseInt(validMatches[1], 10)
            }
            if(inValidMatches) {
                totalInvalidTxs += parseInt(inValidMatches[1], 10)
            }
        }
    }

    return [totalValidTxs, totalInvalidTxs]
}

export const getLastHeightFromLogs = (logs) => {
    let lastHeight = 0
    const heightRegEx = /height=(\d+)/g;
    const lines = reverseAndStripLogs(logs)

    for (const line of lines) {
        if(line.includes("committed state")) {
            const matches = heightRegEx.exec(line)
            lastHeight = (matches ? parseInt(matches[1], 10) : 0)
            break
        }
    }

    return lastHeight
}

export const checkNodeUpgradedFromLogs = (logs, upgradeHeight) => {
    //committed state block_app_hash=4A1D8CE0DEED53EB2995EE963AB1EAD32342DD3687989EF86E47985ED876079E height=30
    const upgradeRegEx = `height=${upgradeHeight}`;
    const lines = reverseAndStripLogs(logs)
    for (const line of lines) {
        if (line.includes("committed state") && line.includes(upgradeRegEx)) {
            return true
        }
    }
    return false
}

export const getCurrentSoftwareVersion = (logs) => {
    //ABCI Handshake App Info hash= height=0 module=consensus protocol-version=0 software-version=1.10.1
    let currentVersion = 0
    const versionRegEx = /software-version=(.*)/;
    const lines = reverseAndStripLogs(logs)
    for (const line of lines) {
        if (line.includes("ABCI Handshake App Info hash")) {
            const matches = versionRegEx.exec(line)
            currentVersion = matches[1]
            break
        }
    }
    return currentVersion
}

export const getHermesStarted = (logs) => {
    const lineMatch = "Hermes has started"
    const lines = reverseAndStripLogs(logs)
    for (const line of lines) {
        if (line.includes(lineMatch)) {
            return true
        }
    }
    return false
}

export const getHermesCreateStatus = (logs) => {
    const lines = reverseAndStripLogs(logs)
    for (const line of lines) {
        if (line.includes("wait 10s for networks to begin producing blocks")) {
            return "Test network initialising"
        }
        if(line.includes("Creating new clients")) {
            return "Creating new clients"
        }
        if(line.includes("OpenInitConnection")) {
            return "Init connection"
        }
        if(line.includes("OpenTryConnection")) {
            return "Try connection"
        }
        if(line.includes("OpenAckConnection")) {
            return "Ack connection"
        }
        if(line.includes("OpenConfirmConnection")) {
            return "Confirm connection"
        }
        if(line.includes("OpenInitChannel")) {
            return "Init channel"
        }
        if(line.includes("OpenTryChannel")) {
            return "Try channel"
        }
        if(line.includes("OpenAckChannel")) {
            return "Ack channel"
        }
        if(line.includes("OpenConfirmChannel")) {
            return "Confirm channel"
        }
        if(line.includes("web socket error")) {
            return "Waiting for network upgrade"
        }
        if(
            line.includes("successfully reconnected to WebSocket")
            || line.includes("worker.batch")
            || line.includes("Hermes has started")
        ) {
            return "Running"
        }
    }

    return ""
}
