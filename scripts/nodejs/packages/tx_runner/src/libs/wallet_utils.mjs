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
