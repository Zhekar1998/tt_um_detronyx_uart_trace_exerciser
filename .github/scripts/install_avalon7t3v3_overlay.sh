#!/usr/bin/env bash
set -euo pipefail

scl="gf180mcu_as_sc_mcu7t3v3"
avalon_repo="${AVALON_SCL_REPO:-https://github.com/AvalonSemiconductors/gf180mcu_as_sc_mcu7t3v3.git}"
avalon_ref="${AVALON_SCL_REF:-c4648471c023690478e97c998edb6f2eac673298}"
work_dir="${RUNNER_TEMP:-/tmp}/gf180mcu_as_sc_mcu7t3v3"

: "${PDK_ROOT:?PDK_ROOT must be set}"
: "${PDK:?PDK must be set}"

if [[ "$PDK" != "gf180mcuD" ]]; then
  echo "ERROR: Avalon overlay is only expected with PDK=gf180mcuD, got PDK=$PDK" >&2
  exit 2
fi

pdk_dir="$PDK_ROOT/$PDK"
src_pdk="$work_dir/pdk"

rm -rf "$work_dir"
git -c init.defaultBranch=main init "$work_dir"
git -C "$work_dir" remote add origin "$avalon_repo"
git -C "$work_dir" fetch --depth=1 origin "$avalon_ref"
git -C "$work_dir" checkout --detach FETCH_HEAD

if [[ ! -d "$src_pdk/libs.ref/$scl" ]]; then
  echo "ERROR: Avalon SCL checkout does not contain $src_pdk/libs.ref/$scl" >&2
  exit 2
fi

if [[ ! -d "$pdk_dir/libs.ref" || ! -d "$pdk_dir/libs.tech" ]]; then
  echo "ERROR: GF180 PDK is not enabled at $pdk_dir" >&2
  echo "Run ciel enable before installing the Avalon overlay." >&2
  exit 2
fi

rm -rf "$pdk_dir/libs.ref/$scl"
cp -a "$src_pdk/libs.ref/$scl" "$pdk_dir/libs.ref/"

if [[ -d "$src_pdk/libs.tech/librelane/$scl" ]]; then
  mkdir -p "$pdk_dir/libs.tech/librelane"
  rm -rf "$pdk_dir/libs.tech/librelane/$scl"
  cp -a "$src_pdk/libs.tech/librelane/$scl" "$pdk_dir/libs.tech/librelane/"
fi

if [[ -d "$src_pdk/libs.tech/openlane/$scl" ]]; then
  mkdir -p "$pdk_dir/libs.tech/openlane"
  rm -rf "$pdk_dir/libs.tech/openlane/$scl"
  cp -a "$src_pdk/libs.tech/openlane/$scl" "$pdk_dir/libs.tech/openlane/"
fi

if [[ -f "$src_pdk/libs.tech/magic/gf180mcuD.magicrc" ]]; then
  mkdir -p "$pdk_dir/libs.tech/magic"
  cp -a "$src_pdk/libs.tech/magic/gf180mcuD.magicrc" \
    "$pdk_dir/libs.tech/magic/${scl}.magicrc"
fi

if [[ -d "$src_pdk/libs.tech/xschem" ]]; then
  mkdir -p "$pdk_dir/libs.tech/xschem/$scl"
  cp -a "$src_pdk/libs.tech/xschem/." "$pdk_dir/libs.tech/xschem/$scl/"
fi

test -f "$pdk_dir/libs.ref/$scl/techlef/${scl}__nom.tlef"
test -f "$pdk_dir/libs.ref/$scl/lib/${scl}__tt_025C_3v30.lib"
test -f "$pdk_dir/libs.tech/librelane/$scl/config.tcl"

echo "Installed Avalon $scl overlay into $pdk_dir"
