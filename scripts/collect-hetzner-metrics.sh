#!/bin/bash
# Collects Hetzner VPS metrics and pushes to Supabase
set -euo pipefail

# CPU usage from /proc/stat (2 samples, 1 sec apart)
read_cpu() {
  awk '/^cpu / {print $2+$3+$4+$5+$6+$7+$8, $5}' /proc/stat
}
CPU1=$(cat /proc/stat | awk '/^cpu / {print $2+$3+$4+$5+$6+$7+$8, $5}')
sleep 1
CPU2=$(cat /proc/stat | awk '/^cpu / {print $2+$3+$4+$5+$6+$7+$8, $5}')
TOTAL1=$(echo "$CPU1" | awk '{print $1}')
IDLE1=$(echo "$CPU1" | awk '{print $2}')
TOTAL2=$(echo "$CPU2" | awk '{print $1}')
IDLE2=$(echo "$CPU2" | awk '{print $2}')
CPU_PCT=$(echo "scale=0; (1 - ($IDLE2 - $IDLE1) / ($TOTAL2 - $TOTAL1)) * 100" | bc 2>/dev/null || echo 0)

# RAM
RAM_USED=$(free -h | grep Mem | awk '{print $3}')
RAM_TOTAL=$(free -h | grep Mem | awk '{print $2}')
RAM_PCT=$(free | grep Mem | awk '{printf "%d", $3/$2*100}')

# Disk
DISK_LINE=$(df -h / | tail -1)
DISK_USED=$(echo "$DISK_LINE" | awk '{print $3}')
DISK_TOTAL=$(echo "$DISK_LINE" | awk '{print $2}')
DISK_PCT=$(echo "$DISK_LINE" | awk '{print $5}' | tr -d '%')

# Uptime + Load
UPTIME=$(uptime -p 2>/dev/null | sed 's/up //' || echo "unknown")
LOAD=$(cat /proc/loadavg | awk '{print $1, $2, $3}')

# Docker containers (via mounted socket, exclude self)
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
    \"metrics\": {\"cpuPercent\": ${CPU_PCT:-0}, \"ramPercent\": ${RAM_PCT:-0}, \"ramUsed\": \"${RAM_USED}\", \"ramTotal\": \"${RAM_TOTAL}\", \"diskPercent\": ${DISK_PCT:-0}, \"diskUsed\": \"${DISK_USED}\", \"diskTotal\": \"${DISK_TOTAL}\", \"uptime\": \"${UPTIME}\", \"loadAvg\": \"${LOAD}\"},
    \"services\": ${SERVICES},
    \"status\": \"online\",
    \"checked_at\": \"${NOW}\"
  }]")

echo "$(date): Hetzner metrics pushed (HTTP ${HTTP_CODE})"
