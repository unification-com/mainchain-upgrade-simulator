import fs from "fs-extra";
import path from "path";
import {Wallet} from "../wallet/wallet.mjs";

export const createWallets = async (config, network) => {
    const srcDir = config.config.dirs.wallets[network]
    const networkConfig = config.config.networks[network]
    const walletFiles = await fs.readdir(srcDir)

    const wallets = []

    for(let i = 0; i < walletFiles.length; i++) {
        const walletFile = walletFiles[i]
        const w = await fs.readFile(path.resolve(srcDir, walletFile))
        const wJson = JSON.parse(w)
        wJson.bech32_prefix = networkConfig.chain.bech32_prefix
        wJson.slip44 = networkConfig.chain.slip44
        wJson.srcDir = srcDir

        const wallet = await Wallet.createWallet(config, network, wJson)

        wallets.push(wallet)
    }

    return wallets
}

export const createTmpLocalWallet = async (wallet, tmpDir) => {

    const krBackend = path.resolve(tmpDir, "keyring-test")
    await fs.mkdirs(krBackend)
    const c = wallet.meta.wallet_json.key_files.contents
    const f1 = wallet.meta.wallet_json.key_files.filename1
    const f2 = wallet.meta.wallet_json.key_files.filename2

    await fs.writeFileSync(path.resolve(krBackend, f1), c);
    await fs.writeFileSync(path.resolve(krBackend, f2), c);
}

export const deleteTmpLocalWallets = async(tmpDir) => {
    await fs.removeSync(tmpDir)
}

export const getRandomWallet = (wallets) => {
    const rndIdx = Math.floor(Math.random() * wallets.length);
    return wallets[rndIdx];
}

export const getRandomWalletNotThis = (wallets, thisIdx) => {
    let rndIdx = thisIdx
    while(rndIdx === thisIdx) {
        rndIdx = Math.floor(Math.random() * wallets.length);
    }
    return wallets[rndIdx];
}

export const getWalletByAddress = (wallets, address) => {
    for(let i = 0; i < wallets.length; i++) {
        const w = wallets[i]
        if(w.meta.wallet_json.address_bech32 === address) {
            return w
        }
    }

    return null
}
