#!/bin/bash
# Collects Hetzner VPS host metrics and pushes to Supabase
set -euo pipefail

PROC="/host/proc"
[ -d "$PROC" ] || PROC="/proc"

# CPU usage from /proc/stat (2 samples, 1 sec apart)
CPU1=$(awk '/^cpu / {print $2+$3+$4+$5+$6+$7+$8, $5}' "$PROC/stat")
sleep 1
CPU2=$(awk '/^cpu / {print $2+$3+$4+$5+$6+$7+$8, $5}' "$PROC/stat")
TOTAL_D=$(echo "$CPU1 $CPU2" | awk '{print $3+$4-$1-$2}' | head -1)
IDLE_D=$(echo "$CPU1 $CPU2" | awk '{print $4-$2}' | head -1)
# Simpler approach
T1=$(echo "$CPU1" | awk '{print $1}'); I1=$(echo "$CPU1" | awk '{print $2}')
T2=$(echo "$CPU2" | awk '{print $1}'); I2=$(echo "$CPU2" | awk '{print $2}')
CPU_PCT=$(echo "scale=0; (1 - ($I2 - $I1) / ($T2 - $T1)) * 100" | bc 2>/dev/null || echo 1)

# RAM from /proc/meminfo
MEM_TOTAL_KB=$(awk '/^MemTotal:/ {print $2}' "$PROC/meminfo")
MEM_AVAIL_KB=$(awk '/^MemAvailable:/ {print $2}' "$PROC/meminfo")
MEM_USED_KB=$((MEM_TOTAL_KB - MEM_AVAIL_KB))
RAM_PCT=$((MEM_USED_KB * 100 / MEM_TOTAL_KB))
RAM_USED="$(echo "scale=1; $MEM_USED_KB / 1048576" | bc)Gi"
RAM_TOTAL="$(echo "scale=0; $MEM_TOTAL_KB / 1048576" | bc)Gi"

# Disk (from host via docker info or /proc/mounts trick)
# Use df inside container but for host root - works if host / is visible
DISK_USED=$(df -h / 2>/dev/null | tail -1 | awk '{print $3}')
DISK_TOTAL=$(df -h / 2>/dev/null | tail -1 | awk '{print $2}')
DISK_PCT=$(df / 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%')

# Uptime from /proc/uptime
UPTIME_SECS=$(awk '{print int($1)}' "$PROC/uptime")
DAYS=$((UPTIME_SECS / 86400))
HOURS=$(((UPTIME_SECS % 86400) / 3600))
MINS=$(((UPTIME_SECS % 3600) / 60))
UPTIME="${DAYS} days, ${HOURS} hours, ${MINS} minutes"

# Load from /proc/loadavg
LOAD=$(awk '{print $1, $2, $3}' "$PROC/loadavg")

# Docker containers
SERVICES="["
FIRST=true
while IFS= read -r line; do
  [ -z "$line" ] && continue
  CNAME=$(echo "$line" | cut -d'|' -f1)
  CSTATUS=$(echo "$line" | cut -d'|' -f2)
  [ "$FIRST" = true ] && FIRST=false || SERVICES+=","
  SERVICES+="{\"name\":\"${CNAME}\",\"status\":\"${CSTATUS}\"}"
done < <(docker ps --format "{{.Names}}|{{.Status}}" 2>/dev/null | grep -v cron-hub)
SERVICES+="]"

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
  "${SUPABASE_URL}/rest/v1/server_metrics" \
  -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=minimal" \
  -d "[{
    \"name\": \"Hetzner VPS\",
    \"host\": \"46.224.85.85\",
    \"specs\": {\"cores\": 16, \"ramGB\": 30, \"diskGB\": 601, \"os\": \"Ubuntu 22.04\"},
    \"metrics\": {\"cpuPercent\": ${CPU_PCT:-0}, \"ramPercent\": ${RAM_PCT:-0}, \"ramUsed\": \"${RAM_USED}\", \"ramTotal\": \"${RAM_TOTAL}\", \"diskPercent\": ${DISK_PCT:-0}, \"diskUsed\": \"${DISK_USED:-?}\", \"diskTotal\": \"${DISK_TOTAL:-601G}\", \"uptime\": \"${UPTIME}\", \"loadAvg\": \"${LOAD}\"},
    \"services\": ${SERVICES},
    \"status\": \"online\",
    \"checked_at\": \"${NOW}\"
  }]")

echo "$(date): Hetzner metrics pushed (HTTP ${HTTP_CODE})"
