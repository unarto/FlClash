export const invokeCore: (action: string) => string;
export const invokeCoreAsync: (action: string) => Promise<string>;
export const chmodPath: (path: string) => boolean;
export const lastError: () => string;
