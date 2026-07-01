import util from '@ohos.util';

export interface FilePickerResultMap {
  path: string;
  name: string;
  size: number;
  bytes: Uint8Array;
  identifier: string;
}

export interface FilePickerUriMap {
  name: string;
  identifier: string;
}

export class FilePickerInfo {
  path: string;
  name: string;
  size: number;
  bytes: Uint8Array;
  uri: string;

  constructor(path: string, name: string, size: number, bytes: Uint8Array, uri: string) {
    this.path = path;
    this.name = name;
    this.size = size;
    this.bytes = bytes;
    this.uri = uri;
  }

  toMap(): FilePickerResultMap {
    const data: FilePickerResultMap = {
      path: this.path,
      name: this.name,
      size: this.size,
      bytes: this.bytes,
      identifier: this.uri,
    };
    return data;
  }

  toUriMap(): FilePickerUriMap {
    const data: FilePickerUriMap = {
      name: this.name,
      identifier: this.uri,
    };
    return data;
  }
}

export class FilePickerInfoBuilder {
  path: string = '';
  name: string = '';
  size: number = 0;
  bytes: Uint8Array = new Uint8Array();
  uri: string = '';

  withPath(path: string): FilePickerInfoBuilder {
    this.path = path;
    return this;
  }

  withName(name: string): FilePickerInfoBuilder {
    this.name = name;
    return this;
  }

  withSize(size: number): FilePickerInfoBuilder {
    this.size = size;
    return this;
  }

  withData(bytes: Uint8Array): FilePickerInfoBuilder {
    this.bytes = bytes;
    return this;
  }

  withUri(uri: string): FilePickerInfoBuilder {
    this.uri = uri;
    return this;
  }

  build(): FilePickerInfo {
    return new FilePickerInfo(this.path, this.name, this.size, this.bytes, this.uri);
  }
}

export function decodePickedFileName(encodedString: string): string {
  let result = '';
  let index = 0;
  while (index < encodedString.length) {
    const char = encodedString[index];
    if (char === '%') {
      const hexCode = encodedString.substring(index + 1, index + 3);
      result += String.fromCharCode(parseInt(hexCode, 16));
      index += 3;
      continue;
    }
    result += char;
    index++;
  }
  const utf8Bytes = new Uint8Array(result.length);
  for (let i = 0; i < result.length; i++) {
    utf8Bytes[i] = result.charCodeAt(i);
  }
  return new util.TextDecoder().decodeToString(utf8Bytes);
}
