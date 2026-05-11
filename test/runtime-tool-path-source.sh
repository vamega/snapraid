#!/bin/sh
set -eu

SRC_ROOT=${1:-.}

assert_has() {
	file=$1
	expected=$2
	if ! grep -F "$expected" "$SRC_ROOT/$file" >/dev/null; then
		echo "Missing '$expected' in $file" >&2
		exit 1
	fi
}

assert_not_has() {
	file=$1
	unexpected=$2
	if grep -F "$unexpected" "$SRC_ROOT/$file" >/dev/null; then
		echo "Unexpected '$unexpected' in $file" >&2
		exit 1
	fi
}

assert_has cmdline/snapraid.c "#if HAVE_GETOPT_LONG && !defined(__MINGW32__)"
assert_not_has cmdline/mingw.c "tool_path_smartctl"
assert_not_has cmdline/mingw.c "log_smartctl_path"
assert_not_has cmdline/mingw.c "tool_path_log(\"smartctl\""
assert_not_has snapraid.conf.example.windows "smartctl_path"
assert_not_has snapraid.conf.example.windows "zfs_path"
assert_not_has snapraid.conf.example.windows "zpool_path"
assert_not_has snapraid.conf.example.windows "bcachefs_path"
