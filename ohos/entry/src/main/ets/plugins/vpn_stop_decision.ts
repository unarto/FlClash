export interface VpnStopResolutionInput {
  stopErrorMessage: string;
  status: string;
}

export interface VpnStopResolution {
  stopped: boolean;
  errorMessage: string;
}

export function resolveVpnStopResult(
  input: VpnStopResolutionInput,
): VpnStopResolution {
  const status = input.status.trim();
  if (status === 'stopped') {
    return {
      stopped: true,
      errorMessage: '',
    };
  }

  if (status.startsWith('failed:')) {
    return {
      stopped: false,
      errorMessage: `vpn extension did not stop: ${status}`,
    };
  }

  const stopErrorMessage = input.stopErrorMessage.trim();
  if (stopErrorMessage.length > 0) {
    return {
      stopped: false,
      errorMessage: stopErrorMessage,
    };
  }

  if (status.length > 0) {
    return {
      stopped: false,
      errorMessage: `vpn extension did not stop: ${status}`,
    };
  }

  return {
    stopped: false,
    errorMessage: 'vpn extension did not stop',
  };
}
