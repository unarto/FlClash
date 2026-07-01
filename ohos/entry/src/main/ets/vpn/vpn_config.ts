export interface OhosVpnApplicationLists {
  blockedApplications: Array<string>;
}

interface OhosVpnAddress {
  address: string;
  family: number;
}

interface OhosVpnIpPrefix {
  address: OhosVpnAddress;
  prefixLength: number;
}

export interface OhosVpnRouteInfo {
  interface: string;
  destination: OhosVpnIpPrefix;
  gateway: OhosVpnAddress;
  hasGateway: boolean;
  isDefaultRoute: boolean;
  isExcludedRoute?: boolean;
}

const IPV4_FAMILY = 1;
const IPV6_FAMILY = 2;

const HUAWEI_BOOTSTRAP_EXCLUDED_ROUTES = [
  '139.9.98.98',
  '139.9.99.99',
];

// Huawei Browser resolves hosts through its own HTTPDNS service rather than the
// system resolver. The bootstrap servers above hand back a rotating pool of
// HTTPDNS edge servers (China Telecom / Huawei Cloud ranges). When those edge
// servers are routed into the tunnel they are reached via the foreign proxy
// node and never answer, so the browser stalls for ~10s per lookup and the page
// fails before any content connection is attempted. Excluding the HTTPDNS edge
// ranges keeps resolution on the local carrier network; the resulting content
// connections still traverse the tunnel and are corrected by the core sniffer.
const HUAWEI_HTTPDNS_EXCLUDED_CIDRS: Array<OhosVpnIpPrefix> = [
  // Huawei Cloud ranges (HTTPDNS bootstrap + edge).
  { address: { address: '139.9.0.0', family: IPV4_FAMILY }, prefixLength: 16 },
  { address: { address: '49.4.0.0', family: IPV4_FAMILY }, prefixLength: 16 },
  { address: { address: '121.36.0.0', family: IPV4_FAMILY }, prefixLength: 16 },
  // China Telecom Guangdong ranges that host the rotating HTTPDNS edge servers
  // (observed: 125.88.252.x, 119.147.50.x, 183.61.178.x).
  { address: { address: '125.88.0.0', family: IPV4_FAMILY }, prefixLength: 16 },
  { address: { address: '119.147.0.0', family: IPV4_FAMILY }, prefixLength: 16 },
  { address: { address: '183.61.0.0', family: IPV4_FAMILY }, prefixLength: 16 },
];

export function resolveOhosVpnApplicationLists(
  bundleName: string,
): OhosVpnApplicationLists {
  // Full-system VPN (no trustedApplications allowlist) mirrors the Android
  // VpnService model: all apps except FlClash itself route through the tunnel.
  // The split-tunnel allowlist kept the VPN from being assigned as the apps'
  // resolving network, so the advertised DNS (172.19.0.2) never propagated and
  // browser DNS lookups bypassed the core. Routing everything restores the
  // Android-equivalent DNS propagation path.
  return {
    blockedApplications: [bundleName],
  };
}

export function buildOhosVpnRoutes(ipv6: boolean): Array<OhosVpnRouteInfo> {
  const routes: Array<OhosVpnRouteInfo> = [
    {
      interface: '',
      destination: {
        address: { address: '0.0.0.0', family: IPV4_FAMILY },
        prefixLength: 0,
      },
      gateway: { address: '', family: IPV4_FAMILY },
      hasGateway: false,
      isDefaultRoute: true,
    },
    ...HUAWEI_BOOTSTRAP_EXCLUDED_ROUTES.map((address) => ({
      interface: '',
      destination: {
        address: { address, family: IPV4_FAMILY },
        prefixLength: 32,
      },
      gateway: { address: '', family: IPV4_FAMILY },
      hasGateway: false,
      isDefaultRoute: false,
      isExcludedRoute: true,
    })),
    ...HUAWEI_HTTPDNS_EXCLUDED_CIDRS.map((destination) => ({
      interface: '',
      destination,
      gateway: { address: '', family: IPV4_FAMILY },
      hasGateway: false,
      isDefaultRoute: false,
      isExcludedRoute: true,
    })),
  ];

  if (ipv6) {
    routes.push({
      interface: '',
      destination: {
        address: { address: '::', family: IPV6_FAMILY },
        prefixLength: 0,
      },
      gateway: { address: '', family: IPV6_FAMILY },
      hasGateway: false,
      isDefaultRoute: true,
    });
  }

  return routes;
}
