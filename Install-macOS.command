#!/bin/bash
# Double-click in Finder to install cvat-helpers.
cd "$(dirname "$0")" || exit 1
bash scripts/install.sh install
status=$?
echo
read -r -p "Nhan Enter de dong cua so..." _
exit $status
