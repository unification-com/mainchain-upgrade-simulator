// Package render fills the __NAME__ placeholders of a file in templates/ - the templates both generators share.
package render

import (
	"fmt"
	"os"
	"regexp"
	"strings"
)

var placeholder = regexp.MustCompile(`__[A-Z0-9_]+__`)

// File renders the template at src into dst. Every placeholder must have a value and every value must be used, so a
// template and its caller cannot drift apart unnoticed.
func File(src, dst string, values map[string]string) error {
	tmpl, err := os.ReadFile(src)
	if err != nil {
		return err
	}
	out := string(tmpl)
	for name, value := range values {
		token := "__" + name + "__"
		if !strings.Contains(out, token) {
			return fmt.Errorf("%s has no %s", src, token)
		}
		out = strings.ReplaceAll(out, token, value)
	}
	if left := placeholder.FindAllString(out, -1); len(left) > 0 {
		return fmt.Errorf("%s: no value for %s", src, strings.Join(left, ", "))
	}
	return os.WriteFile(dst, []byte(out), 0o644)
}
