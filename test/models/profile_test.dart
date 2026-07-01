import 'dart:convert';
import 'dart:typed_data';

import 'package:fl_clash/models/profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  group('Profile.normalizeImportedConfigBytes', () {
    test('clears placeholder external-ui path from imported yaml', () {
      const raw = '''
mixed-port: 7890
external-ui: /path/to/ui/folder/
proxies:
  - name: direct
    type: direct
''';

      final bytes = Uint8List.fromList(utf8.encode(raw));
      final normalized = ProfileExtension.normalizeImportedConfigBytes(bytes);
      final text = utf8.decode(normalized);

      expect(text, contains('external-ui: ""'));
      expect(text, isNot(contains('/path/to/ui/folder/')));
      expect(text, contains('mixed-port: 7890'));
    });

    test('clears absolute external-ui path from imported yaml', () {
      const raw = '''
mixed-port: 7890
external-ui: /etc/clash/ui
proxies:
  - name: direct
    type: direct
''';

      final bytes = Uint8List.fromList(utf8.encode(raw));
      final normalized = ProfileExtension.normalizeImportedConfigBytes(bytes);
      final text = utf8.decode(normalized);

      expect(text, contains('external-ui: ""'));
      expect(text, isNot(contains('/etc/clash/ui')));
      expect(() => loadYaml(text), returnsNormally);
    });

    test('keeps non-yaml subscription payload unchanged', () {
      const raw = 'vmess://example';
      final bytes = Uint8List.fromList(utf8.encode(raw));

      final normalized = ProfileExtension.normalizeImportedConfigBytes(bytes);

      expect(utf8.decode(normalized), raw);
    });

    test(
      'normalizes CRLF yaml while preserving proxy section parsing shape',
      () {
        const raw =
            'proxies:\r\n'
            '  - name: a\r\n'
            '    type: ss\r\n'
            '    server: a.example.com\r\n'
            '    port: 443\r\n'
            '    cipher: aes-128-gcm\r\n'
            '    password: secret\r\n'
            '  - name: b\r\n'
            '    type: ss\r\n'
            '    server: b.example.com\r\n'
            '    port: 443\r\n'
            '    cipher: aes-128-gcm\r\n'
            '    password: secret\r\n'
            'proxy-groups:\r\n'
            '  - name: auto\r\n'
            '    type: select\r\n'
            '    proxies:\r\n'
            '      - a\r\n'
            '      - b\r\n';

        final bytes = Uint8List.fromList(utf8.encode(raw));
        final normalized = ProfileExtension.normalizeImportedConfigBytes(bytes);
        final text = utf8.decode(normalized);

        expect(text, contains('proxies:'));
        expect(text, contains('  - name: a'));
        expect(text, contains('  - name: b'));
        expect(text, contains('proxy-groups:'));
        expect(() => loadYaml(text), returnsNormally);
      },
    );

    test('collapses singleton server and password lists to scalars', () {
      const raw = '''
proxies:
  - name: test
    type: shadowsocks
    server: [example.com]
    port: 443
    password: [secret]
''';

      final bytes = Uint8List.fromList(utf8.encode(raw));
      final normalized = ProfileExtension.normalizeImportedConfigBytes(bytes);
      final text = utf8.decode(normalized);

      expect(text, contains('server: example.com'));
      expect(text, contains('password: secret'));
      expect(text, isNot(contains('server: [example.com]')));
      expect(text, isNot(contains('password: [secret]')));
    });

    test('rewrites unsafe example provider paths to relative paths', () {
      const raw = '''
proxy-providers:
  test:
    type: file
    path: /test.yaml
rule-providers:
  rule1:
    type: http
    behavior: classical
    path: /path/to/save/file.yaml
    url: "https://example.com/rules.yaml"
''';

      final bytes = Uint8List.fromList(utf8.encode(raw));
      final normalized = ProfileExtension.normalizeImportedConfigBytes(bytes);
      final text = utf8.decode(normalized);

      expect(text, contains('path: ./test.yaml'));
      expect(text, contains('path: ./path/to/save/file.yaml'));
      expect(text, isNot(contains('path: /test.yaml')));
      expect(text, isNot(contains('path: /path/to/save/file.yaml')));
      expect(() => loadYaml(text), returnsNormally);
    });

    test('rewrites unsafe example mrs provider path to a relative path', () {
      const raw = '''
rule-providers:
  rule-set:
    type: http
    behavior: domain
    path: /path/to/save/file.mrs
    url: "https://example.com/rules.mrs"
''';

      final bytes = Uint8List.fromList(utf8.encode(raw));
      final normalized = ProfileExtension.normalizeImportedConfigBytes(bytes);
      final text = utf8.decode(normalized);

      expect(text, contains('path: ./path/to/save/file.mrs'));
      expect(text, isNot(contains('path: /path/to/save/file.mrs')));
      expect(() => loadYaml(text), returnsNormally);
    });

    test('rewrites invalid example IP-ASN rule target PROXY to DIRECT', () {
      const raw = '''
rules:
  - IP-ASN,1,PROXY
''';

      final bytes = Uint8List.fromList(utf8.encode(raw));
      final normalized = ProfileExtension.normalizeImportedConfigBytes(bytes);
      final text = utf8.decode(normalized);

      expect(text, contains('IP-ASN,1,DIRECT'));
      expect(text, isNot(contains('IP-ASN,1,PROXY')));
      expect(() => loadYaml(text), returnsNormally);
    });

    test('removes unresolved fake-ip-filter sample dependencies', () {
      const raw = '''
dns:
  fake-ip-filter:
    - '*.lan'
    - rule-set:fakeip-filter
    - geosite:fakeip-filter
''';

      final bytes = Uint8List.fromList(utf8.encode(raw));
      final normalized = ProfileExtension.normalizeImportedConfigBytes(bytes);
      final text = utf8.decode(normalized);

      expect(text, contains("- '*.lan'"));
      expect(text, isNot(contains('rule-set:fakeip-filter')));
      expect(text, isNot(contains('geosite:fakeip-filter')));
      expect(() => loadYaml(text), returnsNormally);
    });

    test('removes sample tunnels block with placeholder proxies', () {
      const raw = '''
tunnels: # one line config
  - tcp/udp,127.0.0.1:6553,114.114.114.114:53,proxy
  - tcp,127.0.0.1:6666,rds.mysql.com:3306,vpn
  # full yaml config
  - network: [tcp, udp]
    address: 127.0.0.1:7777
    target: target.com
    proxy: proxy

dns:
  enable: true
''';

      final bytes = Uint8List.fromList(utf8.encode(raw));
      final normalized = ProfileExtension.normalizeImportedConfigBytes(bytes);
      final text = utf8.decode(normalized);

      expect(text, isNot(contains('tunnels: # one line config')));
      expect(text, isNot(contains('114.114.114.114:53,proxy')));
      expect(text, isNot(contains('rds.mysql.com:3306,vpn')));
      expect(text, isNot(contains('target: target.com')));
      expect(text, contains('dns:'));
      expect(() => loadYaml(text), returnsNormally);
    });

    test('removes unresolved dialer-proxy placeholder from inline provider', () {
      const raw = '''
proxy-providers:
  provider2:
    type: inline
    dialer-proxy: proxy
    payload:
      - name: ss1
        type: ss
        server: example.com
        port: 443
        cipher: aes-128-gcm
        password: secret
''';

      final bytes = Uint8List.fromList(utf8.encode(raw));
      final normalized = ProfileExtension.normalizeImportedConfigBytes(bytes);
      final text = utf8.decode(normalized);

      expect(text, isNot(contains('dialer-proxy: proxy')));
      expect(text, contains('type: inline'));
      expect(() => loadYaml(text), returnsNormally);
    });

    test('rewrites invalid example proxy-group member vmess1 to vmess', () {
      const raw = '''
proxies:
  - name: ss1
    type: ss
    server: example.com
    port: 443
    cipher: aes-128-gcm
    password: secret
  - name: ss2
    type: ss
    server: example2.com
    port: 443
    cipher: aes-128-gcm
    password: secret
  - name: vmess
    type: vmess
    server: example3.com
    port: 443
    uuid: 11111111-1111-1111-1111-111111111111
    alterId: 0
    cipher: auto
proxy-groups:
  - name: auto
    type: url-test
    proxies:
      - ss1
      - ss2
      - vmess1
''';

      final bytes = Uint8List.fromList(utf8.encode(raw));
      final normalized = ProfileExtension.normalizeImportedConfigBytes(bytes);
      final text = utf8.decode(normalized);

      expect(text, contains('- vmess'));
      expect(text, isNot(contains('- vmess1')));
      expect(() => loadYaml(text), returnsNormally);
    });

    test('removes deprecated relay proxy-group example block', () {
      const raw = '''
proxy-groups:
  - name: "relay"
    type: relay
    proxies:
      - http
      - vmess
      - ss1
      - ss2
  - name: "auto"
    type: url-test
    proxies:
      - ss1
      - ss2
      - vmess
''';

      final bytes = Uint8List.fromList(utf8.encode(raw));
      final normalized = ProfileExtension.normalizeImportedConfigBytes(bytes);
      final text = utf8.decode(normalized);

      expect(text, isNot(contains('name: "relay"')));
      expect(text, isNot(contains('type: relay')));
      expect(text, contains('name: "auto"'));
      expect(() => loadYaml(text), returnsNormally);
    });

    test(
      'collapses openvpn sample singleton server and password lists to scalars',
      () {
        const raw = '''
proxies:
  - name: openvpn
    type: openvpn
    server: [YOUR_SERVER_IP]
    port: 1194
    password: [YOUR_SS_PASSWORD]
    plugin-opts:
      password: [YOUR_RESTLS_PASSWORD]
''';

        final bytes = Uint8List.fromList(utf8.encode(raw));
        final normalized = ProfileExtension.normalizeImportedConfigBytes(bytes);
        final text = utf8.decode(normalized);

        expect(text, contains('server: YOUR_SERVER_IP'));
        expect(text, contains('password: YOUR_SS_PASSWORD'));
        expect(text, contains('password: YOUR_RESTLS_PASSWORD'));
        expect(text, isNot(contains('[YOUR_SERVER_IP]')));
        expect(text, isNot(contains('[YOUR_SS_PASSWORD]')));
        expect(text, isNot(contains('[YOUR_RESTLS_PASSWORD]')));
      },
    );

    test('expands openvpn tls-crypt placeholder into an indented block', () {
      const raw = '''
proxies:
  - name: openvpn
    type: openvpn
    server: vpn.example.com
    port: 1194
    tls-crypt: |
      ...
''';

      final bytes = Uint8List.fromList(utf8.encode(raw));
      final normalized = ProfileExtension.normalizeImportedConfigBytes(bytes);
      final text = utf8.decode(normalized);

      expect(text, contains('tls-crypt: |'));
      expect(text, contains('-----BEGIN OpenVPN Static key V1-----'));
      expect(text, contains('00000000000000000000000000000000'));
      expect(text, contains('-----END OpenVPN Static key V1-----'));
      expect(() => loadYaml(text), returnsNormally);
    });

    test('collapses block singleton server and password lists to scalars', () {
      const raw = '''
proxies:
  - name: test
    type: shadowsocks
    server:
      - example.com
    port: 443
    password:
      - secret
''';

      final bytes = Uint8List.fromList(utf8.encode(raw));
      final normalized = ProfileExtension.normalizeImportedConfigBytes(bytes);
      final text = utf8.decode(normalized);

      expect(text, contains('server: example.com'));
      expect(text, contains('password: secret'));
      expect(text, isNot(contains('server:\n      - example.com')));
      expect(text, isNot(contains('password:\n      - secret')));
    });

    test('replaces vless encryption placeholder with none', () {
      const raw = '''
proxies:
  - name: vless-encryption
    type: vless
    server: example.com
    port: 443
    uuid: uuid
    encryption: "mlkem768x25519plus.native/xorpub/random.1rtt/0rtt.(padding len).(padding gap).(X25519 Password).(ML-KEM-768 Client)..."
''';

      final bytes = Uint8List.fromList(utf8.encode(raw));
      final normalized = ProfileExtension.normalizeImportedConfigBytes(bytes);
      final text = utf8.decode(normalized);

      expect(text, contains('encryption: "none"'));
      expect(text, isNot(contains('mlkem768x25519plus.native/xorpub/random')));
    });

    test('replaces reality placeholder keys with concrete sample values', () {
      const raw = '''
proxies:
  - name: vless-reality
    type: vless
    server: example.com
    port: 443
    uuid: uuid
    reality-opts:
      public-key: xxx
      short-id: xxx
''';

      final bytes = Uint8List.fromList(utf8.encode(raw));
      final normalized = ProfileExtension.normalizeImportedConfigBytes(bytes);
      final text = utf8.decode(normalized);

      expect(
        text,
        contains('public-key: CrrQSjAG_YkHLwvM2M-7XkKJilgL5upBKCp0od0tLhE'),
      );
      expect(text, contains('short-id: 10f897e26c4b9478'));
      expect(text, isNot(contains('public-key: xxx')));
      expect(text, isNot(contains('short-id: xxx')));
    });

    test(
      'removes inline ovpn ca tags while preserving certificate payload',
      () {
        const raw = '''
proxies:
  - name: trojan-sample
    type: trojan
    server: example.com
    port: 443
    password: secret
    ca: |
      <ca>
      -----BEGIN CERTIFICATE-----
      abc123
      -----END CERTIFICATE-----
      </ca>
''';

        final bytes = Uint8List.fromList(utf8.encode(raw));
        final normalized = ProfileExtension.normalizeImportedConfigBytes(bytes);
        final text = utf8.decode(normalized);

        expect(text, contains('ca: |'));
        expect(text, contains('-----BEGIN CERTIFICATE-----'));
        expect(text, contains('-----END CERTIFICATE-----'));
        expect(text, isNot(contains('<ca>')));
        expect(text, isNot(contains('</ca>')));
      },
    );

    test(
      'normalizes documented openvpn pem placeholders to parseable pem blocks',
      () {
        const raw = '''
proxies:
  - name: openvpn
    type: openvpn
    server: vpn.example.com
    port: 1194
    ca: |
      -----BEGIN CERTIFICATE-----
      MIIB...example
      -----END CERTIFICATE-----
    cert: |
      -----BEGIN CERTIFICATE-----
      MIIB...example
      -----END CERTIFICATE-----
    key: |
      -----BEGIN PRIVATE KEY-----
      MIIE...example
      -----END PRIVATE KEY-----
''';

        final bytes = Uint8List.fromList(utf8.encode(raw));
        final normalized = ProfileExtension.normalizeImportedConfigBytes(bytes);
        final text = utf8.decode(normalized);

        expect(text, isNot(contains('MIIB...example')));
        expect(text, isNot(contains('MIIE...example')));
        expect(text, contains('QbG/Z7JQGg+Jb42bBYK6q8I4g5sw'));
        expect(text, contains('IG1paG9tb19vcGVudnBuX3Rlc3Rfa2V5XzEyMzQ1Njc4'));
        expect(() => loadYaml(text), returnsNormally);
      },
    );

    test(
      'normalizes documented openvpn tls-crypt placeholder to hex content',
      () {
        const raw = '''
proxies:
  - name: openvpn
    type: openvpn
    server: vpn.example.com
    port: 1194
    tls-crypt: |
      -----BEGIN OpenVPN Static key V1-----
      00000000000000000000000000000000
      ...
      -----END OpenVPN Static key V1-----
''';

        final bytes = Uint8List.fromList(utf8.encode(raw));
        final normalized = ProfileExtension.normalizeImportedConfigBytes(bytes);
        final text = utf8.decode(normalized);
        final hexLines = text
            .split('\n')
            .map((line) => line.trim())
            .where(
              (line) =>
                  line.isNotEmpty &&
                  !line.startsWith('-----BEGIN OpenVPN Static key') &&
                  !line.startsWith('-----END OpenVPN Static key') &&
                  RegExp(r'^[0-9a-fA-F]+$').hasMatch(line),
            )
            .toList();
        final hexBody = hexLines.join();

        expect(text, isNot(contains('...')));
        expect(text, contains('-----BEGIN OpenVPN Static key V1-----'));
        expect(text, contains('-----END OpenVPN Static key V1-----'));
        expect(hexBody.length, 512);
        expect(() => loadYaml(text), returnsNormally);
      },
    );

    test(
      'replaces tls-crypt placeholder body without duplicating begin or end tags',
      () {
        const raw = '''
proxies:
  - name: openvpn
    type: openvpn
    server: vpn.example.com
    port: 1194
    tls-crypt: |
      -----BEGIN OpenVPN Static key V1-----
      00000000000000000000000000000000
      ...
      -----END OpenVPN Static key V1-----
''';

        final bytes = Uint8List.fromList(utf8.encode(raw));
        final normalized = ProfileExtension.normalizeImportedConfigBytes(bytes);
        final text = utf8.decode(normalized);
        final beginCount = RegExp(
          '-----BEGIN OpenVPN Static key V1-----',
        ).allMatches(text).length;
        final endCount = RegExp(
          '-----END OpenVPN Static key V1-----',
        ).allMatches(text).length;
        final hexLines = text
            .split('\n')
            .map((line) => line.trim())
            .where(
              (line) =>
                  line.isNotEmpty &&
                  !line.startsWith('-----BEGIN OpenVPN Static key') &&
                  !line.startsWith('-----END OpenVPN Static key') &&
                  RegExp(r'^[0-9a-fA-F]+$').hasMatch(line),
            )
            .toList();

        expect(beginCount, 1);
        expect(endCount, 1);
        expect(hexLines.join().length, 512);
        expect(() => loadYaml(text), returnsNormally);
      },
    );

    test('removes empty certificate fields that break core validation', () {
      const raw = '''
proxies:
  - name: mtls-sample
    type: vmess
    server: example.com
    port: 443
    uuid: 11111111-1111-1111-1111-111111111111
    alterId: 0
    cipher: auto
    certificate: ""
    private-key:
''';

      final bytes = Uint8List.fromList(utf8.encode(raw));
      final normalized = ProfileExtension.normalizeImportedConfigBytes(bytes);
      final text = utf8.decode(normalized);

      expect(text, isNot(contains('certificate: ""')));
      expect(text, isNot(contains('private-key:')));
      expect(() => loadYaml(text), returnsNormally);
    });

    test(
      'removes placeholder certificate blocks that break core validation',
      () {
        const raw = '''
proxies:
  - name: hysteria2-sample
    type: hysteria2
    server: example.com
    port: 443
    password: secret
    sni: example.com
    skip-cert-verify: true
    certificate:
    private-key:
''';

        final bytes = Uint8List.fromList(utf8.encode(raw));
        final normalized = ProfileExtension.normalizeImportedConfigBytes(bytes);
        final text = utf8.decode(normalized);

        expect(text, isNot(contains('certificate:')));
        expect(text, isNot(contains('private-key:')));
        expect(() => loadYaml(text), returnsNormally);
      },
    );

    test('removes empty certificate block scalars with only comments', () {
      const raw = '''
proxies:
  - name: commented-empty-mtls
    type: hysteria2
    server: example.com
    port: 443
    password: secret
    certificate: | # placeholder only
      # copy cert here
    private-key: >
      # copy key here
''';

      final bytes = Uint8List.fromList(utf8.encode(raw));
      final normalized = ProfileExtension.normalizeImportedConfigBytes(bytes);
      final text = utf8.decode(normalized);

      expect(text, isNot(contains('certificate: |')));
      expect(text, isNot(contains('private-key: >')));
      expect(text, isNot(contains('copy cert here')));
      expect(text, isNot(contains('copy key here')));
      expect(() => loadYaml(text), returnsNormally);
    });

    test('collapses documented restls placeholder lists to scalars', () {
      const raw = '''
proxies:
  - name: "ss-restls-tls13"
    type: ss
    server: [YOUR_SERVER_IP]
    port: 443
    cipher: chacha20-ietf-poly1305
    password: [YOUR_SS_PASSWORD]
    client-fingerprint:
      chrome
    plugin: restls
    plugin-opts:
      host:
        "www.microsoft.com"
      password: [YOUR_RESTLS_PASSWORD]
      version-hint: "tls13"
''';

      final bytes = Uint8List.fromList(utf8.encode(raw));
      final normalized = ProfileExtension.normalizeImportedConfigBytes(bytes);
      final text = utf8.decode(normalized);

      expect(text, contains('server: YOUR_SERVER_IP'));
      expect(text, contains('password: YOUR_SS_PASSWORD'));
      expect(text, contains('password: YOUR_RESTLS_PASSWORD'));
      expect(text, contains('client-fingerprint: chrome'));
      expect(text, contains('host: "www.microsoft.com"'));
      expect(text, isNot(contains('server: [YOUR_SERVER_IP]')));
      expect(text, isNot(contains('password: [YOUR_SS_PASSWORD]')));
      expect(text, isNot(contains('password: [YOUR_RESTLS_PASSWORD]')));
      expect(text, isNot(contains('client-fingerprint:\n      chrome')));
      expect(text, isNot(contains('host:\n        "www.microsoft.com"')));
      expect(() => loadYaml(text), returnsNormally);
    });

    test('injects placeholder certs for documented tuic listener sample', () {
      const raw = '''
listeners:
  - name: tuic-in-1
    type: tuic
    port: 10815
    listen: 0.0.0.0
''';

      final bytes = Uint8List.fromList(utf8.encode(raw));
      final normalized = ProfileExtension.normalizeImportedConfigBytes(bytes);
      final text = utf8.decode(normalized);

      expect(text, contains('certificate: ./server.crt'));
      expect(text, contains('private-key: ./server.key'));
      expect(() => loadYaml(text), returnsNormally);
    });

    test(
      'injects placeholder certs for documented hysteria2 listener sample',
      () {
        const raw = '''
listeners:
  - name: hysteria2-in-1
    type: hysteria2
    port: 10820
    listen: 0.0.0.0
''';

        final bytes = Uint8List.fromList(utf8.encode(raw));
        final normalized = ProfileExtension.normalizeImportedConfigBytes(bytes);
        final text = utf8.decode(normalized);

        expect(text, contains('certificate: ./server.crt'));
        expect(text, contains('private-key: ./server.key'));
        expect(() => loadYaml(text), returnsNormally);
      },
    );
  });
}
