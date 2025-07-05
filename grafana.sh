#!/bin/bash

# Warna untuk output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo -e "${GREEN}Memulai instalasi monitoring system...${NC}"

# Update sistem
sudo apt update -y && sudo apt upgrade -y

# ========== INSTAL PROMETHEUS ==========
echo -e "\n${GREEN}[1/3] Menginstal Prometheus...${NC}"
wget https://github.com/prometheus/prometheus/releases/download/v2.51.0/prometheus-2.51.0.linux-amd64.tar.gz
tar xvfz prometheus-*.tar.gz
cd prometheus-2.51.0.linux-amd64

# Buat konfigurasi khusus untuk monitoring cache
sudo tee prometheus.yml <<EOF
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'node'
    static_configs:
    - targets: ['localhost:9100']
    
  - job_name: 'cache_metrics'
    metrics_path: '/metrics'
    static_configs:
    - targets: ['localhost:9100']
    metric_relabel_configs:
    - source_labels: [__name__]
      regex: '(node_memory_Cached_bytes|node_vmstat_pgmajfault)'
      action: keep
EOF

# Setup service
sudo mv prometheus promtool /usr/local/bin/
sudo mkdir /etc/prometheus
sudo mv prometheus.yml /etc/prometheus/
sudo useradd --no-create-home --system prometheus
sudo chown -R prometheus:prometheus /etc/prometheus

sudo tee /etc/systemd/system/prometheus.service <<EOF
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
ExecStart=/usr/local/bin/prometheus \\
  --config.file=/etc/prometheus/prometheus.yml \\
  --storage.tsdb.path=/var/lib/prometheus \\
  --web.listen-address=0.0.0.0:9090

[Install]
WantedBy=multi-user.target
EOF

# ========== INSTAL NODE EXPORTER ==========
echo -e "\n${GREEN}[2/3] Menginstal Node Exporter...${NC}"
wget https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz
tar xvfz node_exporter-*.tar.gz
sudo mv node_exporter-1.7.0.linux-amd64/node_exporter /usr/local/bin/
sudo useradd --no-create-home --system node_exporter

sudo tee /etc/systemd/system/node_exporter.service <<EOF
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
ExecStart=/usr/local/bin/node_exporter \\
  --collector.filesystem \\
  --collector.meminfo \\
  --collector.vmstat

[Install]
WantedBy=multi-user.target
EOF

# ========== INSTAL GRAFANA ==========
echo -e "\n${GREEN}[3/3] Menginstal Grafana...${NC}"
sudo apt install -y apt-transport-https software-properties-common
wget -q -O - https://packages.grafana.com/gpg.key | sudo apt-key add -
echo "deb https://packages.grafana.com/oss/deb stable main" | sudo tee /etc/apt/sources.list.d/grafana.list
sudo apt update && sudo apt install -y grafana

# ========== START SERVICES ==========
sudo systemctl daemon-reload
sudo systemctl enable prometheus node_exporter grafana-server
sudo systemctl start prometheus node_exporter grafana-server

# ========== IMPORT DASHBOARD ==========
echo -e "\n${GREEN}Mengimpor Dashboard Cache Monitoring...${NC}"
sleep 30 # Tunggu Grafana siap

# Buat API key (Grafana 9+)
GRAFANA_API_KEY=$(sudo grafana-cli admin reset-admin-password newpass123 | grep "API key" | cut -d' ' -f4)

curl -X POST -H "Content-Type: application/json" -H "Authorization: Bearer $GRAFANA_API_KEY" \
-d '{
  "name":"Prometheus",
  "type":"prometheus",
  "url":"http://localhost:9090",
  "access":"proxy"
}' http://localhost:3000/api/datasources

# Import dashboard 1860 (Node Exporter Full)
curl -X POST -H "Content-Type: application/json" -H "Authorization: Bearer $GRAFANA_API_KEY" \
-d '{
  "dashboard": {
    "id":1860,
    "title":"Node Exporter Full (Custom Cache Metrics)",
    "panels": [
      {
        "title": "Memory Cache Size",
        "targets": [{
          "expr": "node_memory_Cached_bytes",
          "legendFormat": "Cache Size"
        }],
        "type": "graph"
      },
      {
        "title": "Disk Cache Hit Rate",
        "targets": [{
          "expr": "rate(node_vmstat_pgmajfault[5m])",
          "legendFormat": "Major Page Faults (Cache Miss)"
        }],
        "type": "graph"
      }
    ]
  }
}' http://localhost:3000/api/dashboards/import

# ========== FINISH ==========
echo -e "\n${GREEN}Instalasi selesai!${NC}"
echo -e "Akses monitoring:"
echo -e "- Prometheus: ${GREEN}http://$(hostname -I | awk '{print $1}'):9090${NC}"
echo -e "- Grafana:    ${GREEN}http://$(hostname -I | awk '{print $1}'):3000${NC} (admin/newpass123)"
echo -e "\nMetric penting yang sudah termasuk:"
echo -e "- Memory Cache: node_memory_Cached_bytes"
echo -e "- Disk Cache Hit: rate(node_vmstat_pgmajfault[5m])"