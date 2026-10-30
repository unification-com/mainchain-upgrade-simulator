package generate

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/unification-com/mainchain-upgrade-simulator/generator/internal/compose"
	"github.com/unification-com/mainchain-upgrade-simulator/generator/internal/network"
)

// networkName is the compose network. The bash generator meant to prefix it with the container prefix but read an
// unset variable, so every generated network has been called this; changing it now would gain nothing.
const networkName = "up_sim_network"

// hermes ports, fixed inside its container and published as-is
const hermesRESTPort, hermesPrometheusPort = 3000, 3001

func (s *side) container(n network.Node) string { return s.containerPrefix + "_" + n.Name }

// sortedByName returns nodes in name order - the order the bash generator listed them in (a glob of node_*.json).
func sortedByName(nodes []network.Node) []network.Node {
	sorted := append([]network.Node(nil), nodes...)
	sort.Slice(sorted, func(i, j int) bool { return sorted[i].Name < sorted[j].Name })
	return sorted
}

func ports(n network.Node) []compose.Quoted {
	out := []compose.Quoted{compose.Port(n.P2PPort)}
	if n.Type == network.RPC {
		out = append(out, compose.Port(n.RPCPort), compose.Port(n.RESTPort), compose.Port(n.GRPCPort))
	}
	return out
}

func rpcFlag(n network.Node) compose.Quoted {
	if n.Type == network.RPC {
		return "1"
	}
	return "0"
}

// service is the part of every container's definition that does not depend on what runs in it.
func (g *generator) service(container, dockerfile, ip, script, logDir string, args, env map[string]compose.Quoted, ports []compose.Quoted) compose.Service {
	return compose.Service{
		Hostname:      container,
		ContainerName: container,
		Build:         compose.Build{Context: ".", Dockerfile: dockerfile, Args: args},
		Environment:   env,
		Command:       []string{"/bin/bash", "-c", "cd /root && ./" + script},
		Networks:      map[string]compose.ServiceNetwork{networkName: {IPv4Address: ip}},
		Volumes:       []string{filepath.Join(g.p.DockerLogs, logDir) + ":/root/out:rw"},
		Ports:         ports,
	}
}

func (g *generator) writeCompose() error {
	und, ibc := g.cfg.Apps.Und, g.cfg.Apps.IBC
	services := map[string]compose.Service{}

	for _, n := range g.fund.all {
		c := g.fund.container(n)
		services[c] = g.service(c, "docker/und.Dockerfile", n.IP, "run_node.sh", n.Name,
			map[string]compose.Quoted{
				"NODE_NAME":          compose.Quoted(n.Name),
				"UPGRADE_PLAN_NAME":  compose.Quoted(und.Upgrade.PlanName),
				"UND_GENESIS_VER":    compose.Quoted(und.Genesis.Version),
				"UND_UPGRADE_BRANCH": compose.Quoted(und.Upgrade.Branch),
				"GO_VERSION":         compose.Quoted(g.upgradeGoVersion),
				"COSMOVISOR_VER":     compose.Quoted(g.cfg.Apps.Cosmovisor.Version),
			},
			map[string]compose.Quoted{
				"DAEMON_RESTART_DELAY":  "5s",
				"DAEMON_SHUTDOWN_GRACE": "5s",
				"UNSAFE_SKIP_BACKUP":    "true",
				"IS_RPC_NODE":           rpcFlag(n),
			},
			ports(n))
	}
	for _, n := range g.ibc.all {
		c := g.ibc.container(n)
		services[c] = g.service(c, "docker/ibc_gaiad.Dockerfile", n.IP, "run_ibc_gaiad.sh", "ibc_gaiad_"+n.Name,
			map[string]compose.Quoted{"NODE_NAME": compose.Quoted(n.Name), "IBC_VER": compose.Quoted(ibc.Version)},
			map[string]compose.Quoted{"IS_RPC_NODE": rpcFlag(n)},
			ports(n))
	}

	fundRPC, err := g.fund.node("rpc1")
	if err != nil {
		return err
	}
	ibcRPC, err := g.ibc.node("rpc1")
	if err != nil {
		return err
	}
	g.hermesIP = g.alloc.NextIP() // after every node, as before
	services[g.hermesContainer()] = g.service(g.hermesContainer(), "docker/hermes.Dockerfile", g.hermesIP, "run_hermes.sh", "hermes",
		map[string]compose.Quoted{
			"MNEMONIC":     compose.Quoted(g.hermesMnemonic),
			"CHAIN_ID":     compose.Quoted(g.fund.chainID),
			"IBC_CHAIN_ID": compose.Quoted(g.ibc.chainID),
			"HERMES_VER":   compose.Quoted(ibc.HermesVersion),
		},
		map[string]compose.Quoted{
			"FUND_CHAIN_ID":  compose.Quoted(g.fund.chainID),
			"FUND_RPC_IP":    compose.Quoted(fundRPC.IP),
			"FUND_RPC_PORT":  compose.Quoted(fmt.Sprint(fundRPC.RPCPort)),
			"FUND_GRPC_PORT": compose.Quoted(fmt.Sprint(fundRPC.GRPCPort)),
			"IBC_CHAIN_ID":   compose.Quoted(g.ibc.chainID),
			"IBC_RPC_IP":     compose.Quoted(ibcRPC.IP),
			"IBC_RPC_PORT":   compose.Quoted(fmt.Sprint(ibcRPC.RPCPort)),
			"IBC_GRPC_PORT":  compose.Quoted(fmt.Sprint(ibcRPC.GRPCPort)),
		},
		[]compose.Quoted{compose.Port(hermesRESTPort), compose.Port(hermesPrometheusPort)})

	return compose.File{
		Services: services,
		Networks: map[string]compose.Network{networkName: {IPAM: compose.IPAM{
			Driver: "default",
			Config: []compose.IPAMConfig{{Subnet: g.cfg.Docker.Network.Subnet + ".0/24"}},
		}}},
	}.Write(g.p.DockerCompose)
}

