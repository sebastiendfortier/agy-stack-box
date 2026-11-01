#!/usr/bin/env bash
# Compat wrapper — prefer ./scripts/agy-cli
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/agy-cli" "$@"
