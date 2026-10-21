#!/usr/bin/env bash
set -euo pipefail
TDLIB_COMMIT=$(cat "$(dirname "$0")/TDLIB_COMMIT")
P=/tmp/tdbuild-prefix
mkdir -p "$P" /tmp/tdlib-install
git clone https://github.com/madler/zlib.git /tmp/zlibsrc
(cd /tmp/zlibsrc && git checkout 51b7f2abdade71cd9bb0e7a373ef2610ec6f9daf && CC=x86_64-w64-mingw32-gcc-win32 ./configure --static --prefix="$P" && make -j$(nproc) install)
echo '2e8a40b01979afe8be0bbfb3de5dc1c6709fedb46d6c89c10da114ab5fc3d281  /tmp/openssl.tar.gz' > /tmp/openssl.sha256
curl -fsSL --retry 3 --connect-timeout 30 --max-time 600 -o /tmp/openssl.tar.gz https://github.com/openssl/openssl/releases/download/openssl-3.3.2/openssl-3.3.2.tar.gz
sha256sum -c /tmp/openssl.sha256
mkdir -p /tmp/opensslsrc && tar -C /tmp/opensslsrc --strip-components=1 -xzf /tmp/openssl.tar.gz
(cd /tmp/opensslsrc && ./Configure mingw64 no-asm no-shared no-tests no-docs --libdir=lib --prefix="$P" --cross-compile-prefix=x86_64-w64-mingw32- && make -j1 -s install_sw)
git clone https://github.com/tdlib/td.git /tmp/tdsrc
(cd /tmp/tdsrc && git checkout "$TDLIB_COMMIT")
cmake -S /tmp/tdsrc -B /tmp/tdsrc/build-host -DCMAKE_BUILD_TYPE=Release -DTD_ENABLE_JNI=OFF
cmake --build /tmp/tdsrc/build-host --target prepare_cross_compiling -j$(nproc)
cmake -S /tmp/tdsrc -B /tmp/tdsrc/build -G Ninja \
  -DCMAKE_SYSTEM_NAME=Windows \
  -DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++-win32 \
  -DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc-win32 \
  -DCMAKE_BUILD_TYPE=Release \
  -DOPENSSL_ROOT_DIR="$P" \
  -DZLIB_INCLUDE_DIR="$P/include" \
  -DZLIB_LIBRARY="$P/lib/libz.a" \
  -DTD_ENABLE_JNI=OFF \
  -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON
cmake --build /tmp/tdsrc/build --target tdjson_static -j$(nproc)
mkdir -p /tmp/tdlib-install/lib /tmp/tdlib-install/include/td
find /tmp/tdsrc/build -name '*.a' -exec cp {} /tmp/tdlib-install/lib/ \;
cp "$P"/lib/libcrypto.a "$P"/lib/libssl.a "$P"/lib/libz.a /tmp/tdlib-install/lib/
for m in tdactor tdclient tdcore tdnet tdutils tddb tdmtproto tde2e; do
  if [ -d "/tmp/tdsrc/$m/td" ]; then cp -r "/tmp/tdsrc/$m/td/." /tmp/tdlib-install/include/td/; fi
done
cp -r /tmp/tdsrc/td/. /tmp/tdlib-install/include/td/
cp -r /tmp/tdsrc/td/generate/auto/td/. /tmp/tdlib-install/include/td/
for lib in libstdc++.a libgcc_eh.a libgcc.a libgcc_s.a; do
  cp "$(x86_64-w64-mingw32-g++-win32 -print-file-name="$lib")" /tmp/tdlib-install/lib/
done
