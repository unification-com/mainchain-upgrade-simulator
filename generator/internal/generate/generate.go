// Package generate builds a simulator network from config.json. Steps run in the bash generator's order, so the same
// config yields the same container addresses and the genesis accounts appear in the same order.
package generate

import (
	"fmt"
	"math/rand/v2"
	"os"
	"path/filepath"

	"github.com/unification-com/mainchain-upgrade-simulator/generator/internal/chain"
	"github.com/unification-com/mainchain-upgrade-simulator/generator/internal/config"
	"github.com/unification-com/mainchain-upgrade-simulator/generator/internal/genesis"
	"github.com/unification-com/mainchain-upgrade-simulator/generator/internal/network"
	"github.com/unification-com/mainchain-upgrade-simulator/generator/internal/paths"
	"github.com/unification-com/mainchain-upgrade-simulator/generator/internal/stake"
	"github.com/unification-com/mainchain-upgrade-simulator/generator/internal/thirdparty"
	"github.com/unification-com/mainchain-upgrade-simulator/generator/internal/wallet"
)

// side is one chain: the FUND chain under test, or the Gaia chain on the other end of IBC.
type side struct {
	bin     chain.Binary
	chainID string
	denom   string
	home    string // the throwaway home that builds the genesis and holds every key
	wallets string // wallet files
	nodes   string // node homes, copied into the images
	network string // node descriptors
	all     []network.Node
}

func (s *side) genesisFile() string { return filepath.Join(s.home, "config", "genesis.json") }

type generator struct {
	cfg       *config.Config
	p         paths.Paths
	fund, ibc *side
	alloc     *network.Allocator
	rng       *rand.Rand
}

// Run generates the network into p.Generated.
func Run(p paths.Paths, cfg *config.Config) error {
	g := &generator{
		cfg: cfg, p: p,
		fund: &side{bin: chain.Binary{Path: thirdparty.UndBin(p, cfg)}, chainID: cfg.Apps.Und.ChainID, denom: "nund",
			home: p.TmpGlobalUndHome, wallets: p.WalletsUnd, nodes: p.NodesFund, network: p.NetworkUnd},
		ibc: &side{bin: chain.Binary{Path: thirdparty.GaiadBin(p, cfg)}, chainID: cfg.Apps.IBC.ChainID, denom: "stake",
			home: p.TmpGlobalGaiadHome, wallets: p.WalletsGaiad, nodes: p.NodesGaiad, network: p.NetworkGaiad},
		alloc: network.NewAllocator(cfg.Docker.Network),
		rng:   rand.New(rand.NewPCG(rand.Uint64(), rand.Uint64())),
	}
	for _, step := range []struct {
		name string
		run  func() error
	}{
		{"initialise the genesis homes", g.initHomes},
		{"create the accounts", g.createAccounts},
		{"create the validators and their gentxs", g.createValidators},
		{"create the sentry, seed and RPC nodes", g.createOtherNodes},
		{"copy the genesis files to the nodes", g.distributeGenesis},
		{"remove the throwaway genesis homes", func() error { return os.RemoveAll(p.Tmp) }},
	} {
		fmt.Println(step.name)
		if err := step.run(); err != nil {
			return fmt.Errorf("%s: %w", step.name, err)
		}
	}
	return nil
}

func (g *generator) initHomes() error {
	for _, s := range []*side{g.fund, g.ibc} {
		if err := s.bin.Init(s.home, "global", s.chainID); err != nil {
			return err
		}
		if err := s.bin.SetClientConfig(s.home, s.chainID); err != nil {
			return err
		}
	}
	return genesis.TuneFund(g.fund.genesisFile())
}

// fundAccount writes a key's wallet file and funds the account in the side's genesis.
func (g *generator) fundAccount(s *side, key chain.Key, walletType string) (wallet.Wallet, error) {
	w, err := wallet.FromKey(key, walletType)
	if err != nil {
		return w, err
	}
	if err := w.Write(s.wallets); err != nil {
		return w, err
	}
	coins := fmt.Sprintf("%d%s", g.cfg.Apps.Und.Accounts.Nund, s.denom)
	return w, s.bin.AddGenesisAccount(s.home, w.AddressBech32, coins)
}

func (g *generator) newAccount(s *side, name, walletType string) (wallet.Wallet, error) {
	key, err := s.bin.AddKey(s.home, name)
	if err != nil {
		return wallet.Wallet{}, err
	}
	return g.fundAccount(s, key, walletType)
}

// newAccounts creates <prefix>1..<prefix>n.
func (g *generator) newAccounts(s *side, prefix, walletType string, n int) error {
	for i := 1; i <= n; i++ {
		if _, err := g.newAccount(s, fmt.Sprintf("%s%d", prefix, i), walletType); err != nil {
			return err
		}
	}
	return nil
}

// sharedAccount creates an account on the FUND chain and the same mnemonic's account on the IBC chain - for the IBC
// test accounts and the relayer, which need funds on both ends.
func (g *generator) sharedAccount(name, walletType string) error {
	w, err := g.newAccount(g.fund, name, walletType)
	if err != nil {
		return err
	}
	key, err := g.ibc.bin.RecoverKey(g.ibc.home, name, w.Mnemonic)
	if err != nil {
		return err
	}
	_, err = g.fundAccount(g.ibc, key, walletType)
	return err
}

