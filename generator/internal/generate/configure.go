package generate

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/unification-com/mainchain-upgrade-simulator/generator/internal/config"
	"github.com/unification-com/mainchain-upgrade-simulator/generator/internal/network"
	"github.com/unification-com/mainchain-upgrade-simulator/generator/internal/render"
	"github.com/unification-com/mainchain-upgrade-simulator/generator/internal/tomledit"
	"github.com/unification-com/mainchain-upgrade-simulator/generator/internal/wallet"
)

// peers is a node's persistent peers and seeds: every other node of its chain, with seeds listed separately, in
// name order.
func peers(all []network.Node, self network.Node) (persistent, seeds string) {
	var p, s []string
	for _, n := range sortedByName(all) {
		switch {
		case n.Name == self.Name:
		case n.Type == network.Seed:
			s = append(s, n.P2PAddr)
		default:
			p = append(p, n.P2PAddr)
		}
	}
	return strings.Join(p, ","), strings.Join(s, ",")
}

func (g *generator) configureNodes() error {
	for _, s := range []*side{g.fund, g.ibc} {
		for _, n := range s.all {
			if err := g.configureNode(s, n); err != nil {
				return fmt.Errorf("%s: %w", n.Name, err)
			}
		}
	}
	return nil
}

func (g *generator) configureNode(s *side, n network.Node) error {
	persistent, seeds := peers(s.all, n)
	conf := filepath.Join(n.Home, "config")
	isRPC := n.Type == network.RPC

	p2p := []tomledit.Setting{
		{Section: "p2p", Key: "laddr", Value: fmt.Sprintf("tcp://0.0.0.0:%d", n.P2PPort)},
		{Section: "p2p", Key: "persistent_peers", Value: persistent},
		{Section: "p2p", Key: "seeds", Value: seeds},
		// peers are on private container addresses, which a strict address book rejects
		{Section: "p2p", Key: "addr_book_strict", Value: false},
	}
	if n.Type == network.Seed {
		p2p = append(p2p, tomledit.Setting{Section: "p2p", Key: "seed_mode", Value: true})
	}
	if err := tomledit.Edit(filepath.Join(conf, "config.toml"), p2p...); err != nil {
		return err
	}

	// RPC nodes keep enough history for queries across a whole rehearsal; the rest prune hard to stay small
	keepRecent := "100"
	if isRPC {
		keepRecent = "363000"
	}
	app := []tomledit.Setting{
		{Key: "minimum-gas-prices", Value: s.minGasPrice},
		{Key: "pruning", Value: "custom"},
		{Key: "pruning-keep-recent", Value: keepRecent},
		{Key: "pruning-interval", Value: "100"},
		{Section: "grpc", Key: "enable", Value: true},
	}
	if isRPC {
		app = append(app,
			tomledit.Setting{Section: "api", Key: "enable", Value: true},
			tomledit.Setting{Section: "api", Key: "swagger", Value: true})
	}
	if err := tomledit.Edit(filepath.Join(conf, "app.toml"), app...); err != nil {
		return err
	}

	if !isRPC {
		return nil
	}
	// nginx in the RPC node's container publishes its RPC, REST and gRPC on the node's own host ports
	return render.File(filepath.Join(g.p.TemplatesConfigs, "nginx.conf"), filepath.Join(n.Home, "nginx.conf"), map[string]string{
		"RPC_PORT": fmt.Sprint(n.RPCPort), "REST_PORT": fmt.Sprint(n.RESTPort), "GRPC_PORT": fmt.Sprint(n.GRPCPort),
	})
}

// configureHermes points the relayer at each chain's first RPC node.
func (g *generator) configureHermes() error {
	fund, err := g.fund.node("rpc1")
	if err != nil {
		return err
	}
	ibc, err := g.ibc.node("rpc1")
	if err != nil {
		return err
	}
	if err := os.MkdirAll(g.p.Hermes, 0o755); err != nil {
		return err
	}
	return render.File(filepath.Join(g.p.TemplatesConfigs, "hermes_config.toml"), filepath.Join(g.p.Hermes, "config.toml"), map[string]string{
		"FUND_CHAIN_ID":  g.fund.chainID,
		"FUND_RPC":       fmt.Sprintf("%s:%d", fund.IP, fund.RPCPort),
		"FUND_GRPC":      fmt.Sprintf("%s:%d", fund.IP, fund.GRPCPort),
		"IBC_CHAIN_ID":   g.ibc.chainID,
		"IBC_GAIAD_RPC":  fmt.Sprintf("%s:%d", ibc.IP, ibc.RPCPort),
		"IBC_GAIAD_GRPC": fmt.Sprintf("%s:%d", ibc.IP, ibc.GRPCPort),
	})
}

// customTxsFile is custom_txs.json: the transactions the tx runner sends at set heights. Each carries a label - a
// gov proposal's metadata, a msg tx's memo - so the tx runner and verify can recognise it on chain.
type customTxsFile struct {
	Gov  []customGovTx `json:"gov"`
	Msgs []customMsgTx `json:"msgs"`
}

// customGovTx is a proposal: when to submit it, how the validators vote on it, and the proposal file itself.
type customGovTx struct {
	SubmitHeight int64           `json:"submit_height"`
	Passes       string          `json:"passes"`
	Proposal     govProposalFile `json:"proposal"`
}

