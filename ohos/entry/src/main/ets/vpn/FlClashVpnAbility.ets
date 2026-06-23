import VpnExtensionAbility from '@ohos.app.ability.VpnExtensionAbility';
import Want from '@ohos.app.ability.Want';
import { fileIo as fs } from '@kit.CoreFileKit';
import connection from '@ohos.net.connection';
import vpnExtension from '@ohos.net.vpnExtension';

interface NativeBridge {
  startTun(fd: number, stack: string, address: string, dns: string): boolean;
  stopTun(): boolean;
  lastError(): string;
}

const nativeBridge = loadNativeModule('libentry.so') as NativeBridge;

const IPV4_ADDRESS = '172.19.0.1';
const IPV4_PREFIX = 30;
const IPV6_ADDRESS = 'fdfe:dcba:9876::1';
const IPV6_PREFIX = 126;
const DNS4 = '172.19.0.2';
const DNS6 = 'fdfe:dcba:9876::2';
const IPV4_FAMILY = 1;
const IPV6_FAMILY = 2;
const BUNDLE_NAME = 'com.follow.clash';
const VPN_STATUS_FILE_NAME = 'flclash-vpn-status.txt';

function writeVpnStatus(filesDir: string, status: string): void {
  const path = `${filesDir}/${VPN_STATUS_FILE_NAME}`;
  const file = fs.openSync(
    path,
    fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC,
  );
  try {
    fs.writeSync(file.fd, status);
  } finally {
    fs.closeSync(file);
  }
}

function getStringParam(
  want: Want,
  key: string,
  fallback: string,
): string {
  const params = want.parameters as Record<string, Object> | undefined;
  const value = params?.[key];
  return typeof value === 'string' && value.length > 0 ? value : fallback;
}

function getBooleanParam(
  want: Want,
  key: string,
  fallback: boolean,
): boolean {
  const params = want.parameters as Record<string, Object> | undefined;
  const value = params?.[key];
  return typeof value === 'boolean' ? value : fallback;
}

export default class FlClashVpnAbility extends VpnExtensionAbility {
  private vpnConnection: vpnExtension.VpnConnection | null = null;

  async onCreate(want: Want): Promise<void> {
    this.vpnConnection = vpnExtension.createVpnConnection(this.context);
    writeVpnStatus(this.context.filesDir, 'starting');
    const stack = getStringParam(want, 'stack', 'mixed');
    const ipv6 = getBooleanParam(want, 'ipv6', false);
    const allowBypass = getBooleanParam(want, 'allowBypass', true);

    const addresses: Array<connection.LinkAddress> = [
      {
        address: { address: IPV4_ADDRESS, family: IPV4_FAMILY },
        prefixLength: IPV4_PREFIX,
      },
    ];
    if (ipv6) {
      addresses.push({
        address: { address: IPV6_ADDRESS, family: IPV6_FAMILY },
        prefixLength: IPV6_PREFIX,
      });
    }

    const routes: Array<connection.RouteInfo> = [
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

    const dnsAddresses = ipv6 ? [DNS4, DNS6] : [DNS4];

    try {
      const fd = await this.vpnConnection.create({
        addresses,
        routes,
        dnsAddresses,
        mtu: 9000,
        isIPv4Accepted: true,
        isIPv6Accepted: ipv6,
        isBlocking: false,
        blockedApplications: [BUNDLE_NAME],
      });
      try {
        await this.vpnConnection.protectProcessNet();
      } catch (error) {
        console.warn(
          `[FlClashVpnAbility] protectProcessNet failed: ${JSON.stringify(error)}`,
        );
      }
      const started = nativeBridge.startTun(
        fd,
        stack,
        IPV4_ADDRESS,
        dnsAddresses.join(','),
      );
      if (!started) {
        throw new Error(`startTun failed: ${nativeBridge.lastError()}`);
      }
      writeVpnStatus(this.context.filesDir, 'started');
      console.info(
        `[FlClashVpnAbility] started fd=${fd} stack=${stack} ipv6=${ipv6} allowBypass=${allowBypass}`,
      );
    } catch (error) {
      writeVpnStatus(
        this.context.filesDir,
        `failed:${JSON.stringify(error) ?? `${error}`}`,
      );
      console.error(
        `[FlClashVpnAbility] start failed: ${JSON.stringify(error)} lastError=${nativeBridge.lastError()}`,
      );
      try {
        await this.vpnConnection?.destroy();
      } catch (_) {}
      this.vpnConnection = null;
      throw new Error(`${error}`);
    }
  }

  async onDestroy(): Promise<void> {
    writeVpnStatus(this.context.filesDir, 'stopped');
    try {
      nativeBridge.stopTun();
    } catch (error) {
      console.error(
        `[FlClashVpnAbility] stopTun failed: ${JSON.stringify(error)} lastError=${nativeBridge.lastError()}`,
      );
    }
    try {
      await this.vpnConnection?.destroy();
    } catch (error) {
      console.error(
        `[FlClashVpnAbility] destroy failed: ${JSON.stringify(error)}`,
      );
    }
    this.vpnConnection = null;
  }
}
