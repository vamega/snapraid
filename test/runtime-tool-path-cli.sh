#!/bin/sh
set -eu

SNAPRAID=${1:-./snapraid}
TMPBASE=${TMPDIR:-/tmp}
WORK=$(mktemp -d "${TMPBASE%/}/snapraid-tool-path-cli.XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM

mkdir -p "$WORK/disk1" "$WORK/first" "$WORK/last"

BASE_CONF="$WORK/base.conf"
BAD_CONF="$WORK/bad.conf"

cat > "$BASE_CONF" <<EOF
hashsize 16
blocksize 1
parity $WORK/parity
content $WORK/content
disk disk1 $WORK/disk1/
EOF

cat > "$BAD_CONF" <<EOF
hashsize 16
blocksize 1
parity $WORK/parity
content $WORK/content
disk disk1 $WORK/disk1/
smartctl_path $WORK/first/smartctl
EOF

write_tool() {
	path=$1
	cat > "$path" <<'EOF'
#!/bin/sh
exit 0
EOF
	chmod +x "$path"
}

write_zfs_tool() {
	path=$1
	cat > "$path" <<EOF
#!/bin/sh
if [ "\$1" = "list" ]; then
	printf '%s\t%s\t%s\n' 'testpool/data' 'fake-zfs-guid' '$WORK'
fi
exit 0
EOF
	chmod +x "$path"
}

write_tool "$WORK/first/smartctl"
write_tool "$WORK/last/smartctl"
write_zfs_tool "$WORK/first/zfs"
write_zfs_tool "$WORK/last/zfs"
write_tool "$WORK/first/zpool"
write_tool "$WORK/last/zpool"
write_tool "$WORK/first/bcachefs"
write_tool "$WORK/last/bcachefs"

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

assert_log_lacks() {
	log=$1
	unexpected=$2
	if grep -F "$unexpected" "$log" >/dev/null; then
		echo "Unexpected '$unexpected' in $log" >&2
		exit 1
	fi
}

UNUSED_LOG="$WORK/unused.log"
run_snapraid \
	--smartctl-path "$WORK/first/smartctl" \
	--zfs-path "$WORK/first/zfs" \
	--zpool-path "$WORK/first/zpool" \
	--bcachefs-path "$WORK/first/bcachefs" \
	-c "$BASE_CONF" -l "$UNUSED_LOG" status
assert_log_lacks "$UNUSED_LOG" "tool:smartctl:"
assert_log_lacks "$UNUSED_LOG" "tool:zfs:"
assert_log_lacks "$UNUSED_LOG" "tool:zpool:"
assert_log_lacks "$UNUSED_LOG" "tool:bcachefs:"

DUPLICATE_LOG="$WORK/duplicate.log"
run_snapraid \
	--smartctl-path "$WORK/first/smartctl" \
	--smartctl-path "$WORK/last/smartctl" \
	--zfs-path "$WORK/first/zfs" \
	--zfs-path "$WORK/last/zfs" \
	--zpool-path "$WORK/first/zpool" \
	--zpool-path "$WORK/last/zpool" \
	--bcachefs-path "$WORK/first/bcachefs" \
	--bcachefs-path "$WORK/last/bcachefs" \
	-c "$BASE_CONF" -l "$DUPLICATE_LOG" status
assert_log_lacks "$DUPLICATE_LOG" "tool:smartctl:"
assert_log_lacks "$DUPLICATE_LOG" "tool:zfs:"
assert_log_lacks "$DUPLICATE_LOG" "tool:zpool:"
assert_log_lacks "$DUPLICATE_LOG" "tool:bcachefs:"

ZFS_LOG="$WORK/zfs.log"
set +e
run_snapraid \
	--zfs-path "$WORK/first/zfs" \
	--zfs-path "$WORK/last/zfs" \
	--test-skip-parity-access \
	-c "$BASE_CONF" -l "$ZFS_LOG" diff > "$WORK/zfs.out" 2>&1
code=$?
set -e
if [ "$code" -ne 0 ] && [ "$code" -ne 2 ]; then
	cat "$WORK/zfs.out" >&2
	exit 1
fi
assert_log_has "$ZFS_LOG" "tool:zfs:$WORK/last/zfs"
assert_log_lacks "$ZFS_LOG" "tool:zfs:$WORK/first/zfs"

ZFS_DIR_LOG="$WORK/zfs-dir.log"
set +e
run_snapraid \
	--zfs-path "$WORK/first" \
	--test-skip-parity-access \
	-c "$BASE_CONF" -l "$ZFS_DIR_LOG" diff > "$WORK/zfs-dir.out" 2>&1
code=$?
set -e
if [ "$code" -ne 0 ] && [ "$code" -ne 2 ]; then
	cat "$WORK/zfs-dir.out" >&2
	exit 1
fi
assert_log_lacks "$ZFS_DIR_LOG" "tool:zfs:$WORK/first"

if run_snapraid --smartctl-path relative-smartctl -c "$BASE_CONF" status > "$WORK/relative.out" 2>&1; then
	echo "Expected relative smartctl path to fail" >&2
	exit 1
fi
assert_log_has "$WORK/relative.out" "requires an absolute path"

if run_snapraid -c "$BAD_CONF" status > "$WORK/config.out" 2>&1; then
	echo "Expected smartctl_path config option to fail" >&2
	exit 1
fi
assert_log_has "$WORK/config.out" "Invalid command 'smartctl_path'"
