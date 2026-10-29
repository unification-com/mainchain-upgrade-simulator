import fs from 'fs'
import path from 'path'
import {fileURLToPath} from 'url'
import {execa} from 'execa';

export const sleep = (delay) => new Promise((resolve) => setTimeout(resolve, delay))

// true when something is listening on 127.0.0.1:port (used to wait for node RPC ports)
export const portIsOpen = async(port) => {

    try {
        await execa`nc -z 127.0.0.1 ${port.toString()}`
        return true
    } catch {
        return false
    }

}

// The simulator repo root: the nearest ancestor of this file holding example.config.json. Found by walking up
// rather than a fixed number of "..", so moving packages around the workspace cannot break it.
const findRepoRoot = (start) => {
    let dir = start
    while (!fs.existsSync(path.join(dir, 'example.config.json'))) {
        const parent = path.dirname(dir)
        if (parent === dir) {
            throw new Error('cannot find the simulator repo root (no example.config.json above ' + start + ')')
        }
        dir = parent
    }
    return dir
}

export const repoRoot = findRepoRoot(path.dirname(fileURLToPath(import.meta.url)))

// The generator's output directory: GENERATED_DIR if set (relative to the working directory), otherwise the
// repo's own generated/ - so no .env is needed for the usual layout.
export const generatedDir = () => (process.env.GENERATED_DIR ? path.resolve(process.env.GENERATED_DIR) : path.join(repoRoot, 'generated'))
