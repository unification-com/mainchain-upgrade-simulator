// Package compare checks two generated trees (the bash and Go generators' output for one config) for differences that
// are not just randomness. Keys, mnemonics, addresses, node IDs, signatures, times and validator stakes differ on every
// run, so each such token is replaced by the place it first appears - its file and JSON pointer (or line) - before
// comparing. A token absent from one side then shows up as one difference, instead of shifting every later name.
// JSON files are compared structurally, so key order does not matter.
//
// Used while the Go generator is checked against the bash one; it goes when the bash generator does.
package compare

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"reflect"
	"regexp"
	"sort"
	"strings"
)

// random tokens: a 24-word mnemonic, a Cosmos bech32 address, a 40-hex-digit ID or address, a long base64 key or
// signature, an RFC 3339 time
var tokenRE = regexp.MustCompile(`\b(?:[a-z]+ ){23}[a-z]+\b` +
	`|\b(?:und|cosmos)(?:valoper|valcons)?1[02-9ac-hj-np-z]{38}\b` +
	`|\b[0-9A-Fa-f]{40}\b` +
	`|[A-Za-z0-9+/]{40,}={0,2}` +
	`|\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?Z`)

var hex40 = regexp.MustCompile(`^[0-9A-Fa-f]{40}$`)

type masker struct {
	names map[string]string
	stake *regexp.Regexp // this side's validator stake amounts, if any
}

func (m *masker) name(token, loc string) string {
	key := token
	if hex40.MatchString(token) {
		key = strings.ToLower(token) // the same address is upper case in one file and lower in another
	}
	if n, ok := m.names[key]; ok {
		return n
	}
	n := "<" + loc + ">"
	m.names[key] = n
	return n
}

func (m *masker) mask(s, loc string) string {
	s = tokenRE.ReplaceAllStringFunc(s, func(tok string) string { return m.name(tok, loc) })
	if m.stake != nil {
		s = m.stake.ReplaceAllStringFunc(s, func(tok string) string { return m.name("stake:"+tok, loc) })
	}
	return s
}

// maskJSON walks a decoded document in a fixed order (object keys sorted) and masks every string and number.
func (m *masker) maskJSON(v any, loc string) any {
	switch t := v.(type) {
	case map[string]any:
		keys := make([]string, 0, len(t))
		for k := range t {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		out := make(map[string]any, len(t))
		for _, k := range keys {
			out[k] = m.maskJSON(t[k], loc+"/"+k)
		}
		return out
	case []any:
		out := make([]any, len(t))
		for i, e := range t {
			out[i] = m.maskJSON(e, fmt.Sprintf("%s/%d", loc, i))
		}
		return out
	case string:
		return m.mask(t, loc)
	case json.Number:
		return m.mask(t.String(), loc)
	}
	return v
}

// skipped reports whether a file is left out: a pattern matches its path or its base name.
func skipped(rel string, skip []string) bool {
	for _, pattern := range skip {
		if ok, _ := filepath.Match(pattern, rel); ok {
			return true
		}
		if ok, _ := filepath.Match(pattern, filepath.Base(rel)); ok {
			return true
		}
	}
	return false
}

func files(root string, skip []string) ([]string, error) {
	var out []string
	err := filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return err
		}
		rel, err := filepath.Rel(root, path)
		if err == nil && !skipped(rel, skip) {
			out = append(out, rel)
		}
		return err
	})
	sort.Strings(out)
	return out, err
}

func decodeJSON(raw []byte) (any, error) {
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.UseNumber()
	var v any
	err := dec.Decode(&v)
	return v, err
}

// stakeAmounts collects the self-delegation amounts from every gentx in the tree's genesis files - random per run.
func stakeAmounts(root string, rels []string) (*regexp.Regexp, error) {
	seen := map[string]bool{}
	for _, rel := range rels {
		if filepath.Base(rel) != "genesis.json" {
			continue
		}
		raw, err := os.ReadFile(filepath.Join(root, rel))
		if err != nil {
			return nil, err
		}
		var doc struct {
			AppState struct {
				Genutil struct {
					GenTxs []struct {
						Body struct {
							Messages []struct {
								Value struct {
									Amount string `json:"amount"`
								} `json:"value"`
							} `json:"messages"`
						} `json:"body"`
					} `json:"gen_txs"`
				} `json:"genutil"`
			} `json:"app_state"`
		}
		if json.Unmarshal(raw, &doc) != nil {
			continue
		}
		for _, tx := range doc.AppState.Genutil.GenTxs {
			for _, msg := range tx.Body.Messages {
				if msg.Value.Amount != "" {
					seen[regexp.QuoteMeta(msg.Value.Amount)] = true
				}
			}
		}
	}
	if len(seen) == 0 {
		return nil, nil
	}
	alts := make([]string, 0, len(seen))
	for a := range seen {
		alts = append(alts, a)
	}
	sort.Strings(alts)
	return regexp.Compile(`\b(?:` + strings.Join(alts, "|") + `)\b`)
}

// normalised is one file's content after masking: a JSON value, or text lines.
type normalised struct {
	json  any
	lines []string
}

