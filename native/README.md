# Native player libraries

The Android build plays through libmpv and FFmpeg, which come as one prebuilt
tarball per ABI. Plezy takes them from
[edde746/mpv-build](https://github.com/edde746/mpv-build); `mpv-build.lock.json`
names the commit, the tarballs and their sha256 checksums.

Plebz builds these tarballs itself, from the same mpv-build commit
(`93aa2d2db12eb594df3dab04882a6f5fe148b3aa`), with one change:
FFmpeg moves from n8.0.1 to **n8.0.3** for the security fixes in 8.0.2 and
8.0.3 (CVE-2025-67306, CVE-2026-8461, CVE-2026-30999). That change is
[`mpv-build-ffmpeg-8.0.3.patch`](mpv-build-ffmpeg-8.0.3.patch); mpv, every
patch and every other dependency stay as mpv-build pins them.

The tarballs are not published. `mpv-build.lock.json` points at the folder the
Plebz build reads them from (`file:///Users/Shared/plebz-native/android`), so
to build this tree, make them first.

## Building the tarballs

On Linux or macOS, with the Android NDK named in mpv-build's
`toolchain/android.txt` (29.0.14206865) and the host tools its
`platforms/android/include/download-sdk.sh` lists (plus rustup for libdovi,
jinja2 for mbedtls and, on macOS, GNU tar):

```bash
git clone https://github.com/edde746/mpv-build.git
cd mpv-build
git checkout 93aa2d2db12eb594df3dab04882a6f5fe148b3aa
git apply /path/to/plebz/native/mpv-build-ffmpeg-8.0.3.patch
cd platforms/android
export MPV_ANDROID_SDK=/path/to/android-sdk   # contains ndk/29.0.14206865
./download.sh && ./build.sh && ./package.sh
```

`package.sh` writes `dist/release/libmpv-android-<abi>.tar.gz`. Plebz then
removes the debug info from every library but `libc++_shared.so`
(`llvm-strip --strip-debug`, from the same NDK) — it would carry the build
machine's paths — and packs them again the way `package.sh` does
(`tar --sort=name --owner=0 --group=0 --numeric-owner --mtime='2020-01-01
00:00:00 UTC'`, `gzip -n -9`) as `libmpv-android-c42a5a2d938e-<abi>.tar.gz`.
`c42a5a2d938e` is the content key mpv-build derives from these sources
(`python3 scripts/keys.py keys --platform-group android`).

## Using your own build

Either put the four tarballs where the lock expects them and set their
checksums in `mpv-build.lock.json`, or point Gradle at their folder, which
skips the checksums:

```bash
export PLEZY_LOCAL_MPV_DIR=/path/to/tarballs   # or -Pplezy.localMpvDir=...
```

The Media3 adapter compiles against FFmpeg's headers of the same release;
`android/app/build.gradle.kts` fetches them from ffmpeg.org
(`ffmpeg-8.0.3.tar.xz`, checksum pinned there).

Once mpv-build itself pins FFmpeg 8.0.3 or later, Plebz goes back to its
published tarballs and this folder goes away.
