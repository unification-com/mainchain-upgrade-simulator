// Command gen generates a simulator network from config.json: node homes, wallets, genesis files and
// docker-compose.yml. It replaces scripts/bash/generate.sh stage by stage (make gen-go); until the port is complete,
// make gen is still the bash generator.
//
// Run it from the repo root after the config has been validated (make gen-go does both).
package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"

	"github.com/unification-com/mainchain-upgrade-simulator/generator/internal/config"
	"github.com/unification-com/mainchain-upgrade-simulator/generator/internal/generate"
	"github.com/unification-com/mainchain-upgrade-simulator/generator/internal/paths"
	"github.com/unification-com/mainchain-upgrade-simulator/generator/internal/thirdparty"
)

func main() {
	root := flag.String("root", ".", "simulator repo root")
	configPath := flag.String("config", "config.json", "config file, relative to the root")
	flag.Parse()

	if err := run(*root, *configPath); err != nil {
		fmt.Fprintln(os.Stderr, "gen:", err)
		os.Exit(1)
	}
}

func run(root, configPath string) error {
	root, err := filepath.Abs(root)
	if err != nil {
		return err
	}
	cfg, err := config.Load(filepath.Join(root, configPath))
	if err != nil {
		return err
	}
	p := paths.New(root)

	goVersion, err := thirdparty.UpgradeGoVersion(cfg.Apps.Und.Upgrade.Branch)
	if err != nil {
		return err
	}
	fmt.Printf("upgrade target %s builds with Go %s\n", cfg.Apps.Und.Upgrade.Branch, goVersion)

	if err := p.ResetGenerated(); err != nil {
		return fmt.Errorf("resetting %s: %w", p.Generated, err)
	}
	if err := thirdparty.EnsureBinaries(p, cfg); err != nil {
		return err
	}
	if err := generate.Run(p, cfg, goVersion); err != nil {
		return err
	}

	fmt.Printf("network generated: %s and %s\n", p.Generated, p.DockerCompose)
	return nil
}
