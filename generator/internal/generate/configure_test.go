package generate

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/unification-com/mainchain-upgrade-simulator/generator/internal/config"
	"github.com/unification-com/mainchain-upgrade-simulator/generator/internal/network"
	"github.com/unification-com/mainchain-upgrade-simulator/generator/internal/wallet"
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

var testWallets = map[string]wallet.Wallet{
	"test1":      {Account: "test1", AddressBech32: "und1test1"},
	"validator1": {Account: "validator1", AddressBech32: "und1val1", ValidatorAddress: "undvaloper1val1"},
}

func TestCustomTxs(t *testing.T) {
	cfg := &config.Config{}
	cfg.Apps.Und.Txs.Gov = []config.GovTx{
		{Title: "BEACON parameters", Description: "raise a fee", Passes: "yes", SubmitHeight: 20, Deposit: "10nund",
			ProposalMsgs: []json.RawMessage{json.RawMessage(`{"@type":"/mainchain.beacon.v1.MsgUpdateParams","params":{"fee_register":"1"}}`)}},
		{Title: "signal", Description: "a text proposal", Passes: "no", SubmitHeight: 22, Deposit: "10nund"},
	}
	cfg.Apps.Und.Txs.Msgs = []config.MsgTx{
		{From: "test1", SubmitHeight: 52, Messages: []json.RawMessage{
			json.RawMessage(`{"@type":"/cosmos.staking.v1beta1.MsgDelegate","delegator_address":"{{test1}}","validator_address":"{{validator1.valoper}}"}`)}},
		{From: "validator1", SubmitHeight: 53, Succeeds: "no", Gas: 100, Fee: "7nund", Messages: []json.RawMessage{json.RawMessage(`{"@type":"/x"}`)}},
	}
	file, err := customTxs(cfg, testWallets)
	if err != nil {
		t.Fatal(err)
	}
	out, _ := json.Marshal(file)
	want := `{"gov":[` +
		`{"submit_height":20,"passes":"yes","proposal":{"messages":[{"@type":"/mainchain.beacon.v1.MsgUpdateParams","params":{"fee_register":"1"}}],"metadata":"simulator custom tx 1","deposit":"10nund","title":"BEACON parameters","summary":"raise a fee"}},` +
		`{"submit_height":22,"passes":"no","proposal":{"messages":[],"metadata":"simulator custom tx 2","deposit":"10nund","title":"signal","summary":"a text proposal"}}],` +
		`"msgs":[` +
		`{"submit_height":52,"succeeds":"yes","from":"test1","address":"und1test1","tx":{"body":{"messages":[{"@type":"/cosmos.staking.v1beta1.MsgDelegate","delegator_address":"und1test1","validator_address":"undvaloper1val1"}],"memo":"simulator custom msg 1"},"auth_info":{"fee":{"amount":[{"denom":"nund","amount":"12500000"}],"gas_limit":"500000"}},"signatures":[]}},` +
		`{"submit_height":53,"succeeds":"no","from":"validator1","address":"und1val1","tx":{"body":{"messages":[{"@type":"/x"}],"memo":"simulator custom msg 2"},"auth_info":{"fee":{"amount":[{"denom":"nund","amount":"7"}],"gas_limit":"100"}},"signatures":[]}}]}`
	if string(out) != want {
		t.Fatalf("got  %s\nwant %s", out, want)
	}

	none, _ := customTxs(&config.Config{}, nil)
	if out, _ := json.Marshal(none); string(out) != `{"gov":[],"msgs":[]}` {
		t.Fatalf("no custom txs: got %s", out)
	}
}

func TestCustomTxsUnknownWallet(t *testing.T) {
	cfg := &config.Config{}
	cfg.Apps.Und.Txs.Msgs = []config.MsgTx{{From: "test1", SubmitHeight: 1, Messages: []json.RawMessage{json.RawMessage(`{"to":"{{test9}}"}`)}}}
	if _, err := customTxs(cfg, testWallets); err == nil || !strings.Contains(err.Error(), "test9") {
		t.Errorf("unknown placeholder wallet: got %v", err)
	}
	cfg.Apps.Und.Txs.Msgs[0].From = "beacon1"
	if _, err := customTxs(cfg, testWallets); err == nil || !strings.Contains(err.Error(), "beacon1") {
		t.Errorf("unknown signer: got %v", err)
	}
}
