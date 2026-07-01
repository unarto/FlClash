import VpnExtensionAbility from '@ohos.app.ability.VpnExtensionAbility';
import Want from '@ohos.app.ability.Want';
import { fileIo as fs } from '@kit.CoreFileKit';
import connection from '@ohos.net.connection';
import vpnExtension from '@ohos.net.vpnExtension';
import {
  buildOhosVpnRoutes,
  resolveOhosVpnApplicationLists,
} from './vpn_config';
import { stringifyError } from '../plugins/error_utils';

interface NativeBridge {
  quickSetup(initParamsJson: string, setupParamsJson: string): string;
  consumeCoreEvents(): string;
  consumeProtectRequests(): string;
  completeProtectRequest(requestId: number, result: number): boolean;
  startTun(fd: number, stack: string, address: string, dns: string): boolean;
  stopTun(): boolean;
  lastError(): string;
  startEmbeddedCore(socketPath: string, logDirPath: string): number;
  stopTrackedCore(): boolean;
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
            `[FlClashVpnAbility] protect fd=${request.fd} failed: ${stringifyError(error)}`,
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
    const initParamsJson = getStringParam(want, 'initParamsJson', '');
    const setupParamsJson = getStringParam(want, 'setupParamsJson', '');
    const coreSocketPath = getStringParam(want, 'coreSocketPath', '');

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
    let tunStarted = false;

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
        blockedApplications: vpnApplicationLists.blockedApplications,
      });
      try {
        await this.vpnConnection.protectProcessNet();
      } catch (error) {
        console.warn(
          `[FlClashVpnAbility] protectProcessNet failed: ${stringifyError(error)}`,
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
      tunStarted = true;
      // Link the main app UI to THIS (traffic-serving) core: the embedded core
      // dials the main app's CoreService socket in-process, so the same core
      // that runs the tun also answers UI queries and pushes live events.
      // This link is part of a successful OHOS VPN start: without it the UI
      // cannot observe the traffic-serving core (status/stats/connections).
      if (coreSocketPath.length > 0) {
        try {
          const linked = nativeBridge.startEmbeddedCore(
            coreSocketPath,
            this.context.filesDir,
          );
          if (linked <= 0) {
            throw new Error(
              `startEmbeddedCore failed: ${nativeBridge.lastError()}`,
            );
          }
          console.info(
            `[FlClashVpnAbility] core UI link socket=${coreSocketPath} result=${linked}`,
          );
        } catch (error) {
          throw new Error(
            `core UI link failed: ${stringifyError(error)}`,
          );
        }
      }
      writeVpnStatus(this.context.filesDir, 'started');
      console.info(
        `[FlClashVpnAbility] started fd=${fd} stack=${stack} ipv6=${ipv6}`,
      );
    } catch (error) {
      const errorMessage = stringifyError(error);
      const cleanupErrors: string[] = [];
      if (tunStarted) {
        try {
          const stopped = nativeBridge.stopTun();
          if (!stopped) {
            cleanupErrors.push(`stopTun failed: ${nativeBridge.lastError()}`);
          }
        } catch (cleanupError) {
          cleanupErrors.push(`stopTun failed: ${stringifyError(cleanupError)}`);
        }
        try {
          const stopped = nativeBridge.stopTrackedCore();
          if (!stopped) {
            cleanupErrors.push(
              `stopTrackedCore failed: ${nativeBridge.lastError()}`,
            );
          }
        } catch (cleanupError) {
          cleanupErrors.push(
            `stopTrackedCore failed: ${stringifyError(cleanupError)}`,
          );
        }
      }
      try {
        await this.vpnConnection?.destroy();
      } catch (cleanupError) {
        cleanupErrors.push(`destroy failed: ${stringifyError(cleanupError)}`);
      }
      writeVpnStatus(
        this.context.filesDir,
        `failed:${errorMessage}${cleanupErrors.length > 0 ? ` | ${cleanupErrors.join(' | ')}` : ''}`,
      );
      console.error(
        `[FlClashVpnAbility] start failed: ${errorMessage} lastError=${nativeBridge.lastError()}`,
      );
      this.vpnConnection = null;
      throw new Error(errorMessage);
    }
  }

  async onDestroy(): Promise<void> {
    const teardownErrors: string[] = [];
    try {
      const stopped = nativeBridge.stopTun();
      if (!stopped) {
        const errorMessage = nativeBridge.lastError();
        teardownErrors.push(`stopTun failed: ${errorMessage}`);
        console.error(
          `[FlClashVpnAbility] stopTun failed: ${errorMessage} lastError=${errorMessage}`,
        );
      }
    } catch (error) {
      teardownErrors.push(`stopTun failed: ${stringifyError(error)}`);
      console.error(
        `[FlClashVpnAbility] stopTun failed: ${stringifyError(error)} lastError=${nativeBridge.lastError()}`,
      );
    }
    try {
      const stopped = nativeBridge.stopTrackedCore();
      if (!stopped) {
        const errorMessage = nativeBridge.lastError();
        teardownErrors.push(`stopTrackedCore failed: ${errorMessage}`);
        console.error(
          `[FlClashVpnAbility] stopTrackedCore failed: ${errorMessage} lastError=${errorMessage}`,
        );
      }
    } catch (error) {
      teardownErrors.push(`stopTrackedCore failed: ${stringifyError(error)}`);
      console.error(
        `[FlClashVpnAbility] stopTrackedCore failed: ${stringifyError(error)} lastError=${nativeBridge.lastError()}`,
      );
    }
    try {
      await this.vpnConnection?.destroy();
    } catch (error) {
      teardownErrors.push(`destroy failed: ${stringifyError(error)}`);
      console.error(
        `[FlClashVpnAbility] destroy failed: ${stringifyError(error)}`,
      );
    }
    this.vpnConnection = null;
    this.protectLoopToken += 1;
    if (teardownErrors.length > 0) {
      writeVpnStatus(
        this.context.filesDir,
        `failed:${teardownErrors.join(' | ')}`,
      );
      return;
    }
    writeVpnStatus(this.context.filesDir, 'stopped');
  }
}
