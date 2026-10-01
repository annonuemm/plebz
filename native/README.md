# Native player libraries

The Android build plays through libmpv and FFmpeg, one prebuilt tarball per
ABI, named with their sha256 checksums in `mpv-build.lock.json`. They are built
from [edde746/mpv-build](https://github.com/edde746/mpv-build) at commit
`93aa2d2db12eb594df3dab04882a6f5fe148b3aa` with
[`mpv-build.patch`](mpv-build.patch) applied, which moves some dependency
versions forward and adds one patch of its own. The tarballs are not
published.

## Building the tarballs

With the Android NDK named in mpv-build's `toolchain/android.txt` and the host
tools its `platforms/android/include/download-sdk.sh` lists:

```bash
git clone https://github.com/edde746/mpv-build.git
cd mpv-build
git checkout 93aa2d2db12eb594df3dab04882a6f5fe148b3aa
git apply /path/to/plebz/native/mpv-build.patch
cd platforms/android
export MPV_ANDROID_SDK=/path/to/android-sdk
./download.sh && ./build.sh && ./package.sh
```

`package.sh` writes `dist/release/libmpv-android-<abi>.tar.gz`. Every library
but `libc++_shared.so` then has its debug info removed
(`llvm-strip --strip-debug`, from the same NDK) and is packed again
(`tar --sort=name --owner=0 --group=0 --numeric-owner --mtime='2020-01-01
00:00:00 UTC' -cf - lib include | gzip -n -9`) as
`libmpv-android-<key>-<abi>.tar.gz`, where `<key>` comes from
`python3 scripts/keys.py keys --platform-group android`.

## Using your own build

Put the four tarballs where the lock expects them and set their checksums in
`mpv-build.lock.json`, or point Gradle at their folder, which skips the
checksums:

```bash
export PLEZY_LOCAL_MPV_DIR=/path/to/tarballs   # or -Pplezy.localMpvDir=...
```
