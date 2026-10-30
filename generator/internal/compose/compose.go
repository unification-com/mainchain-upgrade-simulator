// Package compose writes docker-compose.yml.
package compose

import (
	"os"
	"strconv"

	"gopkg.in/yaml.v3"
)

type File struct {
	Services map[string]Service `yaml:"services"`
	Networks map[string]Network `yaml:"networks"`
}

type Service struct {
	Hostname      string                    `yaml:"hostname"`
	Build         Build                     `yaml:"build"`
	ContainerName string                    `yaml:"container_name"`
	Environment   map[string]Quoted         `yaml:"environment"`
	Command       []string                  `yaml:"command"`
	Networks      map[string]ServiceNetwork `yaml:"networks"`
	Volumes       []string                  `yaml:"volumes"`
	Ports         []Quoted                  `yaml:"ports"`
}

type Build struct {
	Context    string            `yaml:"context"`
	Dockerfile string            `yaml:"dockerfile"`
	Args       map[string]Quoted `yaml:"args"`
}

type ServiceNetwork struct {
	IPv4Address string `yaml:"ipv4_address"`
}

type Network struct {
	IPAM IPAM `yaml:"ipam"`
}

type IPAM struct {
	Driver string       `yaml:"driver"`
	Config []IPAMConfig `yaml:"config"`
}

type IPAMConfig struct {
	Subnet string `yaml:"subnet"`
}

// Quoted is always written double-quoted. A port mapping such as 26660:26660 is otherwise a plain scalar, which a
// YAML 1.1 parser reads as a base-60 number; values like "true" or "5s" stay strings whatever reads them.
type Quoted string

func (q Quoted) MarshalYAML() (any, error) {
	return &yaml.Node{Kind: yaml.ScalarNode, Style: yaml.DoubleQuotedStyle, Value: string(q)}, nil
}

// Port publishes a container port on the same host port.
func Port(p int) Quoted {
	return Quoted(strconv.Itoa(p) + ":" + strconv.Itoa(p))
}

// Write saves the file, services in name order.
func (f File) Write(path string) error {
	out, err := yaml.Marshal(f)
	if err != nil {
		return err
	}
	return os.WriteFile(path, out, 0o644)
}
