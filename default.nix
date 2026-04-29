{ lib, config, ... }:
let
  reservedSubnets = [
    "0.0.0.0/8"
    "10.0.0.0/8"
    "100.64.0.0/10"
    "127.0.0.0/8"
    "169.254.0.0/16"
    "172.16.0.0/12"
    "192.0.0.0/24"
    "192.0.2.0/24"
    "192.88.99.0/24"
    "192.168.0.0/16"
    "198.18.0.0/15"
    "198.51.100.0/24"
    "203.0.113.0/24"
    "224.0.0.0/4"
    "240.0.0.0/4"
  ];

  buildSet = type: flags: name: elements: ''
    set ${name} {
      type ${type}
      ${if flags != null then "flags ${flags}" else ""}

      ${
        lib.optionalString (elements != [ ])

        "elements = { ${lib.concatStringsSep "," elements} }"
      }
    }
  '';
  buildSubnetsSet = buildSet "ipv4_addr" "interval";

in {

  options = {

    networking.tor = {

      VirtualAddrNetworkIPv4 = lib.mkOption {
        type = lib.types.str;
        default = "10.64.0.0/10";
        description = "The virtual address space used by Tor";
      };

      natPrio = lib.mkOption {
        type = lib.types.int;
        default = -100;
        description = "nftables NAT handling priority";
      };

      filterPrio = lib.mkOption {
        type = lib.types.int;
        default = 0;
        description = "nftables filter handling priority";
      };

      client = {
        enable = lib.mkEnableOption
          "Route all traffic of the current machine through Tor. Does not act as a router for other machines";

        clearnet-proxy = {
          enable = lib.mkEnableOption
            "Whether to enable a squid instance that can perform requests without being routed through Tor.";

          port = lib.mkOption {
            type = lib.types.int;
            default = 3128;
            example = 8080;
            description = "Port used for the squid proxy";
          };

        };

        allowedDestinations = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [ "104.16.0.0/13" ];
          description =
            "Allowed destination addresses that will not be routed through Tor";
        };

        allowedInterfaces = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "List of allowed interfaces";
          example = [ "wg0" ];
        };

        allowedFwMarks = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "List of allowed fwMarks";
          example = [ "0x100" ];
        };

      };

      router = {
        enable = lib.mkEnableOption
          "Route all received traffic through Tor. Does not act as a router for the current machine";

        allowedDestinations = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [ "104.16.0.0/13" ];
          description =
            "Allowed destination addresses that will not be routed through Tor";
        };
      };

    };
  };

  config = {

    services.tor = lib.mkIf (config.networking.tor.client.enable
      || config.networking.tor.router.enable) {
        enable = true;

        client = {
          enable = true;
          transparentProxy.enable = true;
          dns.enable = true;
        };

        settings = {

          DNSPort = lib.mkIf config.networking.tor.router.enable [{
            addr = "0.0.0.0";
            port = 9053;
          }];

          # without mkForce it sets to 127.0.0.1 and later it cannot bind
          TransPort = lib.mkIf config.networking.tor.router.enable
            (lib.mkForce [{
              addr = "0.0.0.0";
              port = 9040;
            }]);

          VirtualAddrNetworkIPv4 = config.networking.tor.VirtualAddrNetworkIPv4;
        };

      };

    networking.firewall.allowedTCPPorts =
      lib.mkIf config.networking.tor.router.enable [ 9040 ];

    networking.firewall.allowedUDPPorts =
      lib.mkIf config.networking.tor.router.enable [ 9053 ];

    services.squid = lib.mkIf config.networking.tor.client.enable {
      enable = config.networking.tor.client.clearnet-proxy.enable;
      proxyAddress = "127.0.0.1";
      proxyPort = config.networking.tor.client.clearnet-proxy.port;
      extraConfig = ''
        shutdown_lifetime 0 seconds;

      '';
    };

    systemd.services.squid.after =
      lib.mkIf config.networking.tor.client.enable [ "network-online.target" ];

    systemd.services.squid.wants =
      lib.mkIf config.networking.tor.client.enable [ "network-online.target" ];

    networking.nftables.enable = lib.mkIf (config.networking.tor.client.enable
      || config.networking.tor.router.enable) true;

    networking.nftables.preCheckRuleset = ''
      sed -i 's/skuid tor/skuid 1/' ruleset.conf
      sed -i 's/skuid squid/skuid 2/' ruleset.conf
    '';

    # networking.nftables.checkRuleset = false;

    networking.nftables.tables = {
      tor = {
        enable = config.networking.tor.client.enable;
        family = "inet";
        content = ''

          ${buildSubnetsSet "reserved_subnets" reservedSubnets}

          ${buildSubnetsSet "allowed_destinations"
          config.networking.tor.client.allowedDestinations}

          ${buildSet "ifname" null "allowed_ifs"
          config.networking.tor.client.allowedInterfaces}

          ${buildSet "mark" null "allowed_marks"
          config.networking.tor.client.allowedFwMarks}

          chain tor_nat_output {
            type nat hook output priority ${
              toString config.networking.tor.natPrio
            }

            oifname lo return # Do not modify any packet to lo
            ip daddr 127.0.0.0/8 return # Do not modify any packet to 127...

            oifname @allowed_ifs return
            meta mark @allowed_marks return

            skuid tor return # Do not modify any tor packets

            ${
              lib.optionalString
              (config.networking.tor.client.clearnet-proxy.enable)

              "skuid squid return"
            }

            ip daddr @allowed_destinations return
            # here do we wanna prioritize DNS or allowed_destinations?
            ip protocol udp udp dport 53 dnat to 127.0.0.1:9053 # route dns before allowing local addresses

            ip daddr @reserved_subnets ip daddr != ${config.networking.tor.VirtualAddrNetworkIPv4} return

            ip protocol tcp dnat to 127.0.0.1:9040 # this rewrites the dest addr but not the interface!
          }

          chain tor_filter_output {
            type filter hook output priority ${
              toString config.networking.tor.filterPrio
            }; policy drop;

            ct state established,related accept

            oifname lo accept # for processes that connect to interface IPs, like 192.186.1.150 and are routed through lo
            ip daddr 127.0.0.0/8 accept # DNATed packets have ethernet intf but local addresses

            oifname @allowed_ifs accept
            meta mark @allowed_marks accept

            skuid tor accept

            ${
              lib.optionalString
              (config.networking.tor.client.clearnet-proxy.enable)

              "skuid squid accept"
            }

            ip daddr @reserved_subnets accept
            ip daddr @allowed_destinations accept

            ip protocol udp udp dport 123 drop # drop NTP pkts without logging
            ip protocol udp udp dport 443 drop # drop DTLS pkts without logging

            log prefix "tor-drop: " drop
          }

        '';

      };

      tor-router = {
        enable = config.networking.tor.router.enable;
        family = "inet";
        content = ''

          ${buildSubnetsSet "reserved_subnets" reservedSubnets}
          ${buildSubnetsSet "allowed_destinations"
          config.networking.tor.router.allowedDestinations}

          chain tor_nat_prerouting {
            type nat hook prerouting priority ${
              toString config.networking.tor.natPrio
            }

            ip daddr @reserved_subnets ip daddr != ${config.networking.tor.VirtualAddrNetworkIPv4} return
            ip daddr @allowed_destinations return

            ip protocol udp udp dport 53 redirect to :9053
            ip protocol tcp tcp flags syn redirect to :9040
          }

          chain tor_filter_forward {
            type filter hook forward priority ${
              toString config.networking.tor.filterPrio
            }; policy drop
            
            ct state established,related accept

            ip daddr @reserved_subnets accept
            ip daddr @allowed_destinations accept

            # log
          }
        '';

      };

    };

    boot.kernel.sysctl."net.ipv4.ip_forward" =
      lib.mkIf config.networking.tor.router.enable 1;

  };

}
