#!/bin/sh
set -eu

SNAPRAID=${1:-./snapraid}
TMPBASE=${TMPDIR:-/tmp}
WORK=$(mktemp -d "${TMPBASE%/}/snapraid-tool-path.XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM

mkdir -p "$WORK/disk1" "$WORK/bin" "$WORK/cli" "$WORK/other"

BASE_CONF="$WORK/base.conf"
TOOLS_CONF="$WORK/tools.conf"

cat > "$BASE_CONF" <<EOF
hashsize 16
blocksize 1
parity $WORK/parity
content $WORK/content
disk disk1 $WORK/disk1/
EOF

cat > "$TOOLS_CONF" <<EOF
hashsize 16
blocksize 1
parity $WORK/parity
content $WORK/content
disk disk1 $WORK/disk1/
smartctl_path $WORK/bin/smartctl
zfs_path $WORK/bin/zfs
zpool_path $WORK/bin/zpool
bcachefs_path $WORK/bin/bcachefs
EOF

run_snapraid() {
	"$SNAPRAID" --test-skip-device --test-skip-self --no-warnings "$@"
}

assert_log_has() {
	log=$1
	expected=$2
	if ! grep -F "$expected" "$log" >/dev/null; then
		echo "Missing '$expected' in $log" >&2
		exit 1
	fi
}

CONFIG_LOG="$WORK/config.log"
run_snapraid -c "$TOOLS_CONF" -l "$CONFIG_LOG" status
assert_log_has "$CONFIG_LOG" "tool:smartctl:$WORK/bin/smartctl"
assert_log_has "$CONFIG_LOG" "tool:zfs:$WORK/bin/zfs"
assert_log_has "$CONFIG_LOG" "tool:zpool:$WORK/bin/zpool"
assert_log_has "$CONFIG_LOG" "tool:bcachefs:$WORK/bin/bcachefs"

CLI_LOG="$WORK/cli.log"
run_snapraid \
	--smartctl-path "$WORK/cli/smartctl" \
	--zfs-path "$WORK/cli/zfs" \
	--zpool-path "$WORK/cli/zpool" \
	--bcachefs-path "$WORK/cli/bcachefs" \
	-c "$BASE_CONF" -l "$CLI_LOG" status
assert_log_has "$CLI_LOG" "tool:smartctl:$WORK/cli/smartctl"
assert_log_has "$CLI_LOG" "tool:zfs:$WORK/cli/zfs"
assert_log_has "$CLI_LOG" "tool:zpool:$WORK/cli/zpool"
assert_log_has "$CLI_LOG" "tool:bcachefs:$WORK/cli/bcachefs"

DUPLICATE_LOG="$WORK/duplicate.log"
run_snapraid \
	--smartctl-path "$WORK/bin/smartctl" \
	--smartctl-path "$WORK/cli/smartctl" \
	--zfs-path "$WORK/bin/zfs" \
	--zfs-path "$WORK/cli/zfs" \
	--zpool-path "$WORK/bin/zpool" \
	--zpool-path "$WORK/cli/zpool" \
	--bcachefs-path "$WORK/bin/bcachefs" \
	--bcachefs-path "$WORK/cli/bcachefs" \
	-c "$BASE_CONF" -l "$DUPLICATE_LOG" status
assert_log_has "$DUPLICATE_LOG" "tool:smartctl:$WORK/cli/smartctl"
assert_log_has "$DUPLICATE_LOG" "tool:zfs:$WORK/cli/zfs"
assert_log_has "$DUPLICATE_LOG" "tool:zpool:$WORK/cli/zpool"
assert_log_has "$DUPLICATE_LOG" "tool:bcachefs:$WORK/cli/bcachefs"

SAME_LOG="$WORK/same.log"
run_snapraid \
	--smartctl-path "$WORK/bin/smartctl" \
	--zfs-path "$WORK/bin/zfs" \
	--zpool-path "$WORK/bin/zpool" \
	--bcachefs-path "$WORK/bin/bcachefs" \
	-c "$TOOLS_CONF" -l "$SAME_LOG" status

OVERRIDE_LOG="$WORK/override.log"
run_snapraid --smartctl-path "$WORK/other/smartctl" -c "$TOOLS_CONF" -l "$OVERRIDE_LOG" status
assert_log_has "$OVERRIDE_LOG" "WARNING! 'smartctl_path' '$WORK/bin/smartctl' in '$TOOLS_CONF' overridden by command line '$WORK/other/smartctl'"
assert_log_has "$OVERRIDE_LOG" "tool:smartctl:$WORK/other/smartctl"

if run_snapraid --smartctl-path relative-smartctl -c "$BASE_CONF" status > "$WORK/relative.out" 2>&1; then
	echo "Expected relative smartctl path to fail" >&2
	exit 1
fi
assert_log_has "$WORK/relative.out" "requires an absolute path"
