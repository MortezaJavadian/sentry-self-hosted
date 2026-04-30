# Sentry Self-Hosted

Automated setup for Sentry on Docker with custom network integration.

## About Sentry

Sentry is an error tracking and performance monitoring platform. It captures exceptions, crashes, and performance issues from applications in real-time. Features include:

- **Error Tracking**: Detect and debug issues automatically
- **Performance Monitoring**: Track slow transactions and bottlenecks
- **Release Tracking**: Monitor deployments and rollouts
- **Alerts**: Get notified when errors spike
- **Source Maps**: Debug minified production code

Self-hosted deployment keeps your error data on your own infrastructure.

## Requirements

- Docker 19.03.6+
- Docker Compose 2.32.2+
- 4+ CPU cores, 16GB+ RAM
- 50GB+ disk space

## Quick Start

### Step 1: Run Setup

```bash
./setup.sh
```

Enter your configuration:

- Domain name
- Event retention (days)
- Mail hostname
- Docker network name

### Step 2: Install

```bash
cd self-hosted
./install.sh
```

Creates database, builds images, and sets up admin user.

### Step 3: Start Services

```bash
docker compose --env-file .env --env-file .env.custom up -d
```

Wait 30-60 seconds for containers.

### Step 4: Configure Nginx

```bash
cp ../nginx-sentry.conf /root/nginx-proxy/conf.d/sentry.conf
cd /root/nginx-proxy
docker compose exec nginx nginx -s reload
```

### Step 5: Verify

```bash
curl https://your-domain/_health/
```

Should return HTTP 200.

### Step 6: Access

Open `https://your-domain` in browser.
Login with credentials from step 2.

## Configuration

Setup creates:

- `self-hosted/` - Official Sentry repo
- `.env.custom` - Environment variables
- `docker-compose.override.yml` - Network config
- `sentry/config.yml` - Domain & mail settings
- `nginx-sentry.conf` - Reverse proxy config

## Troubleshooting

**Check logs:**

```bash
cd self-hosted
docker compose logs -f web
```

## After Setup

1. Create projects in Sentry panel
2. Get DSN from project settings
3. Add SDK to your applications

See [Sentry Docs](https://docs.sentry.io/) for SDK setup.
