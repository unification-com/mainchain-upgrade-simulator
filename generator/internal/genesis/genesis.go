// Package genesis makes the simulator's edits to a genesis file the chain binary created. Each edit names the JSON
// path it changes and that path must already exist, so a parameter renamed upstream fails the run instead of being
// silently skipped (the bash generator matched default values with sed, which a changed default slipped past).
package genesis

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"strings"
)

type document struct {
	path string
	root map[string]any
}

// edit loads a genesis file, applies fn and writes it back. Numbers keep their exact text.
func edit(path string, fn func(*document) error) error {
	raw, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.UseNumber()
	doc := &document{path: path}
	if err := dec.Decode(&doc.root); err != nil {
		return fmt.Errorf("%s: %w", path, err)
	}
	if err := fn(doc); err != nil {
		return err
	}
	out, err := json.MarshalIndent(doc.root, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, append(out, '\n'), 0o644)
}

// set replaces the value at a dotted path, which must exist.
func (d *document) set(dotted string, value any) error {
	keys := strings.Split(dotted, ".")
	node := d.root
	for i, k := range keys {
		v, ok := node[k]
		if !ok {
			return fmt.Errorf("%s: %s not found - has the genesis format changed?", d.path, strings.Join(keys[:i+1], "."))
		}
		if i == len(keys)-1 {
			node[k] = value
			return nil
		}
		if node, ok = v.(map[string]any); !ok {
			return fmt.Errorf("%s: %s is not an object", d.path, strings.Join(keys[:i+1], "."))
		}
	}
	return nil
}

func (d *document) setAll(values [][2]any) error {
	for _, kv := range values {
		if err := d.set(kv[0].(string), kv[1]); err != nil {
			return err
		}
	}
	return nil
}

// TuneFund sets the FUND genesis parameters a short rehearsal needs.
func TuneFund(path string) error {
	return edit(path, func(d *document) error {
		return d.setAll([][2]any{
			// governance fast enough for the upgrade proposal to pass within a rehearsal
			{"app_state.gov.params.voting_period", "90s"},
			{"app_state.gov.params.expedited_voting_period", "60s"},
			{"app_state.gov.params.max_deposit_period", "90s"},
			{"app_state.beacon.params.fee_purchase_storage", "1000000000"},
			{"app_state.wrkchain.params.fee_purchase_storage", "1000000000"},
			// BEACON/WRKChain in-state record retention. The defaults prune everything older than ~100 blocks at one
			// record per block, so on a long run the pre-upgrade records are gone by the time you look, and pre- and
			// post-upgrade records (e.g. BEACON timestamps without and with vaxildan's metadata) cannot be compared.
			// 2000/3000 keeps an upgrade-height's worth of history while still exercising pruning and storage purchases.
			{"app_state.beacon.params.default_storage_limit", "2000"},
			{"app_state.beacon.params.max_storage_limit", "3000"},
			{"app_state.wrkchain.params.default_storage_limit", "2000"},
			{"app_state.wrkchain.params.max_storage_limit", "3000"},
			// Unbonding time caps Hermes's IBC client trusting_period (templates/configs/hermes_config.toml), and an
			// upgrade halt longer than that expires the client and stops relaying. 30m allows a 20m trusting period -
			// enough for the ~16 minute halt of a large-state rehearsal. The tx runner undelegates often, so
			// max_entries rises with it: the default 7 unbonding entries per delegator/validator pair would fill up
			// long before 30m entries mature.
			{"app_state.staking.params.unbonding_time", "1800s"},
			{"app_state.staking.params.max_entries", json.Number("100")},
		})
	})
}

// SetEnterpriseSigners makes the generated enterprise accounts the eFUND purchase-order signers.
func SetEnterpriseSigners(path string, minAccepts int, signers []string) error {
	return edit(path, func(d *document) error {
		return d.setAll([][2]any{
			{"app_state.enterprise.params.min_accepts", fmt.Sprint(minAccepts)},
			{"app_state.enterprise.params.ent_signers", strings.Join(signers, ",")},
		})
	})
}
