package chain

import (
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

type keyFile struct {
	Type  string `json:"type"`
	Value string `json:"value"`
}

func readKeyFile(path, field, wantType string) ([]byte, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var doc map[string]json.RawMessage // key files carry other fields too, e.g. priv_validator_key.json's address
	if err := json.Unmarshal(raw, &doc); err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	var k keyFile
	if err := json.Unmarshal(doc[field], &k); err != nil || k.Type != wantType {
		return nil, fmt.Errorf("%s: want %s of type %s, got %s", path, field, wantType, doc[field])
	}
	return base64.StdEncoding.DecodeString(k.Value)
}

// NodeID is the CometBFT p2p ID of a node home: the first 20 bytes of the SHA-256 of its node key's ed25519 public key,
// in hex - what `<binary> tendermint show-node-id` prints.
func NodeID(home string) (string, error) {
	path := filepath.Join(home, "config", "node_key.json")
	priv, err := readKeyFile(path, "priv_key", "tendermint/PrivKeyEd25519")
	if err != nil {
		return "", err
	}
	if len(priv) != 64 {
		return "", fmt.Errorf("%s: ed25519 private key is %d bytes, want 64", path, len(priv))
	}
	sum := sha256.Sum256(priv[32:]) // an ed25519 private key is seed || public key
	return hex.EncodeToString(sum[:20]), nil
}

// ValidatorPubKey is a node home's consensus public key as the SDK writes it in JSON - what
// `<binary> tendermint show-validator` prints and what a gentx takes as --pubkey.
func ValidatorPubKey(home string) (string, error) {
	pub, err := readKeyFile(filepath.Join(home, "config", "priv_validator_key.json"), "pub_key", "tendermint/PubKeyEd25519")
	if err != nil {
		return "", err
	}
	out, err := json.Marshal(struct {
		Type string `json:"@type"`
		Key  string `json:"key"`
	}{"/cosmos.crypto.ed25519.PubKey", base64.StdEncoding.EncodeToString(pub)})
	return string(out), err
}
