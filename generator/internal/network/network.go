// Package network creates the nodes of both chains and gives each its container IP and ports.
package network

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"github.com/unification-com/mainchain-upgrade-simulator/generator/internal/chain"
	"github.com/unification-com/mainchain-upgrade-simulator/generator/internal/config"
)

const (
	Validator = "validator"
	Sentry    = "sentry"
	Seed      = "seed"
	RPC       = "rpc"
)

// Allocator hands out container IPs and host ports in node-creation order, across both chains, so the same config
// always yields the same addresses - the README's defaults (e.g. FUND rpc1 on 26760/1320) depend on that order. Only
// RPC nodes publish RPC/REST/gRPC ports; every other node keeps the in-container defaults.
type Allocator struct {
	subnet                   string
	ip, p2p, rpc, rest, gRPC int
}

func NewAllocator(n config.Network) *Allocator {
	return &Allocator{subnet: n.Subnet, ip: n.IPStart, p2p: n.P2PPortStart, rpc: n.RPCPortStart, rest: n.RESTPortStart, gRPC: n.GRPCPortStart}
}

func next(counter *int) int {
	v := *counter
	*counter++
	return v
}

func (a *Allocator) NextIP() string {
	return fmt.Sprintf("%s.%d", a.subnet, next(&a.ip))
}

// Node is a node's descriptor, written to generated/network/<chain>/node_<name>.json.
type Node struct {
	Name      string          `json:"name"`
	Type      string          `json:"type"`
	IP        string          `json:"ip"`
	P2PPort   int             `json:"p2p_port,string"`
	NodeID    string          `json:"node_id"`
	ValPubKey json.RawMessage `json:"val_pubkey"`
	P2PAddr   string          `json:"p2p_addr"`
	RPCPort   int             `json:"rpc_port,string"`
	RESTPort  int             `json:"rest_port,string"`
	GRPCPort  int             `json:"grpc_port,string"`
	ChainID   string          `json:"chain_id"`
	Home      string          `json:"-"`
}

// Create makes a node home under homeRoot with the chain binary and describes it.
func Create(bin chain.Binary, alloc *Allocator, homeRoot, chainID, name, nodeType string) (Node, error) {
	n := Node{
		Name: name, Type: nodeType, ChainID: chainID,
		IP:      alloc.NextIP(),
		P2PPort: next(&alloc.p2p),
		RPCPort: 26657, RESTPort: 1317, GRPCPort: 9090,
		Home: filepath.Join(homeRoot, name),
	}
	if nodeType == RPC {
		n.RPCPort, n.RESTPort, n.GRPCPort = next(&alloc.rpc), next(&alloc.rest), next(&alloc.gRPC)
	}

	if err := bin.Init(n.Home, name, chainID); err != nil {
		return Node{}, err
	}
	var err error
	if n.NodeID, err = chain.NodeID(n.Home); err != nil {
		return Node{}, err
	}
	valPubKey, err := chain.ValidatorPubKey(n.Home)
	if err != nil {
		return Node{}, err
	}
	n.ValPubKey = json.RawMessage(valPubKey)
	n.P2PAddr = fmt.Sprintf("%s@%s:%d", n.NodeID, n.IP, n.P2PPort)
	return n, nil
}

// Write saves the descriptor as <dir>/node_<name>.json.
func (n Node) Write(dir string) error {
	out, err := json.MarshalIndent(n, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(dir, "node_"+n.Name+".json"), append(out, '\n'), 0o644)
}
