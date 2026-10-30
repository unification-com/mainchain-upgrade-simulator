package genesis

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// the parts of a genesis the edits touch, with und 1.12.0's defaults, plus a number that must keep its exact text
const fundGenesis = `{
  "genesis_time": "2026-01-01T00:00:00Z",
  "initial_height": 1,
  "app_state": {
    "bank": {"supply": [{"denom": "nund", "amount": "1"}], "big": 123456789012345678901234567890},
    "gov": {"params": {"voting_period": "172800s", "expedited_voting_period": "86400s", "max_deposit_period": "172800s"}},
    "beacon": {"params": {"fee_purchase_storage": "5000000000", "default_storage_limit": "50000", "max_storage_limit": "600000"}},
    "wrkchain": {"params": {"fee_purchase_storage": "5000000000", "default_storage_limit": "50000", "max_storage_limit": "600000"}},
    "staking": {"params": {"unbonding_time": "1814400s", "max_entries": 7}},
    "enterprise": {"params": {"min_accepts": "1", "ent_signers": "und1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq5x8kpm"}}
  }
}`

func write(t *testing.T, body string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "genesis.json")
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

func read(t *testing.T, path string) map[string]any {
	t.Helper()
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var doc map[string]any
	if err := json.Unmarshal(raw, &doc); err != nil {
		t.Fatal(err)
	}
	return doc
}

func at(doc map[string]any, dotted string) any {
	var v any = doc
	for _, k := range strings.Split(dotted, ".") {
		v = v.(map[string]any)[k]
	}
	return v
}

func TestTuneFundAndEnterprise(t *testing.T) {
	path := write(t, fundGenesis)
	if err := TuneFund(path); err != nil {
		t.Fatal(err)
	}
	if err := SetEnterpriseSigners(path, 2, []string{"und1a", "und1b"}); err != nil {
		t.Fatal(err)
	}
	doc := read(t, path)
	for dotted, want := range map[string]any{
		"app_state.gov.params.voting_period":             "90s",
		"app_state.gov.params.expedited_voting_period":   "60s",
		"app_state.gov.params.max_deposit_period":        "90s",
		"app_state.beacon.params.max_storage_limit":      "3000",
		"app_state.wrkchain.params.fee_purchase_storage": "1000000000",
		"app_state.staking.params.unbonding_time":        "1800s",
		"app_state.staking.params.max_entries":           float64(100),
		"app_state.enterprise.params.min_accepts":        "2",
		"app_state.enterprise.params.ent_signers":        "und1a,und1b",
	} {
		if got := at(doc, dotted); got != want {
			t.Errorf("%s = %v (%T), want %v", dotted, got, got, want)
		}
	}
	raw, _ := os.ReadFile(path)
	if !strings.Contains(string(raw), "123456789012345678901234567890") {
		t.Error("a large number lost its exact text")
	}
}

func TestMissingPathFails(t *testing.T) {
	path := write(t, strings.Replace(fundGenesis, `"max_entries": 7`, `"max_entries_renamed": 7`, 1))
	err := TuneFund(path)
	if err == nil || !strings.Contains(err.Error(), "app_state.staking.params.max_entries not found") {
		t.Fatalf("want a not-found error naming the path, got %v", err)
	}
}
