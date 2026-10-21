#!/bin/bash
# Re-install the patched d2d1.dll (the launcher also does this automatically).
exec bash "$(dirname "$0")/04-apply-d2d1-patch.sh" "$@"
