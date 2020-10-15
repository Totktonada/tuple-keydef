#!/bin/sh

# runtest.sh tuple_keydef.test.lua [work_dir]

set -exu

TESTDIR="$(dirname "$0")"

if [ -z "${2:-}" ]; then
    WORKDIR="${TESTDIR}/var"
else
    WORKDIR="${2}"
fi

mkdir -p "${WORKDIR}"
cd "${WORKDIR}"
rm -f *.xlog *.snap
tarantool "${TESTDIR}/${1}"
