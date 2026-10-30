package thirdparty

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

func TestGoMajorMinor(t *testing.T) {
	for gomod, want := range map[string]string{
		"module x\n\ngo 1.26.5\n":             "1.26",
		"module x\ngo 1.23\ntoolchain go1.24": "1.23",
	} {
		got, err := goMajorMinor([]byte(gomod))
		if err != nil || got != want {
			t.Errorf("%q: got %q, %v; want %q", gomod, got, err, want)
		}
	}
	if _, err := goMajorMinor([]byte("module x\n")); err == nil {
		t.Error("want an error for a go.mod with no go directive")
	}
}

func tarball(t *testing.T, files map[string]string) []byte {
	t.Helper()
	var buf bytes.Buffer
	gz := gzip.NewWriter(&buf)
	tw := tar.NewWriter(gz)
	for name, body := range files {
		if err := tw.WriteHeader(&tar.Header{Name: name, Mode: 0o755, Size: int64(len(body)), Typeflag: tar.TypeReg}); err != nil {
			t.Fatal(err)
		}
		if _, err := tw.Write([]byte(body)); err != nil {
			t.Fatal(err)
		}
	}
	tw.Close()
	gz.Close()
	return buf.Bytes()
}

func TestEnsure(t *testing.T) {
	tgz := tarball(t, map[string]string{"LICENSE": "text", "und": "und-binary"})
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/und.tar.gz":
			w.Write(tgz)
		case "/gaiad":
			w.Write([]byte("gaiad-binary"))
		default:
			http.NotFound(w, r)
		}
	}))
	defer srv.Close()
	dir := t.TempDir()

	und := filepath.Join(dir, "und_1.0.0")
	if err := ensure(und, srv.URL+"/und.tar.gz", "und"); err != nil {
		t.Fatal(err)
	}
	gaiad := filepath.Join(dir, "gaiad_1.0.0")
	if err := ensure(gaiad, srv.URL+"/gaiad", ""); err != nil {
		t.Fatal(err)
	}
	for path, want := range map[string]string{und: "und-binary", gaiad: "gaiad-binary"} {
		got, err := os.ReadFile(path)
		if err != nil || string(got) != want {
			t.Errorf("%s: got %q, %v; want %q", path, got, err, want)
		}
		if info, _ := os.Stat(path); info.Mode().Perm()&0o100 == 0 {
			t.Errorf("%s is not executable", path)
		}
	}

	// an existing binary is trusted, not fetched again
	if err := os.WriteFile(und, []byte("local"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := ensure(und, srv.URL+"/missing", ""); err != nil {
		t.Fatalf("existing binary: %v", err)
	}

	// a failed download leaves nothing behind
	broken := filepath.Join(dir, "broken")
	if err := ensure(broken, srv.URL+"/missing", ""); err == nil {
		t.Fatal("want an error for a 404")
	}
	if err := ensure(broken, srv.URL+"/und.tar.gz", "not-there"); err == nil {
		t.Fatal("want an error for a missing tar member")
	}
	if entries, _ := filepath.Glob(filepath.Join(dir, "broken*")); len(entries) != 0 {
		t.Fatalf("failed downloads left %v", entries)
	}
}