// govProposalFile is the proposal file `tx gov submit-proposal` reads.
type govProposalFile struct {
	Messages []json.RawMessage `json:"messages"`
	Metadata string            `json:"metadata"`
	Deposit  string            `json:"deposit"`
	Title    string            `json:"title"`
	Summary  string            `json:"summary"`
}

// customMsgTx is a transaction a generated wallet signs and broadcasts.
type customMsgTx struct {
	SubmitHeight int64      `json:"submit_height"`
	Succeeds     string     `json:"succeeds"`
	From         string     `json:"from"`
	Address      string     `json:"address"`
	Tx           unsignedTx `json:"tx"`
}

// unsignedTx is a transaction for `tx sign`, with only the fields every supported und version's decoder accepts (a
// newer CLI's --generate-only output adds fields an older one rejects).
type unsignedTx struct {
	Body struct {
		Messages []json.RawMessage `json:"messages"`
		Memo     string            `json:"memo"`
	} `json:"body"`
	AuthInfo struct {
		Fee struct {
			Amount   []coin `json:"amount"`
			GasLimit uint64 `json:"gas_limit,string"`
		} `json:"fee"`
	} `json:"auth_info"`
	Signatures []string `json:"signatures"`
}

type coin struct {
	Denom  string `json:"denom"`
	Amount string `json:"amount"`
}

const defaultCustomTxGas = 500000

// walletRef is a generated FUND wallet named in a custom tx's message: {{test2}} for its address,
// {{validator1.valoper}} for its operator address.
var walletRef = regexp.MustCompile(`\{\{([a-z_]+[0-9]+)(\.valoper)?\}\}`)

func resolveWallets(messages []json.RawMessage, wallets map[string]wallet.Wallet) ([]json.RawMessage, error) {
	out := []json.RawMessage{}
	var missing []string
	for _, m := range messages {
		resolved := walletRef.ReplaceAllStringFunc(string(m), func(ref string) string {
			parts := walletRef.FindStringSubmatch(ref)
			w, ok := wallets[parts[1]]
			if !ok {
				missing = append(missing, parts[1])
				return ref
			}
			if parts[2] != "" {
				return w.ValidatorAddress
			}
			return w.AddressBech32
		})
		out = append(out, json.RawMessage(resolved))
	}
	if len(missing) > 0 {
		return nil, fmt.Errorf("no generated FUND wallet called %s", strings.Join(missing, ", "))
	}
	return out, nil
}

func customTxs(cfg *config.Config, wallets map[string]wallet.Wallet) (customTxsFile, error) {
	file := customTxsFile{Gov: []customGovTx{}, Msgs: []customMsgTx{}}
	for i, tx := range cfg.Apps.Und.Txs.Gov {
		messages, err := resolveWallets(tx.ProposalMsgs, wallets)
		if err != nil {
			return file, fmt.Errorf("custom gov tx %d: %w", i+1, err)
		}
		file.Gov = append(file.Gov, customGovTx{SubmitHeight: tx.SubmitHeight, Passes: tx.Passes, Proposal: govProposalFile{
			Messages: messages, Metadata: fmt.Sprintf("simulator custom tx %d", i+1), Deposit: tx.Deposit,
			Title: tx.Title, Summary: tx.Description,
		}})
	}
	for i, tx := range cfg.Apps.Und.Txs.Msgs {
		from, ok := wallets[tx.From]
		if !ok {
			return file, fmt.Errorf("custom msg %d: no generated FUND wallet called %s", i+1, tx.From)
		}
		messages, err := resolveWallets(tx.Messages, wallets)
		if err != nil {
			return file, fmt.Errorf("custom msg %d: %w", i+1, err)
		}
		msg := customMsgTx{SubmitHeight: tx.SubmitHeight, Succeeds: tx.Succeeds, From: tx.From, Address: from.AddressBech32}
		if msg.Succeeds == "" {
			msg.Succeeds = "yes"
		}
		gas := tx.Gas
		if gas == 0 {
			gas = defaultCustomTxGas
		}
		fee := strings.TrimSuffix(tx.Fee, "nund")
		if fee == "" {
			fee = fmt.Sprint(gas * fundGasPrice)
		}
		msg.Tx.Body.Messages = messages
		msg.Tx.Body.Memo = fmt.Sprintf("simulator custom msg %d", i+1)
		msg.Tx.AuthInfo.Fee.Amount = []coin{{Denom: "nund", Amount: fee}}
		msg.Tx.AuthInfo.Fee.GasLimit = gas
		msg.Tx.Signatures = []string{}
		file.Msgs = append(file.Msgs, msg)
	}
	return file, nil
}

// writeCustomTxs writes the transactions the tx runner sends at set heights (none is empty lists).
func (g *generator) writeCustomTxs() error {
	file, err := customTxs(g.cfg, g.fundWallets)
	if err != nil {
		return err
	}
	out, err := json.MarshalIndent(file, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(g.p.TxRunner, "custom_txs.json"), append(out, '\n'), 0o644)
}

// writeProposal renders the upgrade proposal the tx runner submits.
func (g *generator) writeProposal() error {
	upgrade := g.cfg.Apps.Und.Upgrade
	return render.File(filepath.Join(g.p.TemplatesConfigs, "upgrade_proposal.json"), filepath.Join(g.p.TxRunner, "upgrade_proposal.json"), map[string]string{
		"PLAN_NAME": upgrade.PlanName, "UPGRADE_HEIGHT": fmt.Sprint(upgrade.UpgradeHeight),
	})
}
