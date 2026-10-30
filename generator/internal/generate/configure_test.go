package generate

import (
	"testing"

	"github.com/unification-com/mainchain-upgrade-simulator/generator/internal/network"
)

// rpc1's peers in a bash-generated network: every other non-seed node in name order (rpc10 before rpc2, as a glob of
// node_*.json listed them), and the seed on its own.
func TestPeers(t *testing.T) {
	node := func(name, nodeType string) network.Node {
		return network.Node{Name: name, Type: nodeType, P2PAddr: name + "@ip"}
	}
	all := []network.Node{
		node("validator1", network.Validator), node("validator2", network.Validator),
		node("sentry1", network.Sentry), node("seed1", network.Seed),
		node("rpc1", network.RPC), node("rpc2", network.RPC), node("rpc10", network.RPC),
	}
	persistent, seeds := peers(all, all[4])
	if want := "rpc10@ip,rpc2@ip,sentry1@ip,validator1@ip,validator2@ip"; persistent != want {
		t.Errorf("persistent peers = %s, want %s", persistent, want)
	}
	if seeds != "seed1@ip" {
		t.Errorf("seeds = %s", seeds)
	}
	if _, seeds := peers(all, all[3]); seeds != "" {
		t.Errorf("a seed does not list itself: %s", seeds)
	}
}
