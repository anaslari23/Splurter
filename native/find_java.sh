# Sourced by the build scripts: makes sure JAVA_HOME points at a JDK that has javac (the phone-side helper and Gradle need one).
# Uses the one you already set, else looks in the usual places. CI sets JAVA_HOME itself (actions/setup-java).
if [ -z "$JAVA_HOME" ] || [ ! -x "$JAVA_HOME/bin/javac" ]; then
  JAVA_HOME=""
  for c in "$(/usr/libexec/java_home 2>/dev/null)" /Applications/Android\ Studio*.app/Contents/jbr/Contents/Home \
           /opt/homebrew/opt/openjdk@17 /opt/homebrew/opt/openjdk@21 /opt/homebrew/opt/openjdk /usr/local/opt/openjdk@17 /usr/local/opt/openjdk; do
    if [ -n "$c" ] && [ -x "$c/bin/javac" ]; then JAVA_HOME="$c"; break; fi
  done
fi
[ -n "$JAVA_HOME" ] || { echo "No JDK with javac found. Install one (brew install openjdk@17) or set JAVA_HOME." >&2; exit 1; }
export JAVA_HOME
