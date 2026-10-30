// Package thirdparty fetches the release binaries the generator runs on the host (the genesis und and gaiad, which
// build the genesis files and keys) and reads facts about the upgrade target from GitHub.
package thirdparty

import (
	"archive/tar"
	"bufio"
	"bytes"
	"compress/gzip"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/unification-com/mainchain-upgrade-simulator/generator/internal/config"
	"github.com/unification-com/mainchain-upgrade-simulator/generator/internal/paths"
)

var client = &http.Client{Timeout: 5 * time.Minute}

const readme = "# Third party binaries\n\nThe `bin` directory contains automatically downloaded binaries\nrequired by the `generate.sh` script.\n"

// UndBin is the genesis und release, used on the host to create keys and the FUND genesis.
func UndBin(p paths.Paths, cfg *config.Config) string {
	return filepath.Join(p.ThirdPartyBin, "und_"+cfg.Apps.Und.Genesis.Version)
}

// GaiadBin is the Gaia release used on the host to create keys and the counterparty genesis.
func GaiadBin(p paths.Paths, cfg *config.Config) string {
	return filepath.Join(p.ThirdPartyBin, "gaiad_"+cfg.Apps.IBC.Version)
}

// EnsureBinaries downloads any host binary that is not already in third_party/bin.
func EnsureBinaries(p paths.Paths, cfg *config.Config) error {
	if err := os.MkdirAll(p.ThirdPartyBin, 0o755); err != nil {
		return err
	}
	readmePath := filepath.Join(p.ThirdParty, "README.md")
	if _, err := os.Stat(readmePath); os.IsNotExist(err) {
		if err := os.WriteFile(readmePath, []byte(readme), 0o644); err != nil {
			return err
		}
	}

	und := cfg.Apps.Und.Genesis.Version
	if err := ensure(UndBin(p, cfg),
		fmt.Sprintf("https://github.com/unification-com/mainchain/releases/download/v%s/und_v%s_linux_x86_64.tar.gz", und, und),
		"und"); err != nil {
		return err
	}
	gaia := cfg.Apps.IBC.Version
	return ensure(GaiadBin(p, cfg),
		fmt.Sprintf("https://github.com/cosmos/gaia/releases/download/v%s/gaiad-v%s-linux-amd64", gaia, gaia),
		"")
}

// ensure downloads url to dest unless dest exists. A non-empty tarMember means url is a .tar.gz holding the binary
// under that name; otherwise url is the binary itself. The file is written beside dest and renamed into place, so an
// interrupted download never leaves a truncated binary that the next run would trust.
func ensure(dest, url, tarMember string) error {
	if _, err := os.Stat(dest); err == nil {
		return nil
	}
	fmt.Printf("%s not found. Downloading %s\n", filepath.Base(dest), url)

	body, err := get(url)
	if err != nil {
		return err
	}
	defer body.Close()

	var bin io.Reader = body
	if tarMember != "" {
		if bin, err = tarEntry(body, tarMember); err != nil {
			return fmt.Errorf("%s: %w", url, err)
		}
	}

	tmp := dest + ".download"
	f, err := os.OpenFile(tmp, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o755)
	if err != nil {
		return err
	}
	if _, err := io.Copy(f, bin); err != nil {
		f.Close()
		os.Remove(tmp)
		return fmt.Errorf("downloading %s: %w", url, err)
	}
	if err := f.Close(); err != nil {
		os.Remove(tmp)
		return err
	}
	return os.Rename(tmp, dest)
}

func get(url string) (io.ReadCloser, error) {
	res, err := client.Get(url)
	if err != nil {
		return nil, err
	}
	if res.StatusCode != http.StatusOK {
		res.Body.Close()
		return nil, fmt.Errorf("GET %s: %s", url, res.Status)
	}
	return res.Body, nil
}

// tarEntry returns a reader positioned at the regular file called name (at any depth) in a gzipped tarball.
func tarEntry(r io.Reader, name string) (io.Reader, error) {
	gz, err := gzip.NewReader(r)
	if err != nil {
		return nil, err
	}
	tr := tar.NewReader(gz)
	for {
		hdr, err := tr.Next()
		if err == io.EOF {
			return nil, fmt.Errorf("no %q in the archive", name)
		}
		if err != nil {
			return nil, err
		}
		if hdr.Typeflag == tar.TypeReg && filepath.Base(hdr.Name) == name {
			return tr, nil
		}
	}
}

// UpgradeGoVersion is the major.minor Go release the upgrade target needs (the go directive of its go.mod, e.g.
// "go 1.26.5" -> "1.26"), used as the golang image tag that builds it. Reading it per run means an SDK Go-floor bump
// needs no Dockerfile edit, and a branch or tag that does not exist fails here, before any Docker build.
func UpgradeGoVersion(ref string) (string, error) {
	url := fmt.Sprintf("https://raw.githubusercontent.com/unification-com/mainchain/%s/go.mod", ref)
	body, err := get(url)
	if err != nil {
		return "", fmt.Errorf("cannot read mainchain %s/go.mod - does that branch or tag exist? %w", ref, err)
	}
	defer body.Close()
	gomod, err := io.ReadAll(body)
	if err != nil {
		return "", err
	}
	return goMajorMinor(gomod)
}

func goMajorMinor(gomod []byte) (string, error) {
	sc := bufio.NewScanner(bytes.NewReader(gomod))
	for sc.Scan() {
		fields := strings.Fields(sc.Text())
		if len(fields) == 2 && fields[0] == "go" {
			parts := strings.Split(fields[1], ".")
			if len(parts) < 2 {
				return "", fmt.Errorf("unexpected go directive %q", sc.Text())
			}
			return parts[0] + "." + parts[1], nil
		}
	}
	return "", fmt.Errorf("go.mod has no go directive")
}
