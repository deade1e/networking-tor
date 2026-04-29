# Networking-Tor

Enable `networking.tor` option in NixOS.

## Flake
```nix
inputs = {
  networking-tor = {
    url = "github:deade1e/networking-tor";
    flake = false;
  };
};
```

## Classic
```nix
imports = [
  (builtins.fetchTarball "https://github.com/deade1e/networking-tor/archive/main.tar.gz")
];
```
