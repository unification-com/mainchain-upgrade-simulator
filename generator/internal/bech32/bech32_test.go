package bech32

import (
	"encoding/hex"
	"strings"
	"testing"
)

// Real wallets written by the bash generator: account address, its bytes, and the validator / consensus forms the
// und and gaiad binaries derived from them.
var wallets = []struct{ prefix, address, hex, valoper, valcons string }{
	{"und", "und1xk7x29fntk7gyanvclk6289803s3w5qaz86n50", "35BC6515335DBC82766CC7EDA51CA77C6117501D",
		"undvaloper1xk7x29fntk7gyanvclk6289803s3w5qaf3kc5f", "undvalcons1xk7x29fntk7gyanvclk6289803s3w5qaaz9ycg"},
	{"cosmos", "cosmos1xx9x2qt9296valhcnv48ka6g9mltdk9st8j0d4", "318A6501655174CEFEF89B2A7B77482EFEB6D8B0",
		"cosmosvaloper1xx9x2qt9296valhcnv48ka6g9mltdk9swnx6px", "cosmosvalcons1xx9x2qt9296valhcnv48ka6g9mltdk9s6q4xd8"},
}

func TestRoundTripAgainstChainBinaries(t *testing.T) {
	for _, w := range wallets {
		hrp, data, err := Decode(w.address)
		if err != nil || hrp != w.prefix || strings.ToUpper(hex.EncodeToString(data)) != w.hex {
			t.Fatalf("%s: got %s %X %v", w.address, hrp, data, err)
		}
		for suffix, want := range map[string]string{"": w.address, "valoper": w.valoper, "valcons": w.valcons} {
			got, err := Encode(w.prefix+suffix, data)
			if err != nil || got != want {
				t.Errorf("%s%s: got %s %v, want %s", w.prefix, suffix, got, err, want)
			}
		}
	}
}

func TestDecodeRejectsCorruption(t *testing.T) {
	good := wallets[0].address
	for _, bad := range []string{
		good[:len(good)-1] + "q",             // checksum
		strings.ToUpper(good[:5]) + good[5:], // mixed case
		"und1b" + good[5:],                   // invalid character
		"nosep",
	} {
		if _, _, err := Decode(bad); err == nil {
			t.Errorf("%q: want an error", bad)
		}
	}
}
