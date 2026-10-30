package chain

import (
	"os"
	"path/filepath"
	"testing"
)

// A node home written by `und init` (a throwaway simulator node), with the node ID and validator key that
// `und tendermint show-node-id` / `show-validator` reported for it.
const (
	nodeKey       = `{"priv_key":{"type":"tendermint/PrivKeyEd25519","value":"Cuvg+KN6j+KgPtpqkdgkkp0jXTSP+jgHj54YB134Dgl2eYnvjmdneKF886U00QKxB5uwlfI/GycRYF/lXlSiwg=="}}`
	privValKey    = `{"address":"","pub_key":{"type":"tendermint/PubKeyEd25519","value":"4rqOu4BVad41WzaOhCAprKxc5Fp/egKWdQ6ag1gRjqc="},"priv_key":{"type":"tendermint/PrivKeyEd25519","value":""}}`
	wantNodeID    = "5d9e50dd07e932dd2fa2ba415c3e0b2b937d1a84"
	wantValPubKey = `{"@type":"/cosmos.crypto.ed25519.PubKey","key":"4rqOu4BVad41WzaOhCAprKxc5Fp/egKWdQ6ag1gRjqc="}`
)

func nodeHome(t *testing.T, files map[string]string) string {
	t.Helper()
	home := t.TempDir()
	if err := os.MkdirAll(filepath.Join(home, "config"), 0o755); err != nil {
		t.Fatal(err)
	}
	for name, body := range files {
		if err := os.WriteFile(filepath.Join(home, "config", name), []byte(body), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	return home
}

func TestIdentityMatchesTheChainBinary(t *testing.T) {
	home := nodeHome(t, map[string]string{"node_key.json": nodeKey, "priv_validator_key.json": privValKey})

	id, err := NodeID(home)
	if err != nil || id != wantNodeID {
		t.Errorf("NodeID = %s, %v; want %s", id, err, wantNodeID)
	}
	pub, err := ValidatorPubKey(home)
	if err != nil || pub != wantValPubKey {
		t.Errorf("ValidatorPubKey = %s, %v; want %s", pub, err, wantValPubKey)
	}
}

func TestIdentityRejectsUnexpectedKeys(t *testing.T) {
	home := nodeHome(t, map[string]string{
		"node_key.json":           `{"priv_key":{"type":"tendermint/PrivKeySecp256k1","value":"AAAA"}}`,
		"priv_validator_key.json": `{"pub_key":{"type":"tendermint/PubKeyEd25519","value":"not base64"}}`,
	})
	if _, err := NodeID(home); err == nil {
		t.Error("NodeID: want an error for a non-ed25519 node key")
	}
	if _, err := ValidatorPubKey(home); err == nil {
		t.Error("ValidatorPubKey: want an error for a malformed key")
	}
}
