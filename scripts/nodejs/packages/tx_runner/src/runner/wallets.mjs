import {createWallets} from "../libs/wallet_utils.mjs";
import {isIdxOdd} from "../libs/utils.mjs";

// Every generated wallet of both chains, selected by type (the wallet files' wallet_type).
export class WalletSet {

    #wallets

    constructor(wallets) {
        this.#wallets = wallets
    }

    static async create(config) {
        return new WalletSet({fund: await createWallets(config, "fund"), gaiad: await createWallets(config, "gaiad")})
    }

    all(network) {
        return this.#wallets[network]
    }

    // a wallet by its account name, e.g. test1
    byName(network, account) {
        return this.#wallets[network].find((w) => w.meta.wallet_json.account === account)
    }

    // the network's wallets of the given types, grouped by type in the order given
    byType(network, ...types) {
        return types.flatMap((type) => this.#wallets[network].filter((w) => w.meta.wallet_json.wallet_type === type))
    }

    // Half the BEACON and WRKChain owners buy their eFUND straight away and half from the upgrade height, so both
    // binaries see purchase orders raised, accepted and spent.
    setEFundActionBlocks(upgradeHeight) {
        for (const type of ["beacon", "wrkchain"]) {
            this.byType("fund", type).forEach((w, i) => w.setEFundActionFromBlock(isIdxOdd(i) ? upgradeHeight : 0))
        }
    }
}
