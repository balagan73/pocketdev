# Android SDK stack runtime env — sourced by rebuild.sh (host-side) to
# compute the container's env_file. Not sourced inside the container itself.
export ANDROID_SDK_ROOT=/home/node/android-sdk
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export PATH="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"
