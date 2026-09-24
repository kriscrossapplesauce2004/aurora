#!/system/bin/sh
# Magisk owns this entrypoint; all runtime work lives in the native CLI.
AURORA=/data/aurora
mkdir -p "$AURORA/log"
exec "$AURORA/bin/aurora" internal boot-service >>"$AURORA/log/service.log" 2>&1
