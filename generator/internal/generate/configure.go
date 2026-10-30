package generate

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/unification-com/mainchain-upgrade-simulator/generator/internal/network"
	"github.com/unification-com/mainchain-upgrade-simulator/generator/internal/render"
	"github.com/unification-com/mainchain-upgrade-simulator/generator/internal/tomledit"
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

// writeProposal renders the upgrade proposal the tx runner submits.
func (g *generator) writeProposal() error {
	upgrade := g.cfg.Apps.Und.Upgrade
	return render.File(filepath.Join(g.p.TemplatesConfigs, "upgrade_proposal.json"), filepath.Join(g.p.TxRunner, "upgrade_proposal.json"), map[string]string{
		"PLAN_NAME": upgrade.PlanName, "UPGRADE_HEIGHT": fmt.Sprint(upgrade.UpgradeHeight),
	})
}
