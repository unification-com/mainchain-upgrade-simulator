package stake

import (
	"encoding/json"
	"math/rand/v2"
	"strconv"
	"strings"
	"testing"

	"github.com/unification-com/mainchain-upgrade-simulator/generator/internal/config"
)

func ptr[T any](v T) *T { return &v }

var staking = config.Staking{
	MinStake: 100, MaxStake: 200, SmallMinStake: 1, SmallMaxStake: 10,
	StakeOverrides: []config.StakeOverride{
		{Validator: 1, Rate: ptr(json.Number("0")), MaxRate: ptr(json.Number("0.1")), Stake: ptr(uint64(240)), MinSelf: ptr(uint64(1000))},
		{Validator: 2, Rate: ptr(json.Number("0.03"))},
	},
}

func amount(t *testing.T, s Stake, denom string) uint64 {
	t.Helper()
	v, err := strconv.ParseUint(strings.TrimSuffix(s.Coins, denom), 10, 64)
	if err != nil || !strings.HasSuffix(s.Coins, denom) {
		t.Fatalf("coins %q: %v", s.Coins, err)
	}
	return v
}

func TestOverrides(t *testing.T) {
	rng := rand.New(rand.NewPCG(1, 2))
	s := ForValidator(1, "nund", staking, true, rng)
	want := Stake{Coins: "240nund", CommissionRate: "0", CommissionMaxRate: "0.1", CommissionMaxChangeRate: "0.01", MinSelfDelegation: "1000"}
	if s != want {
		t.Fatalf("validator 1: got %+v, want %+v", s, want)
	}

	s = ForValidator(2, "nund", staking, true, rng)
	if s.CommissionRate != "0.03" || s.CommissionMaxRate != "0.1" || s.MinSelfDelegation != "1" {
		t.Fatalf("validator 2 keeps defaults except its rate: %+v", s)
	}
	if a := amount(t, s, "nund"); a < 100 || a > 200 {
		t.Fatalf("validator 2 has no stake override, so it is random in range: %d", a)
	}

	// the IBC chain's validator 1 shares a number with the FUND one but takes none of its overrides
	if s := ForValidator(1, "stake", staking, false, rng); s.CommissionRate != "0.1" || s.MinSelfDelegation != "1" {
		t.Fatalf("overrides applied with useOverrides off: %+v", s)
	}
}

func TestRandomRanges(t *testing.T) {
	rng := rand.New(rand.NewPCG(3, 4))
	for i := 0; i < 500; i++ {
		if a := amount(t, ForValidator(3, "nund", staking, true, rng), "nund"); a < 100 || a > 200 {
			t.Fatalf("validator 3 outside [100, 200]: %d", a)
		}
		if a := amount(t, ForValidator(5, "nund", staking, true, rng), "nund"); a < 1 || a > 10 {
			t.Fatalf("validator 5 (every fifth) outside the small range [1, 10]: %d", a)
		}
	}
}
