import 'dotenv/config'
import fs from 'fs'
import path from "path"
import {generatedDir} from "@simulator/shared";
import {UpgradeMonitor} from "./lib/monitor.mjs";

const run = async() => {

    const netOverviewPath = path.resolve(generatedDir(), "network", "overview.json")
    const netOverviewContents = fs.readFileSync(netOverviewPath, 'utf8')
    const netOverview = JSON.parse(netOverviewContents)

    const monitor = new UpgradeMonitor(netOverview)
    await monitor.run()

}

run()
