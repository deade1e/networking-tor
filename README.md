# Networking-Tor

Enable `networking.tor` option in NixOS. This option enables routing all of the traffic through Tor.

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
  (builtins.fetchTarball "https://github.com/deade1e/networking-tor/archive/main.tar.gz")
];
```

## Quick start

```nix
{
  networking.tor = {
    client = {
      enable = true; # Enable routing of all traffic generated on the current machine through Tor.
      allowedDestinations = [
        "104.16.0.0/13" # Don't route packets with this destination
      ];
      allowedInterfaces = [
        "wg0" # Don't route packets that would've gone on this interface
      ];
      allowedFwMarks = [
        "0x100" # Don't route packets marked with this fwMark
      ];
    };
    router = {
      enable = true; # Route traffic forwarded to you by other hosts
      allowedDestinations = [
        "104.16.0.0/13" # Don't route packets with this destination
      ];
    };
  };
}

```
