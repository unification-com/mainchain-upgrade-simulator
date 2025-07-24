import {Logger} from "../libs/logger.mjs";
import {createTmpLocalWallet, deleteTmpLocalWallets, getRandomWallet} from "../libs/wallet_utils.mjs";
import {execa} from "execa";
import {TxFactory} from "../tx/tx_factory.mjs";
import {cosmos} from "@unification-com/fundjs";
const {vote, submitProposal: submitProposalV1} = cosmos.gov.v1.MessageComposer.withTypeUrl;
const {submitProposal: submitProposalV1Beta1} = cosmos.gov.v1beta1.MessageComposer.withTypeUrl;


export class Gov {

    constructor () {}

    static MsgTypes = {
        GOV_SUBMIT_TXT_V1: "gov_submit_txt_v1",
        GOV_SUBMIT_TXT_VBETA1: "gov_submit_txt_v1beta1",
        GOV_VOTE: "google_vote",
    }

    static ValidRandomMsgTypes = [
        Gov.MsgTypes.GOV_VOTE,
    ]

    static randomMsgType() {
        const random = Math.floor(Math.random() * Gov.ValidRandomMsgTypes.length);

        return Gov.ValidRandomMsgTypes[random]
    }

    static getMsg(msgType, params) {
        switch (msgType) {
            default:
                return null
            case Gov.MsgTypes.GOV_VOTE:
                return Gov.msgGovVote(params)
            case Gov.MsgTypes.GOV_SUBMIT_TXT_V1:
                return Gov.msgGovSubmitV1TextProposal(params)
            case Gov.MsgTypes.GOV_SUBMIT_TXT_VBETA1:
                return Gov.msgGovSubmitV1Beta1TextProposal(params)
        }
    }

    static msgGovVote(params) {

        const msg = vote({
            proposalId: params.proposalId,
            voter: params.wallet.meta.wallet_json.address_bech32,
            option: params.option,
            metadata: ""
        })

        let voteOption = "UNSPECIFIED"

        switch(params.option) {
            case 1:
                voteOption = "YES"
                break
            case 2:
                voteOption = "ABSTAIN"
                break
            case 3:
                voteOption = "NO"
                break
            case 4:
                voteOption = "NO_WITH_VETO"
                break
        }

        const memo = `${params.wallet.meta.wallet_json.account} vote ${voteOption} on #${params.proposalId}`

        return {msg, memo}
    }

    static msgGovSubmitV1TextProposal(params) {
        const msg = submitProposalV1({
            authority: "und10d07y265gmmuvt4z0w9aw880jnsr700ja85vs4",
            messages: [],
            title: "testtitle",
            summary: "testsummary",
            initialDeposit: [
                {
                    denom: "nund",
                    amount: "10000000000",
                }
            ],
            proposer: params.fromWallet.meta.wallet_json.address_bech32,
            /** metadata is any arbitrary metadata attached to the proposal. */
            metadata: "",
        })

        const memo = `${params.fromWallet.meta.wallet_json.account} submit gov v1 proposal`

        return {msg, memo}
    }

    static msgGovSubmitV1Beta1TextProposal(params) {
        const msg = submitProposalV1Beta1({
            content: {
                $typeUrl: "/cosmos.gov.v1beta1.TextProposal",
                title: "testtitle",
                description:"testdescription",
            },
            initialDeposit: [
                {
                    denom: "nund",
                    amount: "10000000000",
                }
            ],
            proposer: params.fromWallet.meta.wallet_json.address_bech32,
        })

        const memo = `${params.fromWallet.meta.wallet_json.account} submit gov v1beta1 proposal`

        return {msg, memo}
    }

    static async sendRandomMsg(wallet, openProposal) {
        const rndMsgType = Gov.randomMsgType()
        switch(rndMsgType) {
            case Gov.MsgTypes.GOV_VOTE:
                if(openProposal?.id > 0) {
                    await Gov.voteOnProposal(wallet, openProposal.id, false)
                }
                break
        }
    }

    static async submitUpgradeProposal(fromWallet, config) {

        Logger.info("RUN", "submit upgrade proposal")
        Logger.info("RUN", "create temporary local validator wallet")

        await createTmpLocalWallet(fromWallet, config.dirs.wallets.tmp)

        const proposal = `${config.dirs.generated}/assets/tx_runner/upgrade_proposal.json`

        const {stdout} = await execa`${process.env.UND_BIN} tx gov submit-proposal ${proposal} --from ${fromWallet.meta.wallet_json.account} --node ${config.networks.fund.rpcs[0].rpc} --output json --gas auto --gas-adjustment 1.5 --gas-prices 25.0nund --chain-id ${config.networks.fund.chain_id} --keyring-backend test --yes --home ${config.dirs.wallets.tmp}`;

        const res = JSON.parse(stdout);

        if(res.code === 0) {
            Logger.info("SEND_TX", "net=fund", TxFactory.trimTxHash(res.txhash), "upgrade proposal submitted")
            fromWallet.addSentTx(res.txhash)
        } else {
            Logger.error("SEND_TX", "Submit upgrade proposal failed:", res.raw_log)
        }

        Logger.info("RUN", "delete temporary local validator wallet")
        await deleteTmpLocalWallets(config.dirs.wallets.tmp)

    }

    static async validatorSubmitOrVote(queryClient, validatorWallets) {
        const openProposals = await Gov.getOpenProposals(queryClient)

        // vote or submit
        if(openProposals && openProposals?.proposals.length > 0) {
            //vote
            for(let i = 0; i < validatorWallets.length; i++) {
                await Gov.voteOnProposal(validatorWallets[i], openProposals.proposals[0].id, false)
            }
        } else {
            const fromWallet = getRandomWallet(validatorWallets)
            await Gov.submitNewProposal(fromWallet)
        }
    }

    static async submitNewProposal(wallet) {

        // ToDo - implement v1 proposals. Fo rnow, just use MsgTypes.GOV_SUBMIT_TXT_VBETA1
        const msgType = Gov.MsgTypes.GOV_SUBMIT_TXT_VBETA1

        const {msg, memo} = Gov.getMsg(msgType, {
            fromWallet: wallet
        })

        await TxFactory.sendTx(wallet, [msg], memo, null)
    }

    static async voteOnProposal(wallet, proposalId, forceYes = false) {
        Logger.info("RUN", "governance vote on proposal")

        let voteOption

        // #1 is always the upgrade proposal and should be VOTE_OPTION_YES
        if(forceYes || parseInt(proposalId, 0) === 1) {
            voteOption = cosmos.gov.v1.VoteOption.VOTE_OPTION_YES
        } else {
            // Inclusion of No with Veto votes can be enabled in .env. This will mean
            // nund can be burned from the supply if sufficient wallets vote using
            // the veto option
            const vMax = (process.env.USE_NO_WITH_VETO === true) ? 4 : 3
            voteOption = Math.floor(Math.random() * (vMax) + 1)
        }

        const msgParams = {
            proposalId: proposalId,
            wallet: wallet,
            option: voteOption,
        }
        const {msg, memo} = Gov.getMsg(Gov.MsgTypes.GOV_VOTE, msgParams)

        return await TxFactory.sendTx(wallet, [msg], memo, null)
    }

    static async getOpenProposals(queryClient) {
        return await queryClient.cosmos.gov.v1.proposals({
            proposalStatus: cosmos.gov.v1.ProposalStatus.PROPOSAL_STATUS_VOTING_PERIOD,
            voter: "",
            depositor: "",
        })
    }

}
