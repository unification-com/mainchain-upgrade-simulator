// Command gencompare compares two generated trees - the bash and Go generators' output for the same config - after
// masking what is random on every run. It exits 1 if anything else differs.
//
//	go -C generator run ./cmd/gencompare [-skip glob]... <bash generated dir> <go generated dir>
package main

import (
	"flag"
	"fmt"
	"os"
	"sort"
	"strings"

	"github.com/unification-com/mainchain-upgrade-simulator/generator/internal/compare"
)

type multi []string

func (m *multi) String() string     { return strings.Join(*m, ",") }
func (m *multi) Set(v string) error { *m = append(*m, v); return nil }

func main() {
	max := flag.Int("max", 8, "differences to show per file")
	var skip multi
	flag.Var(&skip, "skip", "leave out files whose path or base name matches this glob (repeatable)")
	flag.Parse()
	if flag.NArg() != 2 {
		fmt.Fprintln(os.Stderr, "usage: gencompare [-max n] [-skip glob]... <dir A> <dir B>")
		os.Exit(2)
	}
	res, err := compare.Trees(flag.Arg(0), flag.Arg(1), *max, skip)
	if err != nil {
		fmt.Fprintln(os.Stderr, "gencompare:", err)
		os.Exit(2)
	}
	for _, rel := range res.OnlyA {
		fmt.Println("only in A:", rel)
	}
	for _, rel := range res.OnlyB {
		fmt.Println("only in B:", rel)
	}
	files := make([]string, 0, len(res.Diffs))
	for rel := range res.Diffs {
		files = append(files, rel)
	}
	sort.Strings(files)
	for _, rel := range files {
		fmt.Println("differs:", rel)
		for _, d := range res.Diffs[rel] {
			fmt.Println("   ", d)
		}
	}
	if !res.Empty() {
		os.Exit(1)
	}
	fmt.Println("no differences beyond randomness")
}
