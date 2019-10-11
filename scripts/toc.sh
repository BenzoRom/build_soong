#!/bin/bash -eu

# Copyright 2017 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Script to handle generating a .toc file from a .so file
# Inputs:
#  Environment:
#   CLANG_BIN: path to the clang bin directory
#  Arguments:
#   -i ${file}: input file (required)
#   -o ${file}: output file (required)
#   -d ${file}: deps file (required)
#   --elf | --macho | --pe: format (required)

OPTSTRING=d:i:o:-:

usage() {
    cat <<EOF
Usage: toc.sh [options] -i in-file -o out-file -d deps-file
Options:
EOF
    exit 1
}

do_elf() {
    ("${CLANG_BIN}/llvm-readelf" -d "${infile}" | grep SONAME || echo "No SONAME for ${infile}") > "${outfile}.tmp"
    "${CLANG_BIN}/llvm-readelf" --dyn-symbols "${infile}" | awk '{$2=""; $3=""; print}' >> "${outfile}.tmp"

    cat <<EOF > "${depsfile}"
${outfile}: \\
  ${CLANG_BIN}/llvm-readelf \\
EOF
}

do_macho() {
    "${CLANG_BIN}/llvm-objdump" -x "${infile}" | grep LC_ID_DYLIB -A 5 > "${outfile}.tmp"
    "${CLANG_BIN}/llvm-nm" --extern-only --format=posix "${infile}" | cut -f1-2 -d" " | (grep -v 'U$' >> "${outfile}.tmp" || true)

    cat <<EOF > "${depsfile}"
${outfile}: \\
  ${CLANG_BIN}/llvm-objdump \\
  ${CLANG_BIN}/llvm-nm \\
EOF
}

do_pe() {
    "${CLANG_BIN}/llvm-objdump" -x "${infile}" | grep "^Name" | cut -f3 -d" " > "${outfile}.tmp"
    "${CLANG_BIN}/llvm-nm" --extern-only --format=posix "${infile}" | cut -f1-2 -d" " >> "${outfile}.tmp"

    cat <<EOF > "${depsfile}"
${outfile}: \\
  ${CLANG_BIN}/llvm-objdump \\
  ${CLANG_BIN}/llvm-nm \\
EOF
}

while getopts $OPTSTRING opt; do
    case "$opt" in
        d) depsfile="${OPTARG}" ;;
        i) infile="${OPTARG}" ;;
        o) outfile="${OPTARG}" ;;
        -)
            case "${OPTARG}" in
                elf) elf=1 ;;
                macho) macho=1 ;;
                pe) pe=1 ;;
                *) echo "Unknown option --${OPTARG}"; usage ;;
            esac;;
        ?) usage ;;
        *) echo "'${opt}' '${OPTARG}'"
    esac
done

if [ -z "${infile:-}" ]; then
    echo "-i argument is required"
    usage
fi

if [ -z "${outfile:-}" ]; then
    echo "-o argument is required"
    usage
fi

if [ -z "${depsfile:-}" ]; then
    echo "-d argument is required"
    usage
fi

if [ -z "${CLANG_BIN:-}" ]; then
    echo "CLANG_BIN environment variable must be set"
    usage
fi

rm -f "${outfile}.tmp"

cat <<EOF > "${depsfile}"
${outfile}: \\
  ${CLANG_BIN}/llvm-readelf \\
EOF

if [ -n "${elf:-}" ]; then
    do_elf
elif [ -n "${macho:-}" ]; then
    do_macho
elif [ -n "${pe:-}" ]; then
    do_pe
else
    echo "--elf, --macho or --pe is required"; usage
fi

if cmp "${outfile}" "${outfile}.tmp" > /dev/null 2> /dev/null; then
    rm -f "${outfile}.tmp"
else
    mv -f "${outfile}.tmp" "${outfile}"
fi
