#!/usr/bin/env bash

set -euo pipefail

PLATFORM="${PLATFORM:-linux/arm64}"
GO_TAGS="${GO_TAGS:-1.25-alpine}"

run_case() {
  local tag="$1"

  echo "===== ${tag} ====="
  docker run --rm --platform "${PLATFORM}" "golang:${tag}" sh -lc '
    set -eu
    export PATH=/usr/local/go/bin:$PATH
    apk add --no-cache build-base binutils >/dev/null

    mkdir -p /tmp/go-musl && cd /tmp/go-musl

    cat > libgo.go <<'"'"'EOF'"'"'
package main

/*
#include <stdint.h>
*/
import "C"

import "runtime"

//export Hello
func Hello() C.int {
  runtime.Gosched()
  return 42
}

func main() {}
EOF

    cat > loader.c <<'"'"'EOF'"'"'
#include <dlfcn.h>
#include <stdio.h>

typedef int (*hello_fn)(void);

int main(void) {
  void *h = dlopen("./libgo.so", RTLD_NOW | RTLD_LOCAL);
  if (!h) {
    puts(dlerror());
    return 2;
  }
  hello_fn hello = (hello_fn)dlsym(h, "Hello");
  if (!hello) {
    puts(dlerror());
    return 3;
  }
  printf("Hello()=%d\n", hello());
  return 0;
}
EOF

    cat > host.c <<'"'"'EOF'"'"'
#include "libgo.h"

int HostHello(void) { return Hello(); }
EOF

    cat > host_loader.c <<'"'"'EOF'"'"'
#include <dlfcn.h>
#include <stdio.h>

typedef int (*hosthello_fn)(void);

int main(void) {
  void *h = dlopen("./host.so", RTLD_NOW | RTLD_LOCAL);
  if (!h) {
    puts(dlerror());
    return 2;
  }
  hosthello_fn hello = (hosthello_fn)dlsym(h, "HostHello");
  if (!hello) {
    puts(dlerror());
    return 3;
  }
  printf("HostHello()=%d\n", hello());
  return 0;
}
EOF

    echo "-- go version --"
    go version

    echo "-- c-shared build --"
    CC=gcc CGO_ENABLED=1 GOOS=linux GOARCH=arm64 go build -buildmode=c-shared -o libgo.so libgo.go
    readelf -r libgo.so | grep TLS || true
    gcc -o loader loader.c -ldl
    echo "-- c-shared dlopen --"
    ./loader || true

    echo "-- c-archive build --"
    CC=gcc CGO_ENABLED=1 GOOS=linux GOARCH=arm64 go build -buildmode=c-archive -o libgo.a libgo.go
    gcc -shared -fPIC -o host.so host.c libgo.a -ldl -lpthread
    readelf -r host.so | grep TLS || true
    gcc -o host_loader host_loader.c -ldl
    echo "-- c-archive->host.so dlopen --"
    ./host_loader || true
  '
}

for tag in ${GO_TAGS}; do
  run_case "${tag}"
done
