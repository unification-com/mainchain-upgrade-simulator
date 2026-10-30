package compare

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func tree(t *testing.T, files map[string]string) string {
	t.Helper()
	root := t.TempDir()
	for rel, body := range files {
		path := filepath.Join(root, rel)
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return root
}

const (
	addrA = "und1xk7x29fntk7gyanvclk6289803s3w5qaz86n50"
	addrB = "und104zyplzvwyhnewqkxn6ghdnsh3360cxzv77tpy"
	hexA  = "35BC6515335DBC82766CC7EDA51CA77C6117501D"
	hexB  = "7D4440FC4C712F3CB81634F48BB670BC63A7E0C2"
)

func genesis(addr, stake string) string {
	return `{"app_state":{"auth":{"accounts":[{"address":"` + addr + `"}]},"genutil":{"gen_txs":[{"body":{"messages":[{"value":{"amount":"` + stake + `"}}]}}]}}}`
}

func TestRandomnessIsNotADifference(t *testing.T) {
	a := tree(t, map[string]string{
		"net/genesis.json": genesis(addrA, "240000000000000"),
		"wallets/v1.json":  `{"address_bech32":"` + addrA + `","address_hex":"` + hexA + `"}`,
		"node.toml":        "moniker = \"v1\"\nid = \"" + strings.ToLower(hexA) + "\"\n",
	})
	b := tree(t, map[string]string{
		"net/genesis.json": genesis(addrB, "118716331787074"),
		"wallets/v1.json":  `{"address_hex":"` + hexB + `","address_bech32":"` + addrB + `"}`, // key order differs too
		"node.toml":        "moniker = \"v1\"\nid = \"" + strings.ToLower(hexB) + "\"\n",
	})
	res, err := Trees(a, b, 10, nil)
	if err != nil {
		t.Fatal(err)
	}
	if !res.Empty() {
		t.Fatalf("want no differences, got %+v", res)
	}
}

func TestRealDifferencesAreReported(t *testing.T) {
	a := tree(t, map[string]string{
		"w.json":   `{"account":"v1","key_files":{"contents":"` + strings.Repeat("Q", 60) + `"},"address":"` + addrA + `"}`,
		"x.toml":   "a = 1\n",
		"old.json": "{}",
	})
	b := tree(t, map[string]string{
		"w.json":   `{"account":"v2","address":"` + addrB + `"}`,
		"x.toml":   "a = 2\n",
		"new.json": "{}",
	})
	res, err := Trees(a, b, 10, nil)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Join(res.OnlyA, ",") != "old.json" || strings.Join(res.OnlyB, ",") != "new.json" {
		t.Errorf("only-in lists: %v / %v", res.OnlyA, res.OnlyB)
	}
	// the one-sided key_files is one difference, and the address after it still lines up
	w := res.Diffs["w.json"]
	if len(w) != 2 || !strings.Contains(w[0], "/account") || !strings.Contains(w[1], "/key_files only in A") {
		t.Errorf("w.json diffs: %q", w)
	}
	if len(res.Diffs["x.toml"]) != 1 {
		t.Errorf("x.toml diffs: %q", res.Diffs["x.toml"])
	}
}

// The chain sorts bank balances by address, so random addresses put the same balances in a different order.
func TestReorderedArraysAreNotADifference(t *testing.T) {
	balances := func(first, second string) string {
		return `{"accounts":["` + first + `","` + second + `"],"balances":[{"address":"` + second + `"},{"address":"` + first + `"}]}`
	}
	a := tree(t, map[string]string{"g.json": balances(addrA, addrB)})
	b := tree(t, map[string]string{"g.json": strings.Replace(balances(addrB, addrA), `"balances":[{"address":"`+addrA+`"},{"address":"`+addrB+`"}]`,
		`"balances":[{"address":"`+addrB+`"},{"address":"`+addrA+`"}]`, 1)})
	res, err := Trees(a, b, 10, nil)
	if err != nil {
		t.Fatal(err)
	}
	if !res.Empty() {
		t.Fatalf("want no differences, got %+v", res)
	}
}

// docker-compose.yml is compared by content: layout and key order are not differences, values are.
func TestYAMLIsComparedStructurally(t *testing.T) {
	a := tree(t, map[string]string{"c.yml": "services:\n  n1:\n    ports: [\"1:1\"]\n    image: x\n"})
	b := tree(t, map[string]string{"c.yml": "services:\n    n1:\n        image: x\n        ports:\n            - \"1:1\"\n"})
	if res, err := Trees(a, b, 10, nil); err != nil || !res.Empty() {
		t.Fatalf("want no differences, got %+v %v", res, err)
	}
	c := tree(t, map[string]string{"c.yml": "services:\n  n1:\n    ports: [\"2:2\"]\n    image: x\n"})
	res, err := Trees(a, c, 10, nil)
	if err != nil || len(res.Diffs["c.yml"]) != 1 || !strings.Contains(res.Diffs["c.yml"][0], "/services/n1/ports") {
		t.Fatalf("want one ports difference, got %+v %v", res.Diffs, err)
	}
}
