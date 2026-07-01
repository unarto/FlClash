export interface VpnStartResolutionInput {
  startErrorMessage: string;
  status: string;
}

export interface VpnStartResolution {
  started: boolean;
  errorMessage: string;
}

export function resolveVpnStartResult(
  input: VpnStartResolutionInput,
): VpnStartResolution {
  const status = input.status.trim();
  if (status === 'started') {
    return {
      started: true,
      errorMessage: '',
    };
  }

  if (status.startsWith('failed:')) {
    return {
      started: false,
      errorMessage: `vpn extension not ready: ${status}`,
    };
  }

  const startErrorMessage = input.startErrorMessage.trim();
  if (startErrorMessage.length > 0) {
    return {
      started: false,
      errorMessage: startErrorMessage,
    };
  }

  if (status.length > 0) {
    return {
      started: false,
      errorMessage: `vpn extension not ready: ${status}`,
    };
  }

  return {
    started: false,
    errorMessage: 'vpn extension not ready',
  };
}
