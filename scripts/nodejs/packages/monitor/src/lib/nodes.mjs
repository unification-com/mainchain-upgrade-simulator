import {sleep} from "@simulator/shared";
import {checkNodeUpgradedFromLogs, getCurrentSoftwareVersion, getDockerLogs, getLastHeightFromLogs} from "./docker.mjs";

// The FUND nodes' table rows - each node's height and und version, read from its container's log - and the upgrade's
// progress across them.
export class NodeTracker {

    rows
    numUpgraded = 0
    status = "NOT UPGRADED \u{1F634}"
    #upgraded = false
    #upgradeHeight

    constructor(rows, upgradeHeight) {
        this.rows = rows
        this.#upgradeHeight = upgradeHeight
    }

    get count() {
        return Object.keys(this.rows).length
    }

    // Reads each node's height, and its version once per side of the upgrade.
    async refresh(currentHeight) {
        for (const row of Object.values(this.rows)) {
            const logs = await getDockerLogs(row.container, 1000)
            row.height = getLastHeightFromLogs(logs)
            const beforeUpgrade = currentHeight < this.#upgradeHeight - 1
            const afterUpgrade = currentHeight >= this.#upgradeHeight
            if (row.und_version === null && (beforeUpgrade || afterUpgrade)) {
                row.und_version = getCurrentSoftwareVersion(logs)
            }
        }
    }

    // From the block before the upgrade until every node has restarted on the upgrade binary: marks each node as it
    // upgrades, redrawing the screen every second.
    async watchUpgrade(redraw) {
        while (!this.#upgraded) {
            for (const row of Object.values(this.rows)) {
                if (row.upgraded) {
                    continue
                }
                row.und_version = null
                const logs = await getDockerLogs(row.container, 200)
                if (checkNodeUpgradedFromLogs(logs, this.#upgradeHeight)) {
                    row.upgraded = true
                    row.up_time = new Date().toLocaleTimeString("en-GB")
                    this.numUpgraded += 1
                } else {
                    row.und_version = "upgrading"
                }
            }
            redraw()
            if (this.numUpgraded >= this.count) {
                this.status = "UPGRADE SUCCESSFUL! \u{1F60A}"
                this.#upgraded = true
            } else {
                this.status = "NETWORK UPGRADE IN PROGRESS \u{1F62C}"
            }
            await sleep(1000)
        }
    }
}
