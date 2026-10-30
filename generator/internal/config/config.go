// Package config is the typed form of config.json.
//
// The rules (ranges, patterns, cross-field limits) live in schema/config.schema.json and are enforced by the Node
// validator (scripts/nodejs/packages/config) before the generator runs, so they are not repeated here. Load only
// decodes, strictly: an unknown key is an error, so a field missing from these structs cannot be silently dropped.
package config

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
)

type Config struct {
	Apps   Apps   `json:"apps"`
	Docker Docker `json:"docker"`
}

type Apps struct {
	Und        Und        `json:"und"`
	IBC        IBC        `json:"ibc"`
	Cosmovisor Cosmovisor `json:"cosmovisor"`
}

type Und struct {
	ChainID     string   `json:"chain_id"`
	GenesisTime string   `json:"genesis_time"`
	Genesis     Genesis  `json:"genesis"`
	Upgrade     Upgrade  `json:"upgrade"`
	Nodes       Nodes    `json:"nodes"`
	Staking     Staking  `json:"staking"`
	Accounts    Accounts `json:"accounts"`
}

type Genesis struct {
	// und release the network starts on - the version upgraded from
	Version string `json:"version"`
}

type Upgrade struct {
	// mainchain branch or tag built as the upgrade binary
	Branch        string `json:"branch"`
	UpgradeHeight int64  `json:"upgrade_height"`
	PlanName      string `json:"upgrade_plan_name"`
}

type Nodes struct {
	NumValidators int `json:"num_validators"`
	NumSentries   int `json:"num_sentries"`
	NumSeeds      int `json:"num_seeds"`
	NumRPCs       int `json:"num_rpcs"`
}

type Staking struct {
	MinStake       uint64          `json:"min_stake"`
	MaxStake       uint64          `json:"max_stake"`
	SmallMinStake  uint64          `json:"small_min_stake"`
	SmallMaxStake  uint64          `json:"small_max_stake"`
	StakeOverrides []StakeOverride `json:"stake_overrides"`
}

// StakeOverride replaces the generated values for one validator. Unset fields keep the generated value. The
// commission fractions stay json.Number so they reach the und CLI exactly as written in config.json.
type StakeOverride struct {
	Validator     int          `json:"validator"`
	Rate          *json.Number `json:"rate"`
	MaxRate       *json.Number `json:"max_rate"`
	MaxChangeRate *json.Number `json:"max_change_rate"`
	Stake         *uint64      `json:"stake"`
	MinSelf       *uint64      `json:"min_self"`
}

type Accounts struct {
	Nund          uint64 `json:"nund"`
	EntPOAmount   uint64 `json:"ent_po_amount"`
	NumEntSigners int    `json:"num_ent_signers"`
	NumEntAccepts int    `json:"num_ent_accepts"`
	// the key's spelling is historical; renaming it would break every existing config.json
	NumWrkChains    int             `json:"num_wrhchains"`
	NumBeacons      int             `json:"num_beacons"`
	NumTests        int             `json:"num_tests"`
	StoragePurchase int             `json:"storage_purchase"`
	PaymentStreams  int             `json:"payment_streams"`
	Static          []StaticAccount `json:"static"`
}

type StaticAccount struct {
	Address string `json:"address"`
	Nund    string `json:"nund"`
}

type IBC struct {
	// Gaia release tag of the IBC counterparty chain (not an ibc-go version)
	Version       string      `json:"version"`
	HermesVersion string      `json:"hermes_version"`
	ChainID       string      `json:"chain_id"`
	Accounts      IBCAccounts `json:"accounts"`
}

type IBCAccounts struct {
	NumIBCAccounts int                `json:"num_ibc_accounts"`
	Static         []StaticIBCAccount `json:"static"`
}

type StaticIBCAccount struct {
	Address string `json:"address"`
	Stake   string `json:"stake"`
}

type Cosmovisor struct {
	Version string `json:"version"`
}

type Docker struct {
	ContainerPrefix string  `json:"container_prefix"`
	Network         Network `json:"network"`
}

type Network struct {
	// first three octets, e.g. 172.25.1
	Subnet        string `json:"subnet"`
	IPStart       int    `json:"ip_start"`
	P2PPortStart  int    `json:"p2p_port_start"`
	RPCPortStart  int    `json:"rpc_port_start"`
	RESTPortStart int    `json:"rest_port_start"`
	GRPCPortStart int    `json:"grpc_port_start"`
}

// Load reads and strictly decodes a config file.
func Load(path string) (*Config, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	return Parse(raw)
}

// Parse strictly decodes config JSON: unknown keys and trailing content are errors.
func Parse(raw []byte) (*Config, error) {
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.DisallowUnknownFields()
	var cfg Config
	if err := dec.Decode(&cfg); err != nil {
		return nil, fmt.Errorf("decoding config: %w", err)
	}
	if dec.More() {
		return nil, fmt.Errorf("decoding config: unexpected content after the top-level object")
	}
	return &cfg, nil
}
