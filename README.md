# Deployment Lab

> Kubernetes · Go · Docker · GitHub Actions · Prometheus · Grafana · k6

## โครงสร้างโฟลเดอร์

```text
deployment/
├── .github/
│   └── workflows/
│       └── ci-cd.yml           # GitHub Actions CI/CD pipeline
├── api/
│   ├── main.go                 # Go (Gin) API พร้อม health probes + metrics
│   ├── go.mod
│   ├── Dockerfile              # Multi-stage build
│   └── .dockerignore
├── k8s/
│   ├── postgres-db.yaml        # PostgreSQL Deployment + Service + Secret
│   ├── api-deployment.yaml     # Go API Deployment + Service + HPA
│   ├── prometheus.yaml         # Prometheus + RBAC + ConfigMap
│   └── grafana.yaml            # Grafana + Datasource provisioning
├── tests/
│   ├── k6/
│   │   └── script.js           # k6 load test script
│   └── hurl/
│       └── api.hurl            # Hurl functional test
├── TROUBLESHOOTING.md          # Common errors & quick fixes
└── README.md                   # คู่มือนี้
```

---

## เครื่องมือที่ใช้ในการทำ Lab – Google Cloud Shell

> Lab นี้ใช้ **Google Cloud Shell** เป็น Environment หลัก ไม่ต้องติดตั้งอะไรบนเครื่องตัวเอง

### วิธีเข้าใช้ Google Cloud Shell

