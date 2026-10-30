// Package wallet writes the per-account JSON files (generated/assets/wallets/<chain>/<account>.json) that the tx
// runner, verify and the Hermes image read: the mnemonic and every address form of the account.
package wallet

import (
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/unification-com/mainchain-upgrade-simulator/generator/internal/bech32"
	"github.com/unification-com/mainchain-upgrade-simulator/generator/internal/chain"
)

type Wallet struct {
	Account          string          `json:"account"`
	WalletType       string          `json:"wallet_type"`
	Mnemonic         string          `json:"mnemonic"`
	AddressBech32    string          `json:"address_bech32"`
	AddressHex       string          `json:"address_hex"`
	Bech32Prefix     string          `json:"bech32_prefix"`
	ValidatorAddress string          `json:"validator_address"`
	ConsensusAddress string          `json:"consensus_address"`
	PubKey           json.RawMessage `json:"pubkey"`
}

// FromKey derives every address form from a key the chain binary created.
func FromKey(key chain.Key, walletType string) (Wallet, error) {
	prefix, data, err := bech32.Decode(key.Address)
	if err != nil {
		return Wallet{}, fmt.Errorf("key %s: %w", key.Name, err)
	}
	valoper, err := bech32.Encode(prefix+"valoper", data)
	if err != nil {
		return Wallet{}, err
	}
	valcons, err := bech32.Encode(prefix+"valcons", data)
	if err != nil {
		return Wallet{}, err
	}
	if !json.Valid([]byte(key.PubKey)) {
		return Wallet{}, fmt.Errorf("key %s: pubkey is not JSON: %q", key.Name, key.PubKey)
	}
	return Wallet{
		Account:          key.Name,
		WalletType:       walletType,
		Mnemonic:         key.Mnemonic,
		AddressBech32:    key.Address,
		AddressHex:       strings.ToUpper(hex.EncodeToString(data)),
		Bech32Prefix:     prefix,
		ValidatorAddress: valoper,
		ConsensusAddress: valcons,
		PubKey:           json.RawMessage(key.PubKey),
	}, nil
}

// Write saves the wallet as <dir>/<account>.json.
func (w Wallet) Write(dir string) error {
	out, err := json.MarshalIndent(w, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(dir, w.Account+".json"), append(out, '\n'), 0o644)
}
