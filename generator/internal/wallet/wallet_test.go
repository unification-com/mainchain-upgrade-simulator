package wallet

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/unification-com/mainchain-upgrade-simulator/generator/internal/chain"
)

// validator1's key as `und keys add` reported it, and the address forms the binary's `keys show` / `keys parse`
// gave the bash generator for it.
var key = chain.Key{
	Name:     "validator1",
	Address:  "und1xk7x29fntk7gyanvclk6289803s3w5qaz86n50",
	PubKey:   `{"@type":"/cosmos.crypto.secp256k1.PubKey","key":"AvCjYTdfnrRR/3zVHV3V1C4U8Os8FOWyr54CmdjMrR5h"}`,
	Mnemonic: "word list",
}

func TestFromKeyMatchesTheChainBinary(t *testing.T) {
	w, err := FromKey(key, "validator")
	if err != nil {
		t.Fatal(err)
	}
	want := Wallet{
		Account: "validator1", WalletType: "validator", Mnemonic: "word list",
		AddressBech32:    "und1xk7x29fntk7gyanvclk6289803s3w5qaz86n50",
		AddressHex:       "35BC6515335DBC82766CC7EDA51CA77C6117501D",
		Bech32Prefix:     "und",
		ValidatorAddress: "undvaloper1xk7x29fntk7gyanvclk6289803s3w5qaf3kc5f",
		ConsensusAddress: "undvalcons1xk7x29fntk7gyanvclk6289803s3w5qaaz9ycg",
		PubKey:           json.RawMessage(key.PubKey),
	}
	got, _ := json.Marshal(w)
	exp, _ := json.Marshal(want)
	if string(got) != string(exp) {
		t.Fatalf("got  %s\nwant %s", got, exp)
	}
}

func TestWriteKeepsPubKeyAnObject(t *testing.T) {
	w, err := FromKey(key, "validator")
	if err != nil {
		t.Fatal(err)
	}
	dir := t.TempDir()
	if err := w.Write(dir); err != nil {
		t.Fatal(err)
	}
	raw, err := os.ReadFile(filepath.Join(dir, "validator1.json"))
	if err != nil {
		t.Fatal(err)
	}
	var doc struct {
		PubKey map[string]string `json:"pubkey"`
	}
	if err := json.Unmarshal(raw, &doc); err != nil || doc.PubKey["key"] == "" {
		t.Fatalf("pubkey is not an object in %s: %v", raw, err)
	}
}

func TestFromKeyRejectsBadInput(t *testing.T) {
	if _, err := FromKey(chain.Key{Name: "x", Address: "und1bad", PubKey: "{}"}, "test"); err == nil {
		t.Error("want an error for a bad address")
	}
	if _, err := FromKey(chain.Key{Name: "x", Address: key.Address, PubKey: "not json"}, "test"); err == nil {
		t.Error("want an error for a non-JSON pubkey")
	}
}
