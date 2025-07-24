import {DirectSecp256k1HdWallet} from '@cosmjs/proto-signing';
import {makeHdPath} from 'cosmjs-utils';

export const getOfflineSignerProtoAccNum = async ({
                                                      mnemonic,
                                                      chain,
                                                      account = 0,
                                                  }) => {
    try {
        const {
            bech32_prefix,
            slip44
        } = chain;
        return await DirectSecp256k1HdWallet.fromMnemonic(mnemonic, {
            prefix: bech32_prefix,
            hdPaths: [makeHdPath(slip44, account)]
        });
    } catch (e) {
        console.log('bad mnemonic');
    }
};
