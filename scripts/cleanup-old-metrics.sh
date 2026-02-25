#!/bin/bash
# Keep only 7 days of server_metrics
CUTOFF=$(date -u -d "7 days ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-7d +%Y-%m-%dT%H:%M:%SZ)
curl -s -X DELETE "${SUPABASE_URL}/rest/v1/server_metrics?checked_at=lt.${CUTOFF}" \
  -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" > /dev/null 2>&1
echo "$(date): Cleaned up metrics older than 7 days"
