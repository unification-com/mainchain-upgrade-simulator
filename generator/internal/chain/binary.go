// Package chain drives a chain's CLI - the genesis-version und, or gaiad - for the work only the chain's own code
// should do: node homes, keys, genesis accounts and gentxs. Everything that can be derived from what the CLI writes
// (node IDs, validator keys, address forms) is derived in Go instead of costing another process each.
package chain

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os/exec"
	"path/filepath"
	"strings"
)

type Binary struct {
	Path string
}

// Key is what `keys add --output json` reports. PubKey is a JSON object serialised as a string.
type Key struct {
	Name     string `json:"name"`
	Address  string `json:"address"`
	PubKey   string `json:"pubkey"`
	Mnemonic string `json:"mnemonic"`
}

func (b Binary) run(stdin string, args ...string) ([]byte, error) {
	cmd := exec.Command(b.Path, args...)
	if stdin != "" {
		cmd.Stdin = strings.NewReader(stdin)
	}
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("%s %s: %w\n%s", filepath.Base(b.Path), strings.Join(args, " "), err, strings.TrimSpace(stderr.String()))
	}
	return stdout.Bytes(), nil
}

// Init creates a node home: config, node key, validator key and a default genesis.
func (b Binary) Init(home, moniker, chainID string) error {
	_, err := b.run("", "init", moniker, "--home", home, "--chain-id", chainID)
	return err
}

// SetClientConfig points the home's CLI config at the chain, with the test keyring and JSON output.
func (b Binary) SetClientConfig(home, chainID string) error {
	for _, kv := range [][2]string{{"chain-id", chainID}, {"keyring-backend", "test"}, {"output", "json"}} {
		if _, err := b.run("", "config", "set", "client", kv[0], kv[1], "--home", home); err != nil {
			return err
		}
	}
	return nil
}

// AddKey creates a new key in the home's test keyring.
func (b Binary) AddKey(home, name string) (Key, error) {
	return b.addKey("", home, name)
}

// RecoverKey adds a key to the home's test keyring from an existing mnemonic - the same account on another chain.
func (b Binary) RecoverKey(home, name, mnemonic string) (Key, error) {
	key, err := b.addKey(mnemonic+"\n", home, name, "--recover")
	key.Mnemonic = mnemonic
	return key, err
}

func (b Binary) addKey(stdin, home, name string, extra ...string) (Key, error) {
	args := append([]string{"keys", "add", name, "--keyring-backend", "test", "--home", home, "--output", "json"}, extra...)
	out, err := b.run(stdin, args...)
	if err != nil {
		return Key{}, err
	}
	var key Key
	if err := json.Unmarshal(out, &key); err != nil {
		return Key{}, fmt.Errorf("keys add %s: %w: %s", name, err, out)
	}
	return key, nil
}

// AddGenesisAccount funds an address in the home's genesis, e.g. coins "1000nund".
func (b Binary) AddGenesisAccount(home, address, coins string) error {
	_, err := b.run("", "genesis", "add-genesis-account", address, coins, "--home", home)
	return err
}

// Gentx is a validator's genesis transaction.
type Gentx struct {
	Moniker                 string // also the signing key's name
	Stake                   string // coins, e.g. "1000nund"
	CommissionRate          string
	CommissionMaxRate       string
	CommissionMaxChangeRate string
	MinSelfDelegation       string
	IP                      string
	P2PPort                 int
	NodeID                  string
	ValidatorPubKey         string // the consensus key, as JSON
	ChainID                 string
	OutputFile              string
}

func (b Binary) Gentx(home string, g Gentx) error {
	_, err := b.run("", "genesis", "gentx", g.Moniker, g.Stake,
		"--home", home,
		"--commission-rate", g.CommissionRate,
		"--commission-max-rate", g.CommissionMaxRate,
		"--commission-max-change-rate", g.CommissionMaxChangeRate,
		"--min-self-delegation", g.MinSelfDelegation,
		"--moniker", g.Moniker,
		"--details", g.Moniker,
		"--ip", g.IP,
		"--p2p-port", fmt.Sprint(g.P2PPort),
		"--node-id", g.NodeID,
		"--pubkey", g.ValidatorPubKey,
		"--chain-id", g.ChainID,
		"--from", g.Moniker,
		"--keyring-backend", "test",
		"--output-document", g.OutputFile)
	return err
}

// CollectGentxs puts the home's gentxs into its genesis.
func (b Binary) CollectGentxs(home string) error {
	_, err := b.run("", "genesis", "collect-gentxs", "--home", home)
	return err
}
