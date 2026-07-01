'use strict';

const fs = require('fs');
const path = require('path');

function removePathSync(targetPath) {
  if (!fs.existsSync(targetPath)) {
    return;
  }

  const stat = fs.lstatSync(targetPath);
  if (stat.isDirectory() && !stat.isSymbolicLink()) {
    for (const entry of fs.readdirSync(targetPath)) {
      removePathSync(path.join(targetPath, entry));
    }
    fs.rmdirSync(targetPath);
    return;
  }

  fs.rmSync(targetPath, {force: true});
}

const originalRmdirSync = fs.rmdirSync;

fs.rmdirSync = function patchedRmdirSync(targetPath, options) {
  if (options && typeof options === 'object' && options.recursive === true) {
    removePathSync(targetPath);
    return;
  }
  return originalRmdirSync.apply(this, arguments);
};
