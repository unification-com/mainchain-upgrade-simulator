package render

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestFile(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "t.conf")
	dst := filepath.Join(dir, "out.conf")
	if err := os.WriteFile(src, []byte("listen __PORT__;\nname __NAME__ __NAME__;\n$request_method\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	if err := File(src, dst, map[string]string{"PORT": "1320", "NAME": "rpc1"}); err != nil {
		t.Fatal(err)
	}
	got, _ := os.ReadFile(dst)
	if string(got) != "listen 1320;\nname rpc1 rpc1;\n$request_method\n" {
		t.Fatalf("got %q", got)
	}

	if err := File(src, dst, map[string]string{"PORT": "1"}); err == nil || !strings.Contains(err.Error(), "__NAME__") {
		t.Errorf("want an error naming the unfilled placeholder, got %v", err)
	}
	if err := File(src, dst, map[string]string{"PORT": "1", "NAME": "x", "EXTRA": "y"}); err == nil || !strings.Contains(err.Error(), "__EXTRA__") {
		t.Errorf("want an error naming the unused value, got %v", err)
	}
}
