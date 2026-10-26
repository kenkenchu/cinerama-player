#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
CACHE="$ROOT_DIR/.build/metal-mpeg2"
SOURCE="$CACHE/ffmpeg-8.0.1"
PREFIX="$CACHE/install"
OUTPUT="$ROOT_DIR/Frameworks/CineramaMPEG2.xcframework"
HASH="05ee0b03119b45c0bdb4df654b96802e909e0a752f72e4fe3794f487229e5a41"
mkdir -p "$CACHE"
# Stamp covers bridge, kernel, headers, patch and this builder.
STAMP=$(cat Native/CineramaMPEG2/Decoder.mm Native/CineramaMPEG2/include/CineramaMPEG2.h Native/CineramaMPEG2/patch_ffmpeg.py Native/CineramaMPEG2/exports.txt ci_scripts/install_cinerama_mpeg2.sh | shasum -a 256 | cut -d ' ' -f 1)
if [ -f "$OUTPUT/source.sha256" ] && [ "$(cat "$OUTPUT/source.sha256")" = "$STAMP" ]; then exit 0; fi
if [ ! -f "$CACHE/ffmpeg-8.0.1.tar.xz" ]; then
    curl --fail --location --retry 3 --proto '=https' --tlsv1.2 https://ffmpeg.org/releases/ffmpeg-8.0.1.tar.xz -o "$CACHE/ffmpeg-8.0.1.tar.xz.partial"
    mv "$CACHE/ffmpeg-8.0.1.tar.xz.partial" "$CACHE/ffmpeg-8.0.1.tar.xz"
fi
printf '%s  %s\n' "$HASH" "$CACHE/ffmpeg-8.0.1.tar.xz" | shasum -a 256 --check
if [ ! -d "$SOURCE" ]; then tar -xf "$CACHE/ffmpeg-8.0.1.tar.xz" -C "$CACHE"; fi
python3 Native/CineramaMPEG2/patch_ffmpeg.py "$SOURCE"
FFMPEG_STAMP=$(cat Native/CineramaMPEG2/patch_ffmpeg.py ci_scripts/install_cinerama_mpeg2.sh | shasum -a 256 | cut -d ' ' -f 1)
if [ ! -f "$PREFIX/lib/libavcodec.a" ] || [ ! -f "$PREFIX/ffmpeg.sha256" ] || [ "$(cat "$PREFIX/ffmpeg.sha256")" != "$FFMPEG_STAMP" ]; then
    (cd "$SOURCE"
     ./configure --prefix="$PREFIX" --cc="$(xcrun -f clang)" --arch=arm64 --target-os=darwin --sysroot="$(xcrun --sdk macosx --show-sdk-path)" \
       --host-cflags="-isysroot $(xcrun --sdk macosx --show-sdk-path)" \
       --host-ldflags="-isysroot $(xcrun --sdk macosx --show-sdk-path)" \
       --extra-cflags='-mmacosx-version-min=26.0 -fvisibility=hidden' \
       --disable-shared --enable-static --enable-pic --disable-autodetect --disable-gpl --disable-nonfree \
       --disable-doc --disable-programs --disable-avdevice --enable-avfilter \
       --disable-everything --enable-filter=bwdif,buffer,buffersink --enable-avcodec --enable-avformat --enable-swresample --enable-swscale \
       --enable-encoder=mpeg2video,ac3 --enable-muxer=mpegts,hls --enable-decoder=mpeg2video,ac3,eac3,aac,mp2 --enable-parser=mpegvideo,ac3,aac,mpegaudio \
       --enable-demuxer=hls,mpegts,mpegvideo,mov --enable-protocol=file,http,https,tcp,tls,crypto \
       --enable-securetransport
     make -j "$(sysctl -n hw.logicalcpu)"
     make install)
    printf '%s\n' "$FFMPEG_STAMP" > "$PREFIX/ffmpeg.sha256"
fi
STAGE="$CACHE/framework/CineramaMPEG2.framework"
if [ -d "$STAGE" ]; then mv "$STAGE" "$CACHE/previous-framework-$(date +%s)"; fi
mkdir -p "$STAGE/Versions/A/Headers" "$STAGE/Versions/A/Modules" "$STAGE/Versions/A/Resources"
ln -s A "$STAGE/Versions/Current"
for item in Headers Modules Resources CineramaMPEG2; do ln -s "Versions/Current/$item" "$STAGE/$item"; done
cp Native/CineramaMPEG2/include/CineramaMPEG2.h "$STAGE/Headers/"
printf 'framework module CineramaMPEG2 { umbrella header "CineramaMPEG2.h" export * }\n' > "$STAGE/Modules/module.modulemap"
cat > "$STAGE/Resources/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.cinerama-player.mpeg2</string><key>CFBundleName</key><string>CineramaMPEG2</string><key>CFBundleExecutable</key><string>CineramaMPEG2</string><key>CFBundlePackageType</key><string>FMWK</string><key>CFBundleVersion</key><string>1</string></dict></plist>
PLIST
mkdir -p "$CACHE/relink"
xcrun clang++ -isysroot "$(xcrun --sdk macosx --show-sdk-path)" -std=c++17 -O3 -fobjc-arc -mmacosx-version-min=26.0 \
    -I "$PREFIX/include" -iquote "$SOURCE" -I Native/CineramaMPEG2/include \
    -c Native/CineramaMPEG2/Decoder.mm -o "$CACHE/relink/Decoder.o"
xcrun clang++ -isysroot "$(xcrun --sdk macosx --show-sdk-path)" -dynamiclib -mmacosx-version-min=26.0 \
    "$CACHE/relink/Decoder.o" -L "$PREFIX/lib" \
    -lavformat -lavfilter -lavcodec -lswresample -lswscale -lavutil -lz -lbz2 -liconv \
    -framework Foundation -framework Metal -framework CoreMedia -framework CoreVideo \
    -framework AudioToolbox -framework Security -framework CoreFoundation \
    -Wl,-install_name,@rpath/CineramaMPEG2.framework/CineramaMPEG2 \
    -Wl,-exported_symbols_list,Native/CineramaMPEG2/exports.txt -o "$STAGE/Versions/A/CineramaMPEG2"
# Replace only this generated, ignored framework.
if [ -d "$OUTPUT" ]; then mv "$OUTPUT" "$CACHE/previous-xcframework-$(date +%s)"; fi
xcodebuild -create-xcframework -framework "$STAGE" -output "$OUTPUT"
printf '%s\n' "$STAMP" > "$OUTPUT/source.sha256"