func load(root string, skip []string) (map[string]normalised, []string, error) {
	rels, err := files(root, skip)
	if err != nil {
		return nil, nil, err
	}
	stake, err := stakeAmounts(root, rels)
	if err != nil {
		return nil, nil, err
	}
	m := &masker{names: map[string]string{}, stake: stake}
	out := make(map[string]normalised, len(rels))
	for _, rel := range rels {
		raw, err := os.ReadFile(filepath.Join(root, rel))
		if err != nil {
			return nil, nil, err
		}
		if strings.HasSuffix(rel, ".json") {
			if v, err := decodeJSON(raw); err == nil {
				out[rel] = normalised{json: m.maskJSON(v, rel+"#")}
				continue
			}
		}
		lines := strings.Split(string(raw), "\n")
		for i, l := range lines {
			lines[i] = m.mask(l, fmt.Sprintf("%s:%d", rel, i+1))
		}
		out[rel] = normalised{lines: lines}
	}
	return out, rels, nil
}

// Result lists the files only one tree has, and the differences in the files both have.
type Result struct {
	OnlyA, OnlyB []string
	Diffs        map[string][]string // file -> differences
}

func (r Result) Empty() bool { return len(r.OnlyA) == 0 && len(r.OnlyB) == 0 && len(r.Diffs) == 0 }

// Trees compares two generated trees, reporting at most maxPerFile differences per file. Files matching a skip pattern
// (against the relative path or the base name) are left out entirely, so they do not influence how tokens are named
// either - for the parts a generator does not produce yet.
func Trees(a, b string, maxPerFile int, skip []string) (Result, error) {
	na, relsA, err := load(a, skip)
	if err != nil {
		return Result{}, err
	}
	nb, relsB, err := load(b, skip)
	if err != nil {
		return Result{}, err
	}
	res := Result{Diffs: map[string][]string{}}
	for _, rel := range relsA {
		if _, ok := nb[rel]; !ok {
			res.OnlyA = append(res.OnlyA, rel)
		}
	}
	for _, rel := range relsB {
		fa, ok := na[rel]
		if !ok {
			res.OnlyB = append(res.OnlyB, rel)
			continue
		}
		var diffs []string
		fb := nb[rel]
		if fa.json != nil && fb.json != nil {
			diffJSON(fa.json, fb.json, "", &diffs, maxPerFile)
		} else {
			diffLines(fa.lines, fb.lines, &diffs, maxPerFile)
		}
		if len(diffs) > 0 {
			res.Diffs[rel] = diffs
		}
	}
	return res, nil
}

func short(v any) string {
	out, _ := json.Marshal(v)
	if len(out) > 120 {
		return string(out[:117]) + "..."
	}
	return string(out)
}

func diffJSON(a, b any, ptr string, out *[]string, max int) {
	if len(*out) >= max || reflect.DeepEqual(a, b) {
		return
	}
	ma, okA := a.(map[string]any)
	mb, okB := b.(map[string]any)
	if okA && okB {
		keys := map[string]bool{}
		for k := range ma {
			keys[k] = true
		}
		for k := range mb {
			keys[k] = true
		}
		sorted := make([]string, 0, len(keys))
		for k := range keys {
			sorted = append(sorted, k)
		}
		sort.Strings(sorted)
		for _, k := range sorted {
			va, inA := ma[k]
			vb, inB := mb[k]
			switch {
			case !inA:
				*out = append(*out, fmt.Sprintf("%s/%s only in B: %s", ptr, k, short(vb)))
			case !inB:
				*out = append(*out, fmt.Sprintf("%s/%s only in A: %s", ptr, k, short(va)))
			default:
				diffJSON(va, vb, ptr+"/"+k, out, max)
			}
			if len(*out) >= max {
				return
			}
		}
		return
	}
	sa, okA := a.([]any)
	sb, okB := b.([]any)
	if okA && okB && len(sa) == len(sb) {
		// arrays the chain sorts by a random key (e.g. bank balances by address) hold the same elements in another order
		if sameElements(sa, sb) {
			return
		}
		for i := range sa {
			diffJSON(sa[i], sb[i], fmt.Sprintf("%s/%d", ptr, i), out, max)
		}
		return
	}
	*out = append(*out, fmt.Sprintf("%s: A=%s B=%s", ptr, short(a), short(b)))
}

func sameElements(a, b []any) bool {
	canon := func(s []any) []string {
		out := make([]string, len(s))
		for i, e := range s {
			raw, _ := json.Marshal(e) // map keys marshal sorted, so equal values give equal text
			out[i] = string(raw)
		}
		sort.Strings(out)
		return out
	}
	return reflect.DeepEqual(canon(a), canon(b))
}

func diffLines(a, b []string, out *[]string, max int) {
	n := len(a)
	if len(b) > n {
		n = len(b)
	}
	for i := 0; i < n && len(*out) < max; i++ {
		var la, lb string
		if i < len(a) {
			la = a[i]
		}
		if i < len(b) {
			lb = b[i]
		}
		if la != lb {
			*out = append(*out, fmt.Sprintf("line %d: A=%q B=%q", i+1, la, lb))
		}
	}
}
