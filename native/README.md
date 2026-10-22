# Native player libraries

The Android build plays through mpv-build's mpv-android library: one AAR with
libmpv, FFmpeg and the JNI glue, named with its key and sha256 checksum in
`mpv-build.lock.json`. It is built from
[edde746/mpv-build](https://github.com/edde746/mpv-build) at commit
`582f6d6e748a87a1536bf5cdad0af97b75725ffb` with
[`mpv-build.patch`](mpv-build.patch) applied, which moves some dependency
versions forward. The AAR is not published.

## Building the AAR

With the Android NDK named in mpv-build's `toolchain/android.txt` and the host
tools its `platforms/android/include/download-sdk.sh` lists:

```bash
git clone https://github.com/edde746/mpv-build.git
cd mpv-build
git checkout 582f6d6e748a87a1536bf5cdad0af97b75725ffb
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
`libmpv-android-<key>-<abi>.tar.gz` in one folder. The AAR is then built from
that folder:

```bash
cd platforms/android/lib
ANDROID_HOME=/path/to/android-sdk ./gradlew -Pmpv.tarballs=/path/to/tarballs assembleRelease
```

and `build/outputs/aar/mpv-android-release.aar` is named
`mpv-android-<key>.aar`. Both keys come from
`python3 scripts/keys.py keys --platform-group android`.

## Using your own build

Put the AAR in the folder the lock's `assetBase` names and set its key and
checksum in `mpv-build.lock.json` and in
`android/gradle/verification-metadata.xml`.
