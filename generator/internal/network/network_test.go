package network

import (
	"encoding/json"
	"testing"

	"github.com/unification-com/mainchain-upgrade-simulator/generator/internal/config"
)

// The defaults in example.config.json give the addresses the README documents: validators from .2 on p2p 26660..., and
// the first RPC node its RPC/REST/gRPC ports from the starts, while non-RPC nodes keep the in-container defaults.
func TestAllocationOrder(t *testing.T) {
	a := NewAllocator(config.Network{Subnet: "172.25.1", IPStart: 2, P2PPortStart: 26660, RPCPortStart: 26760, RESTPortStart: 1320, GRPCPortStart: 9190})
	if got := a.NextIP(); got != "172.25.1.2" {
		t.Fatalf("first IP = %s", got)
	}
	if got := next(&a.p2p); got != 26660 {
		t.Fatalf("first p2p = %d", got)
	}
	if rpc, rest, grpc := next(&a.rpc), next(&a.rest), next(&a.gRPC); rpc != 26760 || rest != 1320 || grpc != 9190 {
		t.Fatalf("first rpc ports = %d %d %d", rpc, rest, grpc)
	}
	if got := a.NextIP(); got != "172.25.1.3" {
		t.Fatalf("second IP = %s", got)
	}
}

func TestDescriptorKeepsTheBashShape(t *testing.T) {
	n := Node{Name: "validator1", Type: Validator, IP: "172.25.1.2", P2PPort: 26660, NodeID: "id", ValPubKey: json.RawMessage(`{"@type":"t","key":"k"}`),
		P2PAddr: "id@172.25.1.2:26660", RPCPort: 26657, RESTPort: 1317, GRPCPort: 9090, ChainID: "c", Home: "/not/written"}
	out, err := json.Marshal(n)
	if err != nil {
		t.Fatal(err)
	}
	want := `{"name":"validator1","type":"validator","ip":"172.25.1.2","p2p_port":"26660","node_id":"id","val_pubkey":{"@type":"t","key":"k"},"p2p_addr":"id@172.25.1.2:26660","rpc_port":"26657","rest_port":"1317","grpc_port":"9090","chain_id":"c"}`
	if string(out) != want {
		t.Fatalf("got  %s\nwant %s", out, want)
	}
}
