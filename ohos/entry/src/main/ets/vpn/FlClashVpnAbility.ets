import VpnExtensionAbility from '@ohos.app.ability.VpnExtensionAbility';
import Want from '@ohos.app.ability.Want';
import { fileIo as fs } from '@kit.CoreFileKit';
import connection from '@ohos.net.connection';
import vpnExtension from '@ohos.net.vpnExtension';
import {
  buildOhosVpnRoutes,
  resolveOhosVpnApplicationLists,
} from './vpn_config';

interface NativeBridge {
  quickSetup(initParamsJson: string, setupParamsJson: string): string;
  consumeCoreEvents(): string;
  consumeProtectRequests(): string;
  completeProtectRequest(requestId: number, result: number): boolean;
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
const PROTECT_POLL_INTERVAL_MS = 10;

interface ProtectRequest {
  id: number;
  fd: number;
}

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
  private protectLoopToken = 0;

  private async pumpProtectRequests(loopToken: number): Promise<void> {
    while (this.vpnConnection !== null && this.protectLoopToken === loopToken) {
      // The VPN extension hosts its own bridge instance, so unsolicited core
      // events would otherwise accumulate in this process without a consumer.
      nativeBridge.consumeCoreEvents();
      const payload = nativeBridge.consumeProtectRequests();
      const requests = JSON.parse(payload) as Array<ProtectRequest>;
      for (const request of requests) {
        try {
          await this.vpnConnection.protect(request.fd);
          nativeBridge.completeProtectRequest(request.id, 0);
        } catch (error) {
          console.warn(
            `[FlClashVpnAbility] protect fd=${request.fd} failed: ${JSON.stringify(error)}`,
          );
          nativeBridge.completeProtectRequest(request.id, -1);
        }
      }
      await new Promise<void>((resolve) => setTimeout(resolve, PROTECT_POLL_INTERVAL_MS));
    }
  }

  async onCreate(want: Want): Promise<void> {
    this.vpnConnection = vpnExtension.createVpnConnection(this.context);
    const protectLoopToken = ++this.protectLoopToken;
    writeVpnStatus(this.context.filesDir, 'starting');
    const stack = getStringParam(want, 'stack', 'mixed');
    const ipv6 = getBooleanParam(want, 'ipv6', false);
    const allowBypass = getBooleanParam(want, 'allowBypass', true);
    const initParamsJson = getStringParam(want, 'initParamsJson', '');
    const setupParamsJson = getStringParam(want, 'setupParamsJson', '');

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

    const routes: Array<connection.RouteInfo> = buildOhosVpnRoutes(ipv6);

    const dnsAddresses = ipv6 ? [DNS4, DNS6] : [DNS4];
    const tunAddresses = ipv6
      ? `${IPV4_ADDRESS},${IPV6_ADDRESS}`
      : IPV4_ADDRESS;
    const vpnApplicationLists = resolveOhosVpnApplicationLists(BUNDLE_NAME);

    try {
      if (initParamsJson.length === 0 || setupParamsJson.length === 0) {
        throw new Error('missing init/setup params for quickSetup');
      }
      const setupResult = nativeBridge.quickSetup(
        initParamsJson,
        setupParamsJson,
      );
      if (setupResult.length > 0) {
        throw new Error(`quickSetup failed: ${setupResult}`);
      }
      const fd = await this.vpnConnection.create({
        addresses,
        routes,
        dnsAddresses,
        mtu: 9000,
        isIPv4Accepted: true,
        isIPv6Accepted: ipv6,
        isInternal: false,
        isBlocking: false,
        trustedApplications: vpnApplicationLists.trustedApplications,
        blockedApplications: vpnApplicationLists.blockedApplications,
      });
      try {
        await this.vpnConnection.protectProcessNet();
      } catch (error) {
        console.warn(
          `[FlClashVpnAbility] protectProcessNet failed: ${JSON.stringify(error)}`,
        );
      }
      void this.pumpProtectRequests(protectLoopToken);
      const started = nativeBridge.startTun(
        fd,
        stack,
        tunAddresses,
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
    this.protectLoopToken += 1;
  }
}
