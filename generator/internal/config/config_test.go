package config

import (
	"os"
	"strings"
	"testing"
)

const examplePath = "../../../example.config.json"

func TestExampleConfigLoads(t *testing.T) {
	cfg, err := Load(examplePath)
	if err != nil {
		t.Fatalf("example.config.json: %v", err)
	}
	if cfg.Apps.Und.Upgrade.PlanName == "" || cfg.Apps.Und.Nodes.NumValidators < 1 || cfg.Docker.Network.Subnet == "" {
		t.Fatalf("example.config.json decoded with empty fields: %+v", cfg)
	}
	if len(cfg.Apps.Und.Staking.StakeOverrides) == 0 {
		t.Fatal("example.config.json is expected to carry stake overrides")
	}
}

// Every key in config.json must have a field, or strict decoding would reject the operator's file - the example
// carries every optional section, so a clean load proves the structs cover it.
func TestUnknownKeyIsRejected(t *testing.T) {
	raw, err := os.ReadFile(examplePath)
	if err != nil {
		t.Fatal(err)
	}
	misspelt := strings.Replace(string(raw), `"num_sentries"`, `"num_sentrys"`, 1)
	_, err = Parse([]byte(misspelt))
	if err == nil || !strings.Contains(err.Error(), "num_sentrys") {
		t.Fatalf("want an unknown-field error naming num_sentrys, got %v", err)
	}
}

func TestTrailingContentIsRejected(t *testing.T) {
	raw, err := os.ReadFile(examplePath)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := Parse(append(raw, []byte(`{}`)...)); err == nil {
		t.Fatal("want an error for content after the top-level object")
	}
}

// Commission fractions reach the und CLI as text, so they must survive decoding exactly as written.
func TestFractionsKeepTheirText(t *testing.T) {
	cfg, err := Parse([]byte(`{"apps":{"und":{"staking":{"stake_overrides":[{"validator":1,"rate":0.10,"max_rate":0}]}}}}`))
	if err != nil {
		t.Fatal(err)
	}
	o := cfg.Apps.Und.Staking.StakeOverrides[0]
	if o.Rate.String() != "0.10" || o.MaxRate.String() != "0" || o.MaxChangeRate != nil {
		t.Fatalf("got rate=%v max_rate=%v max_change_rate=%v", o.Rate, o.MaxRate, o.MaxChangeRate)
	}
}
