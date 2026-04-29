# networking-tor

A NixOS module that enables the `networking.tor` option to transparently route
traffic through [Tor](https://www.torproject.org/) using nftables.

## Import

### Flake

```nix
inputs = {
  networking-tor = {
    url = "github:deade1e/networking-tor";
    flake = false;
  };
};
```

### Classic

```nix
imports = [
  (builtins.fetchTarball {
    url = "https://github.com/deade1e/networking-tor/archive/main.tar.gz";
    sha256 = lib.fakeHash; # Replace with the actual hash
  })
];
```

## Quick start

```nix
{
  networking.tor = {
    client = {
      enable = true; # Route all traffic generated on this machine through Tor
      allowedDestinations = [
        "104.16.0.0/13" # Bypass Tor for this destination
      ];
      allowedInterfaces = [
        "wg0" # Bypass Tor for packets going out this interface
      ];
      allowedFwMarks = [
        "0x100" # Bypass Tor for packets with this fwmark
      ];
    };
    router = {
      enable = true; # Route traffic forwarded by other hosts through Tor
      allowedDestinations = [
        "104.16.0.0/13" # Bypass Tor for this destination
      ];
    };
  };
}
```

## Modes

**Client mode** (`networking.tor.client.enable`) routes all outbound traffic of
the local machine through Tor.

**Router mode** (`networking.tor.router.enable`) routes forwarded traffic
through Tor, turning the machine into a Tor gateway for other devices. Also
accepts `allowedSources` to exempt specific source subnets.

Both modes can be enabled simultaneously.

## Options

### `networking.tor.client`

| Option | Type | Default | Description |
|--------|------|---------|--------------|
| `enable` | bool | `false` | Enable client mode |
| `clearnet-proxy.enable` | bool | `false` | Enable a Squid proxy for traffic that bypasses Tor |
| `clearnet-proxy.port` | int | `3128` | Squid proxy port |
| `allowedDestinations` | list of str | `[]` | Destination subnets that bypass Tor |
| `allowedInterfaces` | list of str | `[]` | Outbound interfaces that bypass Tor |
| `allowedFwMarks` | list of str | `[]` | Packet marks that bypass Tor |

### `networking.tor.router`

| Option | Type | Default | Description |
|---|---|---|---|
| `enable` | bool | `false` | Enable router mode |
| `allowedDestinations` | list of str | `[]` | Destination subnets that bypass Tor |
| `allowedSources` | list of str | `[]` | Source subnets that bypass Tor |

### Global

| Option | Type | Default | Description |
|---|---|---|---|
| `VirtualAddrNetworkIPv4` | str | `10.64.0.0/10` | Virtual address space for `.onion` resolution |
| `nat-priority` | int | `-100` | nftables NAT chain priority |
| `filter-priority` | int | `0` | nftables filter chain priority |

## Notes

- `networking.nftables.enable` is set automatically
- Router mode enables `net.ipv4.ip_forward` automatically
- Router mode opens TCP port `9040` and UDP port `9053` in the firewall
- DNS is redirected through Tor to prevent leaks
- Traffic from the `tor` and `squid` system users is always exempted to prevent routing loops
