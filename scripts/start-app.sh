#!/usr/bin/env bash
# Compat wrapper — prefer ./scripts/agy-app
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/agy-app" "$@"
