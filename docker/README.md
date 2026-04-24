# Docker Compose Setup

Guide for running the stack with `docker-compose` or `podman-compose`.

Stack includes:

- **PostgreSQL 16** — database
- **Go API** — REST API (port 8080)
- **Prometheus** — metrics collection (port 9090)
- **Grafana** — dashboard (port 3000)
- **Node Exporter** — host metrics (port 9100)

---

## Prerequisites

Choose one — **Docker** or **Podman**.

---

## Installation

### Docker + Docker Compose

#### macOS

```bash
# Option 1 — Install via Homebrew (recommended)
brew install --cask docker

# Open Docker Desktop and wait for the engine to start
open /Applications/Docker.app
```

> Option 2 — Download the installer from <https://docs.docker.com/desktop/install/mac-install/>

Verify:

```bash
docker --version
docker compose version
```

---

#### Windows

1. Enable WSL 2 first (open PowerShell as Administrator):

   ```powershell
   wsl --install
   ```

2. Restart your machine.
3. Download and install **Docker Desktop** from <https://docs.docker.com/desktop/install/windows-install/>
4. During installation, select **Use WSL 2 instead of Hyper-V**.

Verify (in PowerShell or Windows Terminal):

```powershell
docker --version
docker compose version
```

---

#### Linux (Ubuntu)

```bash
# 1. Remove old packages (if any)
sudo apt remove docker docker-engine docker.io containerd runc

# 2. Install dependencies
sudo apt update
sudo apt install -y ca-certificates curl gnupg

# 3. Add Docker GPG key and repo
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 4. Install Docker Engine + Compose plugin
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# 5. Allow current user to run docker without sudo
sudo usermod -aG docker $USER
newgrp docker
```

Verify:

```bash
docker --version
docker compose version
```

---

### Podman + podman-compose

#### macOS (podman-compose)

```bash
brew install podman podman-compose
```

Verify:

```bash
podman --version
podman-compose --version
```

---

#### Windows (podman-compose)

1. Download **Podman Desktop** from <https://podman-desktop.io/>
2. Follow the installation steps (WSL 2 required).
3. Install podman-compose via pip:

   ```powershell
   pip install podman-compose
   ```

Verify (in PowerShell or Windows Terminal):

```powershell
podman --version
podman-compose --version
```

---

#### Linux (Ubuntu) (podman-compose)

```bash
# 1. Install Podman
sudo apt update
sudo apt install -y podman

# 2. Install podman-compose
sudo apt install -y python3-pip
pip3 install podman-compose
```

Verify:

```bash
podman --version
podman-compose --version
```

---

## Running with docker-compose

### Step 1 — Navigate to the project root

```bash
cd /path/to/deployment
```

### Step 2 — Build images and start services

```bash
docker compose up -d --build
```

### Step 3 — Check container status

```bash
docker compose ps
```

### Step 4 — View logs (optional)

```bash
# All services
docker compose logs -f

# API only
docker compose logs -f api
```

### Step 5 — Stop services

```bash
docker compose down
```

> To also remove volumes (PostgreSQL data), add `-v`:

```bash
docker compose down -v
```

---

## Running with podman-compose

### Step 1 — Start Podman machine (macOS/Windows only)

```bash
podman machine init   # first time only
podman machine start
```

### Step 2 — Navigate to the project root

```bash
cd /path/to/deployment
```

### Step 3 — Build images and start services

```bash
podman-compose up -d --build
```

### Step 4 — Check container status

```bash
podman-compose ps
```

### Step 5 — View logs (optional)

```bash
# All services
podman-compose logs -f

# API only
podman-compose logs -f api
```

### Step 6 — Stop services

```bash
podman-compose down
```

> To also remove volumes:

```bash
podman-compose down -v
```

---

## Service URLs

| Service | URL | Credentials |
| ------- | --- | ----------- |
| Go API | <http://localhost:8080> | — |
| Prometheus | <http://localhost:9090> | — |
| Grafana | <http://localhost:3000> | admin / admin123 |
| Node Exporter | <http://localhost:9100/metrics> | — |
| PostgreSQL | <http://localhost:5432> | postgres / password |

---

## Files in this folder

| File | Description |
| ---- | ----------- |
| `init.sql` | SQL script to initialize the PostgreSQL schema |
| `prometheus.yml` | Prometheus scrape configuration |
| `grafana/datasources.yaml` | Grafana datasource configuration (Prometheus) |
| `grafana/dashboards.yaml` | Grafana dashboard provisioning config |
| `grafana/go-api-metrics.json` | Dashboard for Go API metrics |
| `grafana/node-exporter-full.json` | Dashboard for Node Exporter metrics |

---

## Load Testing with k6

Script location: `tests/k6/script.js`

**Load profile:**

| Stage | Duration | VUs |
| ----- | --------- | --- |
| Ramp-up | 30s | 0 → 10 |
| Load | 1m | 50 |
| Spike | 30s | 50 → 100 |
| Ramp-down | 30s | 100 → 0 |

**Thresholds:**

- 95th percentile latency < 500ms
- Error rate < 1%

---

### Install k6

#### macOS (Homebrew)

```bash
brew install k6
```

#### Windows (winget)

```powershell
winget install k6 --source winget
```

#### Linux (Ubuntu)(apt)

```bash
sudo gpg -k
sudo gpg --no-default-keyring \
  --keyring /usr/share/keyrings/k6-archive-keyring.gpg \
  --keyserver hkp://keyserver.ubuntu.com:80 \
  --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" \
  | sudo tee /etc/apt/sources.list.d/k6.list
sudo apt update
sudo apt install -y k6
```

Verify:

```bash
k6 version
```

---

### Step 1 — Start the stack first

```bash
# docker
docker compose up -d

# or podman
podman-compose up -d
```

### Step 2 — Run the load test

```bash
# Run with default BASE_URL (http://localhost:8080)
k6 run tests/k6/script.js

# Or specify BASE_URL explicitly
k6 run -e BASE_URL=http://localhost:8080 tests/k6/script.js
```

### Step 3 — View results

k6 prints a summary in the terminal when the test finishes, e.g.:

```text
✓ welcome: status 200
✓ readyz: status 200
✓ items: status 200 or 503

checks.........................: 100.00%
http_req_duration..............: avg=45ms   p(95)=120ms
errors.........................: 0.00%
```

### Step 4 (optional) — View real-time metrics in Grafana

Open Grafana at <http://localhost:3000> and watch the **Go API Metrics** dashboard while k6 is running.