func (g *generator) hermesContainer() string { return g.cfg.Docker.ContainerPrefix + "ibc_hermes" }

// ibcDenom is nund as it appears on the Gaia chain after crossing channel-0, the first channel Hermes opens.
func ibcDenom() string {
	sum := sha256.Sum256([]byte("transfer/channel-0/nund"))
	return "ibc/" + strings.ToUpper(hex.EncodeToString(sum[:]))
}

type overviewNode struct {
	Name            string `json:"name"`
	Type            string `json:"type"`
	IP              string `json:"ip"`
	P2PPort         int    `json:"p2p_port,string"`
	RPCPort         int    `json:"rpc_port,string"`
	RESTPort        int    `json:"rest_port,string"`
	GRPCPort        int    `json:"grpc_port,string"`
	DockerContainer string `json:"docker_container"`
}

type overviewHermes struct {
	Name            string `json:"name"`
	Type            string `json:"type"`
	IP              string `json:"ip"`
	PrometheusPort  int    `json:"prometheus_port,string"`
	RESTPort        int    `json:"rest_port,string"`
	DockerContainer string `json:"docker_container"`
}

// writeOverview writes generated/network/overview.json - the network layout the monitor, tx runner and verify read.
func (g *generator) writeOverview() error {
	nodes := func(s *side) []overviewNode {
		var out []overviewNode
		for _, n := range sortedByName(s.all) {
			out = append(out, overviewNode{Name: n.Name, Type: n.Type, IP: n.IP, P2PPort: n.P2PPort, RPCPort: n.RPCPort,
				RESTPort: n.RESTPort, GRPCPort: n.GRPCPort, DockerContainer: s.container(n)})
		}
		return out
	}
	und := g.cfg.Apps.Und
	out, err := json.MarshalIndent(struct {
		GenesisVersion       string         `json:"genesis_version"`
		UpgradeVersion       string         `json:"upgrade_version"`
		FundChainID          string         `json:"fund_chain_id"`
		GaiadChainID         string         `json:"gaiad_chain_id"`
		FundUpgradeHeight    int64          `json:"fund_upgrade_height,string"`
		FundUpgradePlan      string         `json:"fund_upgrade_plan"`
		WalletsDir           string         `json:"wallets_dir"`
		FundContainerPrefix  string         `json:"fund_container_prefix"`
		GaiadContainerPrefix string         `json:"gaiad_container_prefix"`
		IBCDenom             string         `json:"ibc_denom"`
		Hermes               overviewHermes `json:"hermes"`
		FundNodes            []overviewNode `json:"fund_nodes"`
		GaiadNodes           []overviewNode `json:"gaiad_nodes"`
	}{
		GenesisVersion: und.Genesis.Version, UpgradeVersion: und.Upgrade.Branch,
		FundChainID: g.fund.chainID, GaiadChainID: g.ibc.chainID,
		FundUpgradeHeight: und.Upgrade.UpgradeHeight, FundUpgradePlan: und.Upgrade.PlanName,
		WalletsDir:          filepath.Dir(g.p.WalletsUnd),
		FundContainerPrefix: g.fund.containerPrefix, GaiadContainerPrefix: g.ibc.containerPrefix,
		IBCDenom: ibcDenom(),
		Hermes: overviewHermes{Name: "hermes1", Type: "hermes", IP: g.hermesIP, PrometheusPort: hermesPrometheusPort,
			RESTPort: hermesRESTPort, DockerContainer: g.hermesContainer()},
		FundNodes:  nodes(g.fund),
		GaiadNodes: nodes(g.ibc),
	}, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(g.p.NetworkOverviewJSON, append(out, '\n'), 0o644)
}
