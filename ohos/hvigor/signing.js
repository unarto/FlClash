'use strict';

const childProcess = require('child_process');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const APP_RELEASE_ALIAS = 'openharmony application release';
const APP_CA_ALIAS = 'openharmony application ca';
const APP_ROOT_CA_ALIAS = 'openharmony application root ca';
const PROFILE_RELEASE_ALIAS = 'openharmony application profile release';
const DEFAULT_STORE_PASSWORD = '123456';
const DEFAULT_SIGN_ALG = 'SHA256withECDSA';

function ensureDir(dirPath) {
  if (!dirPath || dirPath === '.' || fs.existsSync(dirPath)) {
    return;
  }
  ensureDir(path.dirname(dirPath));
  try {
    fs.mkdirSync(dirPath);
  } catch (error) {
    if (!fs.existsSync(dirPath)) {
      throw error;
    }
  }
}

function execJava(signToolPath, args) {
  return execFile('java', ['-jar', signToolPath, ...args]);
}

function exportCertificate(keystorePath, alias, outputPath, asPem = false) {
  const args = [
    '-exportcert',
    '-alias',
    alias,
    '-keystore',
    keystorePath,
    '-storetype',
    'PKCS12',
    '-storepass',
    DEFAULT_STORE_PASSWORD,
    '-file',
    outputPath,
  ];
  if (asPem) {
    args.splice(1, 0, '-rfc');
    args.splice(args.length - 2, 2);
    const content = execFile('keytool', args);
    fs.writeFileSync(outputPath, content);
    return;
  }
  execFile('keytool', args);
}

function pemFingerprint(pemContent) {
  const der = execFile('openssl', ['x509', '-inform', 'PEM', '-outform', 'DER'], {
    input: pemContent,
    encoding: 'buffer',
  });
  return crypto.createHash('sha256').update(der).digest('hex');
}

function execFile(command, args, options = {}) {
  return childProcess.execFileSync(command, args, {
    encoding: options.encoding === 'buffer' ? null : (options.encoding || 'utf8'),
    input: options.input,
    stdio: ['pipe', 'pipe', 'pipe'],
  });
}

function readLatestLeafCertificate(certChainPath) {
  const content = fs.readFileSync(certChainPath, 'utf8');
  const certificates = content.match(/-----BEGIN CERTIFICATE-----[\s\S]*?-----END CERTIFICATE-----/g);
  if (!certificates || certificates.length === 0) {
    throw new Error(`No certificates found in ${certChainPath}`);
  }
  return certificates[0].trim() + '\n';
}

function buildProfileContent(bundleName, distributionCertificate) {
  return {
    'version-name': '2.0.0',
    'version-code': 2,
    'app-distribution-type': 'os_integration',
    'uuid': 'e8c0cf4e-414d-40e9-99df-c00e6a5f0d99',
    'validity': {
      'not-before': 1710000000,
      'not-after': 1893456000,
    },
    'type': 'release',
    'bundle-info': {
      'developer-id': 'OpenHarmony',
      'distribution-certificate': distributionCertificate,
      'bundle-name': bundleName,
      'apl': 'normal',
      'app-feature': 'hos_normal_app',
    },
    'acls': {
      'allowed-acls': [''],
    },
    'permissions': {
      'restricted-permissions': [],
    },
    'issuer': 'pki_internal',
  };
}

function fileExists(filePath) {
  try {
    return fs.statSync(filePath).isFile();
  } catch (_) {
    return false;
  }
}

function prepareOpenHarmonySigningAssets(options) {
  const {
    appHome,
    ohosSdkHome,
    signToolPath,
    bundleName,
  } = options;
  const keystorePath = path.join(ohosSdkHome, 'toolchains', 'lib', 'OpenHarmony.p12');
  const profileCertPath = path.join(ohosSdkHome, 'toolchains', 'lib', 'OpenHarmonyProfileRelease.pem');
  const outputDir = path.join(appHome, 'hvigor', '.signing', 'openharmony');

  if (!fileExists(keystorePath) || !fileExists(profileCertPath) || !fileExists(signToolPath)) {
    return;
  }

  ensureDir(outputDir);

  const rootCaPath = path.join(outputDir, 'OpenHarmonyApplicationRoot.cer');
  const appCaPath = path.join(outputDir, 'OpenHarmonyApplicationCA.cer');
  const appCertChainPath = path.join(outputDir, 'OpenHarmonyApplicationRelease.cer');
  const localKeystorePath = path.join(outputDir, 'OpenHarmony.p12');
  const profileInputPath = path.join(outputDir, 'OpenHarmonyProfileRelease.json');
  const signedProfilePath = path.join(outputDir, 'OpenHarmonyProfileRelease.p7b');
  const metadataPath = path.join(outputDir, 'metadata.json');

  fs.copyFileSync(keystorePath, localKeystorePath);
  exportCertificate(keystorePath, APP_ROOT_CA_ALIAS, rootCaPath, false);
  exportCertificate(keystorePath, APP_CA_ALIAS, appCaPath, false);

  execJava(signToolPath, [
    'generate-app-cert',
    '-keyAlias', APP_RELEASE_ALIAS,
    '-keyPwd', DEFAULT_STORE_PASSWORD,
    '-issuer', 'C=CN,O=OpenHarmony,OU=OpenHarmony Team,CN=OpenHarmony Application CA',
    '-issuerKeyAlias', APP_CA_ALIAS,
    '-issuerKeyPwd', DEFAULT_STORE_PASSWORD,
    '-subject', 'C=CN,O=OpenHarmony,OU=OpenHarmony Team,CN=OpenHarmony Application Release',
    '-validity', '3650',
    '-signAlg', DEFAULT_SIGN_ALG,
    '-rootCaCertFile', rootCaPath,
    '-subCaCertFile', appCaPath,
    '-keystoreFile', keystorePath,
    '-keystorePwd', DEFAULT_STORE_PASSWORD,
    '-outForm', 'certChain',
    '-outFile', appCertChainPath,
    '-issuerKeystoreFile', keystorePath,
    '-issuerKeystorePwd', DEFAULT_STORE_PASSWORD,
  ]);

  const distributionCertificate = readLatestLeafCertificate(appCertChainPath);
  const profileContent = buildProfileContent(bundleName, distributionCertificate);
  fs.writeFileSync(profileInputPath, `${JSON.stringify(profileContent, null, 2)}\n`);

  execJava(signToolPath, [
    'sign-profile',
    '-mode', 'localSign',
    '-keyAlias', PROFILE_RELEASE_ALIAS,
    '-keyPwd', DEFAULT_STORE_PASSWORD,
    '-profileCertFile', profileCertPath,
    '-inFile', profileInputPath,
    '-signAlg', DEFAULT_SIGN_ALG,
    '-keystoreFile', keystorePath,
    '-keystorePwd', DEFAULT_STORE_PASSWORD,
    '-outFile', signedProfilePath,
  ]);

  const metadata = {
    bundleName,
    distributionCertificateSha256: pemFingerprint(distributionCertificate),
    appCertChainPath: path.relative(appHome, appCertChainPath),
    signedProfilePath: path.relative(appHome, signedProfilePath),
  };
  fs.writeFileSync(metadataPath, `${JSON.stringify(metadata, null, 2)}\n`);
}

module.exports = {
  prepareOpenHarmonySigningAssets,
};
