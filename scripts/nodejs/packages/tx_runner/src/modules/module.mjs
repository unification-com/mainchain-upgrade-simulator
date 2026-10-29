
export class Module {

    constructor() {}

    static MsgModules = {
        BANK: "bank",
        STAKE: "staking",
        GOV: "gov",
    }

    static async getParams(queryClient, pkg, module, ver){
        return await queryClient[pkg][module][ver].params()
    }

    static randomModule(includeGovernance = false) {
        const validModules = [
            Module.MsgModules.BANK,
            Module.MsgModules.STAKE
        ]

        if(includeGovernance) {
            validModules.push(Module.MsgModules.GOV)
        }

        const random = Math.floor(Math.random() * validModules.length);

        return validModules[random]
    }

}
