# Tap Counter — cross-framework benchmark app

The minimal "Tap me" counter — Valdi's cell of a cross-framework startup / tap /
app-size benchmark (the driving comparison and results live in the `universal_ui`
repo, `docs/benchmarks.md`). It is deliberately behavior-identical to its
native-Compose, compiled-Swift, wasm, and React Native twins — one label + one
button, nothing else — so the numbers isolate runtime overhead (here: the native
Valdi runtime **plus** the JS engine) rather than app content.

`TapCounter.tsx` is the whole app: a `StatefulComponent` with a `count`, a
`[valdi-tap]` `console.log` on each render for latency correlation.

## Building the Android APK

This open-source checkout lacks Snap's internal `.bazelrc.internal`, which
normally wires the host Android SDK/NDK, a JDK, and a Java runtime toolchain for
the `os:android` target platform. Supply them explicitly:

```sh
export JAVA_HOME=/opt/homebrew/opt/openjdk@17     # any JDK 17
SDK=$HOME/Android/sdk
NDK=$SDK/ndk/28.0.13004108

bazel build //apps/tap_counter:tap_counter_app_android \
  --android_platforms=@rules_android//:arm64-v8a \
  --define client_repo_arm64=true \
  --extra_toolchains=//bzl/local_android_java:android_host_java_runtime_toolchain \
  --repo_env=ANDROID_HOME=$SDK \
  --repo_env=ANDROID_NDK_HOME=$NDK \
  --repo_env=JAVA_HOME=$JAVA_HOME
```

Why each flag:

- `--android_platforms=@rules_android//:arm64-v8a` — target arm64 devices; keeps
  host tool actions on the host toolchains (unlike a global `--platforms`, which
  clobbers the host JDK/CC toolchains).
- `--define client_repo_arm64=true` — selects `@snap_platforms//os:android_arm64`
  in `valdi_android_aar`'s `android_aar_platforms()` native-lib transition, so the
  aar actually contains `lib/arm64-v8a/libvaldi.so`. Without it the aar ships no
  native libs and the arch filter fails.
- `--extra_toolchains=//bzl/local_android_java:...` — a Java runtime toolchain for
  the `os:android` platform (the aar's deploy-jar step is resolved there and every
  stock rules_java JDK is host-OS-constrained). See that package's BUILD comment.

Install + launch:

```sh
adb install -r -d bazel-bin/apps/tap_counter/tap_counter_app_android.apk
adb shell am start -n com.snap.valdi.tap_counter_app/.StartActivity
```
