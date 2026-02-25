# Cron Hub

Centralized cron jobs container deployed via Coolify on Hetzner Power.

## Jobs

| Schedule | Script | Description |
|----------|--------|-------------|
| `*/2 * * * *` | `collect-hetzner-metrics.sh` | Push Hetzner VPS metrics to Supabase |
| `0 4 * * *` | `cleanup-old-metrics.sh` | Delete metrics older than 7 days |

## Environment Variables

- `SUPABASE_URL` — Supabase project URL
- `SUPABASE_SERVICE_ROLE_KEY` — Service role key for DB writes

## Volumes

- `/var/run/docker.sock` (read-only) — For listing Docker containers
- `/proc` (read-only) — For host CPU metrics

## Adding new crons

1. Add script to `scripts/`
2. Add schedule to `crontab`
3. Push to GitHub → Coolify auto-deploys
