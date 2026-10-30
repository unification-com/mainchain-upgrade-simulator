// Package stake decides each genesis validator's self-delegation and commission.
package stake

import (
	"fmt"
	"math/rand/v2"

	"github.com/unification-com/mainchain-upgrade-simulator/generator/internal/config"
)

// Stake is one validator's gentx terms. The fractions are text so they reach the CLI exactly as configured.
type Stake struct {
	Coins                   string // e.g. "240000000000000nund"
	CommissionRate          string
	CommissionMaxRate       string
	CommissionMaxChangeRate string
	MinSelfDelegation       string
}

// ForValidator returns the terms for validator n (1-based). Unless an override sets the stake, it is random within
// the configured range - every fifth validator from the small range, to give the set an uneven distribution of power.
// Overrides apply only when useOverrides is set: they describe the FUND validators, not the IBC chain's.
func ForValidator(n int, denom string, cfg config.Staking, useOverrides bool, rng *rand.Rand) Stake {
	s := Stake{CommissionRate: "0.1", CommissionMaxRate: "0.1", CommissionMaxChangeRate: "0.01", MinSelfDelegation: "1"}
	var amount uint64
	if useOverrides {
		for _, o := range cfg.StakeOverrides {
			if o.Validator != n {
				continue
			}
			if o.Rate != nil {
				s.CommissionRate = o.Rate.String()
			}
			if o.MaxRate != nil {
				s.CommissionMaxRate = o.MaxRate.String()
			}
			if o.MaxChangeRate != nil {
				s.CommissionMaxChangeRate = o.MaxChangeRate.String()
			}
			if o.Stake != nil {
				amount = *o.Stake
			}
			if o.MinSelf != nil {
				s.MinSelfDelegation = fmt.Sprint(*o.MinSelf)
			}
		}
	}
	if amount == 0 {
		lo, hi := cfg.MinStake, cfg.MaxStake
		if n%5 == 0 {
			lo, hi = cfg.SmallMinStake, cfg.SmallMaxStake
		}
		amount = lo + rng.Uint64N(hi-lo+1)
	}
	s.Coins = fmt.Sprintf("%d%s", amount, denom)
	return s
}
