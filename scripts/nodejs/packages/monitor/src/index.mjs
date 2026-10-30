import 'dotenv/config'
import {loadOverview} from "@simulator/shared";
import {UpgradeMonitor} from "./lib/monitor.mjs";

const run = async() => {

    const monitor = new UpgradeMonitor(loadOverview())
    await monitor.run()

}

run()
