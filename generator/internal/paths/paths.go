// Package paths is every file-system location the generator reads or writes, derived from the simulator repo root.
// The layout is a contract: the Dockerfiles, the generated docker-compose.yml and the Node packages all read from it.
package paths

import (
	"fmt"
	"os"
	"path/filepath"
)

type Paths struct {
	Root string

	Templates        string
	TemplatesScripts string
	TemplatesConfigs string

	Generated           string
	NetworkUnd          string // per-node descriptor files for the FUND chain
	NetworkGaiad        string // per-node descriptor files for the IBC counterparty chain
	Assets              string
	AssetsScripts       string
	WalletsUnd          string
	WalletsGaiad        string
	NodesFund           string // node homes copied into the FUND images
	NodesGaiad          string // node homes copied into the Gaia images
	Hermes              string
	TxRunner            string
	Tmp                 string // throwaway work, removed at the end of a run
	TmpGlobalUndHome    string // throwaway node home that builds the FUND genesis
	TmpGlobalGaiadHome  string // throwaway node home that builds the Gaia genesis
	DockerLogs          string
	DockerCompose       string
	NetworkOverviewJSON string

	ThirdParty    string
	ThirdPartyBin string
}

func New(root string) Paths {
	generated := filepath.Join(root, "generated")
	network := filepath.Join(generated, "network")
	assets := filepath.Join(generated, "assets")
	wallets := filepath.Join(assets, "wallets")
	tmp := filepath.Join(generated, "tmp")
	tmpGlobal := filepath.Join(tmp, "GLOBAL")
	templates := filepath.Join(root, "templates")
	thirdParty := filepath.Join(root, "third_party")

	return Paths{
		Root: root,

		Templates:        templates,
		TemplatesScripts: filepath.Join(templates, "scripts"),
		TemplatesConfigs: filepath.Join(templates, "configs"),

		Generated:           generated,
		NetworkUnd:          filepath.Join(network, "und"),
		NetworkGaiad:        filepath.Join(network, "gaiad"),
		Assets:              assets,
		AssetsScripts:       filepath.Join(assets, "scripts"),
		WalletsUnd:          filepath.Join(wallets, "und"),
		WalletsGaiad:        filepath.Join(wallets, "gaiad"),
		NodesFund:           filepath.Join(assets, "fund_net"),
		NodesGaiad:          filepath.Join(assets, "gaiad_net"),
		Hermes:              filepath.Join(assets, "hermes"),
		TxRunner:            filepath.Join(assets, "tx_runner"),
		Tmp:                 tmp,
		TmpGlobalUndHome:    filepath.Join(tmpGlobal, ".und_mainchain"),
		TmpGlobalGaiadHome:  filepath.Join(tmpGlobal, ".gaiad"),
		DockerLogs:          filepath.Join(generated, "docker_logs"),
		DockerCompose:       filepath.Join(root, "docker-compose.yml"),
		NetworkOverviewJSON: filepath.Join(network, "overview.json"),

		ThirdParty:    thirdParty,
		ThirdPartyBin: filepath.Join(thirdParty, "bin"),
	}
}

// ResetGenerated replaces generated/ with an empty tree and copies the node-side scripts into it - a run never
// builds on the output of the previous one.
func (p Paths) ResetGenerated() error {
	if err := os.RemoveAll(p.Generated); err != nil {
		return err
	}
	for _, dir := range []string{p.NodesFund, p.WalletsUnd, p.WalletsGaiad, p.AssetsScripts, p.TxRunner,
		p.NetworkUnd, p.NetworkGaiad, p.Tmp} {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return err
		}
	}
	return copyDir(p.TemplatesScripts, p.AssetsScripts)
}

// copyDir copies the regular files of src (not sub-directories) into dst, keeping their modes - the scripts must
// stay executable inside the images.
func copyDir(src, dst string) error {
	entries, err := os.ReadDir(src)
	if err != nil {
		return err
	}
	for _, e := range entries {
		if !e.Type().IsRegular() {
			continue
		}
		info, err := e.Info()
		if err != nil {
			return err
		}
		data, err := os.ReadFile(filepath.Join(src, e.Name()))
		if err != nil {
			return err
		}
		if err := os.WriteFile(filepath.Join(dst, e.Name()), data, info.Mode().Perm()); err != nil {
			return fmt.Errorf("copying %s: %w", e.Name(), err)
		}
	}
	return nil
}