1. เปิดเบราว์เซอร์แล้วไปที่ [https://ssh.cloud.google.com](https://ssh.cloud.google.com)
2. Login ด้วย Google Account (ต้องเปิดใช้ Google Cloud Project ไว้ก่อน)
3. รอจนหน้าจอ Terminal พร้อมใช้งาน (ประมาณ 10-30 วินาที)

### ตรวจสอบ Tools ที่มีใน Cloud Shell

```bash
docker --version
kubectl version --client
go version
git --version
```

> **หมายเหตุ:** Minikube และ k6 ต้องติดตั้งเพิ่มใน Cloud Shell ตามขั้นตอน Pre-requisites ด้านล่าง

### ติดตั้ง Minikube บน Cloud Shell

```bash
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
minikube version
```

### ติดตั้ง k6 บน Cloud Shell

```bash
sudo gpg -k
sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg \
  --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" \
  | sudo tee /etc/apt/sources.list.d/k6.list
sudo apt-get update && sudo apt-get install k6
```

### ติดตั้ง Hurl บน Cloud Shell

```bash
curl -LO https://github.com/Orange-OpenSource/hurl/releases/latest/download/hurl_amd64.deb
sudo dpkg -i hurl_amd64.deb
hurl --version
```

---

## ก่อนเริ่ม Lab – Pre-requisites

| เครื่องมือ | ติดตั้ง |
|-----------|---------|
| Docker | [docs.docker.com/get-docker](https://docs.docker.com/get-docker/) |
| Minikube | `curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 && sudo install minikube-linux-amd64 /usr/local/bin/minikube` |
| kubectl | `curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && sudo install kubectl /usr/local/bin/kubectl` |
| Go 1.22+ | `sudo apt install golang-go` หรือ [go.dev/dl](https://go.dev/dl/) |
| k6 | `sudo apt install k6` หรือ [k6.io/docs/get-started/installation](https://k6.io/docs/get-started/installation/) |
| Hurl | `curl -LO https://github.com/Orange-OpenSource/hurl/releases/latest/download/hurl-x86_64-unknown-linux-gnu.tar.gz` |

---

## Phase 1 – Environment Setup (15-20 นาที)

### 1.1 Fork & Clone Template Repo

```bash
# Fork repo นี้บน GitHub แล้ว clone ลงเครื่อง
git clone https://github.com/<YOUR_USERNAME>/deployment.git
cd deployment
```

### 1.2 เริ่ม Minikube

```bash
minikube start --driver=docker --cpus=4 --memory=4096
```

ผลลัพธ์ที่คาดหวัง: `Done! kubectl is now configured to use "minikube" cluster`

### 1.3 ตรวจ Node

```bash
kubectl get nodes
# NAME       STATUS   ROLES           AGE   VERSION
# minikube   Ready    control-plane   30s   v1.xx.x
```

### 1.4 เปิด Kubernetes Dashboard (ทางเลือก)

```bash
minikube dashboard &
# กด Web Preview → Preview on Port 41655 (port จะเปลี่ยนไปตาม minikube)
```

---

## Phase 2 – Database & Networking (20 นาที)

### 2.1 Deploy PostgreSQL

```bash
kubectl apply -f k8s/postgres-db.yaml
```

### 2.2 ตรวจสอบ Pod และ Service

```bash
kubectl get pods -w          # รอจนสถานะเป็น Running
kubectl get svc db-service   # ดูว่า ClusterIP และ Port 5432 ถูกต้อง
```

> **แนวคิดสำคัญ:** App เรียกหา `db-service` แทน IP Address  
> เพราะ K8s DNS resolve ชื่อ Service → ClusterIP ให้อัตโนมัติ  
> IP อาจเปลี่ยนทุกครั้งที่ Pod restart แต่ชื่อ Service คงที่เสมอ

### 2.3 ทดสอบต่อ Database

```bash
kubectl exec -it deploy/postgres -- psql -U postgres -d appdb -c "\dt"
# ถ้าเห็น table "items" แสดงว่า init script ทำงานสำเร็จ
```

---

## Phase 3 – The Reliable Go API (30 นาที)

### 3.1 ทำความเข้าใจ Code หลัก 3 ส่วน

เปิดไฟล์ `api/main.go` แล้วดู:

| ส่วน | บรรทัด | คำอธิบาย |
|------|--------|----------|
| **Health Probes** | `healthLive()`, `healthReady()` | `/livez` = container ยังมีชีวิต, `/readyz` = พร้อมรับ Traffic |
| **Graceful Shutdown** | `signal.Notify(quit, syscall.SIGTERM)` | ดักจับสัญญาณ SIGTERM จาก K8s แล้ว drain connection ก่อน exit |
| **Prometheus Metrics** | `prometheusMiddleware()` | นับ request count และ duration ทุก endpoint |

### 3.2 Build Docker Image

```bash
cd api

# Download dependencies ก่อน (สร้าง go.sum)
go mod tidy

cd ..

# Build image (multi-stage)
docker build -t <DOCKER_USERNAME>/go-api:latest ./api

# ดูขนาด image (ควรเล็กมากเพราะ scratch base)
docker images | grep go-api
```

### 3.3 ทดสอบ Local ก่อน Push

```bash
# รัน container พร้อม env vars
docker run --rm -p 8080:8080 \
  -e DB_HOST=host.docker.internal \
  <DOCKER_USERNAME>/go-api:latest &

# ทดสอบ endpoint
curl http://localhost:8080/livez
curl http://localhost:8080/readyz
curl http://localhost:8080/

# หยุด container
docker stop $(docker ps -q --filter ancestor=<DOCKER_USERNAME>/go-api:latest)
```

### 3.4 Push Image ขึ้น Docker Hub

```bash
docker login
docker push <DOCKER_USERNAME>/go-api:latest
```

### 3.5 อัปเดต image name ใน k8s/api-deployment.yaml

```bash
# แทนที่ DOCKER_USERNAME ด้วยชื่อจริง
sed -i "s/DOCKER_USERNAME/<YOUR_DOCKERHUB_USERNAME>/g" k8s/api-deployment.yaml
```

### 3.6 Deploy Go API

```bash
kubectl apply -f k8s/api-deployment.yaml
kubectl get pods -w   # รอจนสถานะ Running
```

### 3.7 ทดสอบ API ผ่าน Minikube

```bash
NODE_IP=$(minikube ip)
curl http://${NODE_IP}:30080/
curl http://${NODE_IP}:30080/livez
curl http://${NODE_IP}:30080/readyz
```

---

## Phase 4 – CI/CD Automation (40 นาที)

### 4.1 ตั้งค่า GitHub Secrets

ไปที่ GitHub repo → **Settings → Secrets and variables → Actions** → New repository secret

| Secret Name | Value |
|-------------|-------|
| `DOCKER_USERNAME` | Docker Hub username |
| `DOCKER_TOKEN` | Docker Hub Access Token ([สร้างที่นี่](https://hub.docker.com/settings/security)) |

### 4.2 ติดตั้ง Self-hosted Runner บน Cloud Shell

```bash
# ไปที่ GitHub repo → Settings → Actions → Runners → New self-hosted runner
# เลือก OS: Linux, Architecture: x64 แล้วทำตามคำสั่งที่หน้าจอแสดง

mkdir -p ~/actions-runner && cd ~/actions-runner
curl -o actions-runner-linux-x64-2.316.1.tar.gz -L \
  https://github.com/actions/runner/releases/download/v2.316.1/actions-runner-linux-x64-2.316.1.tar.gz
tar xzf ./actions-runner-linux-x64-2.316.1.tar.gz

# Config (ใช้ token จากหน้า GitHub)
./config.sh --url https://github.com/<YOUR_USERNAME>/deployment --token <TOKEN>

# Start runner (ใช้ tmux ให้ทำงาน background)
tmux new -s runner
./run.sh
# กด Ctrl+B แล้ว D เพื่อ detach
```

### 4.3 The Magic Moment – Test CI/CD

```bash
cd ~/deployment

# แก้ไข welcome message ใน api/main.go
# บรรทัด: "message": "Hello from Go API v1.0.0 🚀"
# เปลี่ยนเป็น: "message": "Hello from Go API v2.0.0 ✨"

git add api/main.go
git commit -m "feat: update welcome message to v2.0.0"
git push origin main
```

ไปดู GitHub Actions → จะเห็น Pipeline รัน Build → Push → Deploy อัตโนมัติ!

```bash
# ตรวจสอบว่า Pod อัปเดตแล้ว
kubectl rollout status deployment/go-api
curl http://$(minikube ip):30080/
```

---

## Phase 5 – Load Test & Monitoring (30 นาที)

### 5.1 Deploy Prometheus & Grafana

```bash
kubectl apply -f k8s/prometheus.yaml
kubectl apply -f k8s/grafana.yaml
kubectl get pods -w   # รอทั้ง 2 ตัว Running
```

### 5.2 เข้า Grafana ผ่าน Port-forward

```bash
kubectl port-forward svc/grafana-service 3000:3000 &
# เปิด http://localhost:3000
# Login: admin / admin123
```

**ตั้งค่า Dashboard:**
1. **Connections → Data Sources** → ตรวจว่า Prometheus URL = `http://prometheus-service:9090`
2. **Dashboards → New → Import** → ใส่ ID `12708` (Go Metrics Dashboard) หรือ `1860` (Node Exporter)
3. เพิ่ม Panel เอง:
   - Query: `rate(http_requests_total[1m])` → ดู Request per second
   - Query: `histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[1m]))` → ดู P95 latency

### 5.3 รัน k6 Load Test

```bash
# เปิด terminal ใหม่
BASE_URL=http://$(minikube ip):30080 k6 run \
  -e BASE_URL=http://$(minikube ip):30080 \
  tests/k6/script.js
```

### 5.4 สังเกต Grafana

ดูกราฟใน Grafana ขณะที่ k6 ยิง:
- **Request rate** จะพุ่งสูง
- **CPU usage** ของ Pod จะเพิ่มขึ้น
- **P95 latency** จะเปลี่ยนแปลงตาม load

### 5.5 ทดสอบ Functional ด้วย Hurl

```bash
hurl --variable base_url=http://$(minikube ip):30080 \
  tests/hurl/api.hurl --verbose
```

---

## Phase 6 – Scaling & Troubleshooting (20 นาที)

### 6.1 Manual Scaling

เมื่อเห็น CPU พุ่งใน Grafana:

```bash
kubectl scale deployment go-api --replicas=5
kubectl get pods -w   # ดู Pod ใหม่ถูกสร้าง
```

### 6.2 ตรวจสอบการกระจาย Load ใน Grafana

เพิ่ม Panel ใน Grafana ด้วย Query:
```promql
rate(http_requests_total[30s])
```
จะเห็นว่าแต่ละ Pod (label `pod`) รับ request คนละก้อน

### 6.3 Log Analysis

```bash
# ดู log แบบ real-time ระหว่างที่ k6 ยิง
kubectl logs -f deployment/go-api

# ดู log ของ Pod ที่ระบุ
kubectl logs -f <pod-name>

# ดู log หลาย Pod พร้อมกัน (ต้องติดตั้ง stern)
stern go-api
```

### 6.4 Scale Down

```bash
kubectl scale deployment go-api --replicas=2
```

---

## สรุปสิ่งที่เรียนรู้

| หัวข้อ | สิ่งที่ทำ |
|--------|---------|
| **Reliability** | Health probes (`/livez`, `/readyz`) + Graceful shutdown |
| **Observability** | Prometheus metrics + Grafana dashboard |
| **Automation** | GitHub Actions + Self-hosted Runner |
| **Scalability** | Manual scaling + HPA (auto-scale) |
| **Testing** | Load test (k6) + Functional test (Hurl) |

---

## ถ้าติดปัญหา

ดู [TROUBLESHOOTING.md](TROUBLESHOOTING.md) สำหรับ error ที่พบบ่อยและวิธีแก้ไข