func (g *generator) createAccounts() error {
	acc := g.cfg.Apps.Und.Accounts

	var signers []string
	for i := 1; i <= acc.NumEntSigners; i++ {
		w, err := g.newAccount(g.fund, fmt.Sprintf("enterprise%d", i), "enterprise")
		if err != nil {
			return err
		}
		signers = append(signers, w.AddressBech32)
	}
	if err := genesis.SetEnterpriseSigners(g.fund.genesisFile(), acc.NumEntAccepts, signers); err != nil {
		return err
	}

	for _, set := range []struct {
		s          *side
		prefix     string
		walletType string
		n          int
	}{
		{g.fund, "validator", "validator", g.cfg.Apps.Und.Nodes.NumValidators},
		{g.ibc, "validator", "validator", 1},
		{g.fund, "wrkchain", "wrkchain", acc.NumWrkChains},
		{g.fund, "beacon", "beacon", acc.NumBeacons},
		{g.fund, "test", "test", acc.NumTests},
		{g.fund, "stream_sender", "stream_sender", acc.PaymentStreams},
		{g.fund, "stream_receiver", "stream_receiver", acc.PaymentStreams},
	} {
		if err := g.newAccounts(set.s, set.prefix, set.walletType, set.n); err != nil {
			return err
		}
	}

	for i := 1; i <= g.cfg.Apps.IBC.Accounts.NumIBCAccounts; i++ {
		if err := g.sharedAccount(fmt.Sprintf("ibc%d", i), "ibc"); err != nil {
			return err
		}
	}
	if err := g.sharedAccount("hermes1", "hermes"); err != nil {
		return err
	}

	for _, a := range acc.Static {
		if err := g.fund.bin.AddGenesisAccount(g.fund.home, a.Address, a.Nund+"nund"); err != nil {
			return err
		}
	}
	for _, a := range g.cfg.Apps.IBC.Accounts.Static {
		if err := g.ibc.bin.AddGenesisAccount(g.ibc.home, a.Address, a.Stake+"stake"); err != nil {
			return err
		}
	}
	return nil
}

func (g *generator) createNode(s *side, name, nodeType string) (network.Node, error) {
	n, err := network.Create(s.bin, g.alloc, s.nodes, s.chainID, name, nodeType)
	if err != nil {
		return n, err
	}
	s.all = append(s.all, n)
	return n, n.Write(s.network)
}

// createValidator makes validator<i>'s node and its gentx. The FUND validators take their config overrides; the IBC
// chain's single validator does not.
func (g *generator) createValidator(s *side, i int, useOverrides bool) error {
	n, err := g.createNode(s, fmt.Sprintf("validator%d", i), network.Validator)
	if err != nil {
		return err
	}
	st := stake.ForValidator(i, s.denom, g.cfg.Apps.Und.Staking, useOverrides, g.rng)
	fmt.Printf("%s %s stake %s\n", s.chainID, n.Name, st.Coins)

	gentxDir := filepath.Join(s.home, "config", "gentx")
	if err := os.MkdirAll(gentxDir, 0o755); err != nil {
		return err
	}
	return s.bin.Gentx(s.home, chain.Gentx{
		Moniker: n.Name, Stake: st.Coins,
		CommissionRate: st.CommissionRate, CommissionMaxRate: st.CommissionMaxRate,
		CommissionMaxChangeRate: st.CommissionMaxChangeRate, MinSelfDelegation: st.MinSelfDelegation,
		IP: n.IP, P2PPort: n.P2PPort, NodeID: n.NodeID, ValidatorPubKey: string(n.ValPubKey),
		ChainID: s.chainID, OutputFile: filepath.Join(gentxDir, n.Name+".json"),
	})
}

func (g *generator) createValidators() error {
	for i := 1; i <= g.cfg.Apps.Und.Nodes.NumValidators; i++ {
		if err := g.createValidator(g.fund, i, true); err != nil {
			return err
		}
	}
	if err := g.fund.bin.CollectGentxs(g.fund.home); err != nil {
		return err
	}
	if err := g.createValidator(g.ibc, 1, false); err != nil {
		return err
	}
	return g.ibc.bin.CollectGentxs(g.ibc.home)
}

func (g *generator) createOtherNodes() error {
	nodes := g.cfg.Apps.Und.Nodes
	for _, set := range []struct {
		s        *side
		nodeType string
		n        int
	}{
		{g.fund, network.Sentry, nodes.NumSentries},
		{g.fund, network.Seed, nodes.NumSeeds},
		{g.fund, network.RPC, nodes.NumRPCs},
		{g.ibc, network.RPC, 1},
	} {
		for i := 1; i <= set.n; i++ {
			if _, err := g.createNode(set.s, fmt.Sprintf("%s%d", set.nodeType, i), set.nodeType); err != nil {
				return err
			}
		}
	}
	return nil
}

// distributeGenesis gives every node its chain's finished genesis.
func (g *generator) distributeGenesis() error {
	for _, s := range []*side{g.fund, g.ibc} {
		genesisJSON, err := os.ReadFile(s.genesisFile())
		if err != nil {
			return err
		}
		for _, n := range s.all {
			if err := os.WriteFile(filepath.Join(n.Home, "config", "genesis.json"), genesisJSON, 0o644); err != nil {
				return err
			}
		}
	}
	return nil
}
