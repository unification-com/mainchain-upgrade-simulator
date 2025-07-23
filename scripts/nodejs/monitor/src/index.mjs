import 'dotenv/config'
import fs from 'fs'
import path from "path"
import {UpgradeMonitor} from "./lib/monitor.mjs";

const run = async() => {

    const netOverviewPath = path.resolve(process.env.GENERATED_DIR, "network", "overview.json")
    const netOverviewContents = fs.readFileSync(netOverviewPath, 'utf8')
    const netOverview = JSON.parse(netOverviewContents)

    const monitor = new UpgradeMonitor(netOverview)
    await monitor.run()

}

run()
