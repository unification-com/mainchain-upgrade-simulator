// Package bech32 encodes and decodes BIP-173 bech32 strings - the address format of Cosmos chains - so the generator
// can derive an account's hex, validator and consensus addresses itself instead of asking the chain binary.
package bech32

import (
	"fmt"
	"strings"
)

const charset = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"

var generator = [5]uint32{0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3}

func polymod(values []byte) uint32 {
	chk := uint32(1)
	for _, v := range values {
		top := chk >> 25
		chk = (chk&0x1ffffff)<<5 ^ uint32(v)
		for i := 0; i < 5; i++ {
			if (top>>i)&1 == 1 {
				chk ^= generator[i]
			}
		}
	}
	return chk
}

func hrpExpand(hrp string) []byte {
	out := make([]byte, 0, len(hrp)*2+1)
	for _, c := range hrp {
		out = append(out, byte(c>>5))
	}
	out = append(out, 0)
	for _, c := range hrp {
		out = append(out, byte(c&31))
	}
	return out
}

// convertBits regroups a byte slice from `from`-bit to `to`-bit groups.
func convertBits(data []byte, from, to uint, pad bool) ([]byte, error) {
	var acc, bits uint
	maxv := uint(1)<<to - 1
	var out []byte
	for _, b := range data {
		if uint(b)>>from != 0 {
			return nil, fmt.Errorf("invalid %d-bit group %d", from, b)
		}
		acc = acc<<from | uint(b)
		bits += from
		for bits >= to {
			bits -= to
			out = append(out, byte(acc>>bits&maxv))
		}
	}
	if pad {
		if bits > 0 {
			out = append(out, byte(acc<<(to-bits)&maxv))
		}
	} else if bits >= from || acc<<(to-bits)&maxv != 0 {
		return nil, fmt.Errorf("invalid padding")
	}
	return out, nil
}

// Encode returns the bech32 string for data under the human-readable prefix hrp.
func Encode(hrp string, data []byte) (string, error) {
	five, err := convertBits(data, 8, 5, true)
	if err != nil {
		return "", err
	}
	values := append(hrpExpand(hrp), five...)
	mod := polymod(append(values, 0, 0, 0, 0, 0, 0)) ^ 1
	var sb strings.Builder
	sb.WriteString(hrp)
	sb.WriteByte('1')
	for _, v := range five {
		sb.WriteByte(charset[v])
	}
	for i := 0; i < 6; i++ {
		sb.WriteByte(charset[(mod>>(5*(5-i)))&31])
	}
	return sb.String(), nil
}

// Decode splits a bech32 string into its prefix and data bytes, verifying the checksum.
func Decode(s string) (string, []byte, error) {
	if strings.ToLower(s) != s {
		return "", nil, fmt.Errorf("%q: mixed or upper case", s)
	}
	sep := strings.LastIndexByte(s, '1')
	if sep < 1 || sep+7 > len(s) {
		return "", nil, fmt.Errorf("%q: no prefix separator or too short", s)
	}
	hrp := s[:sep]
	values := make([]byte, 0, len(s)-sep-1)
	for _, c := range s[sep+1:] {
		i := strings.IndexRune(charset, c)
		if i < 0 {
			return "", nil, fmt.Errorf("%q: invalid character %q", s, c)
		}
		values = append(values, byte(i))
	}
	if polymod(append(hrpExpand(hrp), values...)) != 1 {
		return "", nil, fmt.Errorf("%q: bad checksum", s)
	}
	data, err := convertBits(values[:len(values)-6], 5, 8, false)
	if err != nil {
		return "", nil, fmt.Errorf("%q: %w", s, err)
	}
	return hrp, data, nil
}
