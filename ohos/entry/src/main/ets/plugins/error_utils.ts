export function stringifyError(error: unknown): string {
  if (typeof error === 'string') {
    return error;
  }

  try {
    const value = JSON.stringify(error);
    if (value && value !== 'undefined' && value !== '{}') {
      return value;
    }
  } catch (_) {}

  if (typeof error === 'object' && error !== null) {
    const message = (error as Record<string, unknown>).message;
    if (typeof message === 'string' && message.trim().length > 0) {
      return message;
    }
  }

  return `${error}`;
}
