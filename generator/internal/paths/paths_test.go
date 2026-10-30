package paths

import (
	"os"
	"path/filepath"
	"testing"
)

func TestResetGenerated(t *testing.T) {
	root := t.TempDir()
	p := New(root)
	if err := os.MkdirAll(p.TemplatesScripts, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(p.TemplatesScripts, "run_node.sh"), []byte("#!/bin/bash\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	stale := filepath.Join(p.Generated, "stale")
	if err := os.MkdirAll(stale, 0o755); err != nil {
		t.Fatal(err)
	}

	if err := p.ResetGenerated(); err != nil {
		t.Fatal(err)
	}

	if _, err := os.Stat(stale); !os.IsNotExist(err) {
		t.Errorf("previous output survived: %v", err)
	}
	for _, dir := range []string{p.NodesFund, p.WalletsUnd, p.WalletsGaiad, p.TxRunner, p.NetworkUnd, p.NetworkGaiad} {
		if info, err := os.Stat(dir); err != nil || !info.IsDir() {
			t.Errorf("%s not created: %v", dir, err)
		}
	}
	info, err := os.Stat(filepath.Join(p.AssetsScripts, "run_node.sh"))
	if err != nil || info.Mode().Perm() != 0o755 {
		t.Fatalf("script not copied with its mode: %v %v", info, err)
	}
}
