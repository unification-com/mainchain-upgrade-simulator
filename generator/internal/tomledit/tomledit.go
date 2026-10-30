// Package tomledit changes single values in the config.toml and app.toml the chain binary writes, leaving every other
// byte - comments, layout, key order - as it was. A full TOML encoder would rewrite the SDK's commented templates; the
// files are flat `key = value` lines under `[section]` headers, which is all this handles. As with the genesis edits,
// a key that is not there is an error rather than a silent no-op.
package tomledit

import (
	"fmt"
	"os"
	"strings"
)

type File struct {
	path  string
	lines []string
}

func Load(path string) (*File, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	return &File{path: path, lines: strings.Split(string(raw), "\n")}, nil
}

// literal renders a value as TOML: strings basic-quoted, booleans bare.
func literal(v any) (string, error) {
	switch t := v.(type) {
	case bool:
		return fmt.Sprint(t), nil
	case string:
		if strings.ContainsAny(t, "\"\\\n") {
			return "", fmt.Errorf("value %q needs escaping, which this editor does not do", t)
		}
		return `"` + t + `"`, nil
	}
	return "", fmt.Errorf("unsupported value type %T", v)
}

// Set replaces the value of key in section ("" for the top level, before the first header).
func (f *File) Set(section, key string, value any) error {
	lit, err := literal(value)
	if err != nil {
		return fmt.Errorf("%s: %s.%s: %w", f.path, section, key, err)
	}
	current := ""
	for i, line := range f.lines {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "[") && strings.HasSuffix(trimmed, "]") {
			current = strings.TrimSpace(strings.Trim(trimmed, "[]"))
			continue
		}
		if current != section {
			continue
		}
		name, _, found := strings.Cut(trimmed, "=")
		if found && strings.TrimSpace(name) == key {
			f.lines[i] = key + " = " + lit
			return nil
		}
	}
	if section == "" {
		return fmt.Errorf("%s: top-level %s not found", f.path, key)
	}
	return fmt.Errorf("%s: [%s] %s not found", f.path, section, key)
}

func (f *File) Save() error {
	return os.WriteFile(f.path, []byte(strings.Join(f.lines, "\n")), 0o644)
}

// Setting is one value to set: Section "" is the top level.
type Setting struct {
	Section, Key string
	Value        any
}

// Edit applies settings to the file at path in one load and save.
func Edit(path string, settings ...Setting) error {
	f, err := Load(path)
	if err != nil {
		return err
	}
	for _, s := range settings {
		if err := f.Set(s.Section, s.Key, s.Value); err != nil {
			return err
		}
	}
	return f.Save()
}
