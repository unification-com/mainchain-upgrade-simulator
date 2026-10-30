package tomledit

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// the shape of the SDK's app.toml / config.toml: top-level keys, comments, and the same key in several sections
const doc = `# This is a TOML config file.
minimum-gas-prices = ""

# default: the last 362880 states are kept
pruning = "default"

[rpc]
laddr = "tcp://127.0.0.1:26657"

[p2p]
# Address to listen for incoming connections
laddr = "tcp://0.0.0.0:26656"
addr_book_strict = true

[grpc-web]
enable = true

[grpc]
enable = false
`

func TestSet(t *testing.T) {
	path := filepath.Join(t.TempDir(), "app.toml")
	if err := os.WriteFile(path, []byte(doc), 0o644); err != nil {
		t.Fatal(err)
	}
	f, err := Load(path)
	if err != nil {
		t.Fatal(err)
	}
	for _, e := range []struct {
		section, key string
		value        any
	}{
		{"", "minimum-gas-prices", "25.0nund"},
		{"p2p", "laddr", "tcp://0.0.0.0:26660"},
		{"p2p", "addr_book_strict", false},
		{"grpc", "enable", true},
	} {
		if err := f.Set(e.section, e.key, e.value); err != nil {
			t.Fatal(err)
		}
	}
	if err := f.Save(); err != nil {
		t.Fatal(err)
	}
	got, _ := os.ReadFile(path)
	want := strings.NewReplacer(
		`minimum-gas-prices = ""`, `minimum-gas-prices = "25.0nund"`,
		`laddr = "tcp://0.0.0.0:26656"`, `laddr = "tcp://0.0.0.0:26660"`,
		`addr_book_strict = true`, `addr_book_strict = false`,
		"[grpc]\nenable = false", "[grpc]\nenable = true",
	).Replace(doc)
	if string(got) != want {
		t.Fatalf("got:\n%s\nwant:\n%s", got, want)
	}
}

func TestSetErrors(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.toml")
	if err := os.WriteFile(path, []byte(doc), 0o644); err != nil {
		t.Fatal(err)
	}
	f, _ := Load(path)
	for _, e := range []struct {
		section, key string
		value        any
		want         string
	}{
		{"p2p", "seed_mode", true, "[p2p] seed_mode not found"},
		{"", "laddr", "x", "top-level laddr not found"}, // only exists inside sections
		{"p2p", "laddr", `a"b`, "needs escaping"},
		{"p2p", "laddr", 3, "unsupported value type"},
	} {
		if err := f.Set(e.section, e.key, e.value); err == nil || !strings.Contains(err.Error(), e.want) {
			t.Errorf("%s.%s: want %q, got %v", e.section, e.key, e.want, err)
		}
	}
}
