#!/bin/bash

# Script Auto Install Grafana + Prometheus + Node Exporter untuk Monitoring Cache
# Menggunakan systemd untuk service management

GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo -e "${GREEN}Memulai instalasi otomatis...${NC}"

# 1. Update sistem
sudo apt update -y
sudo apt upgrade -y

# 2. Install dependensi
sudo apt install -y wget curl git unzip

# 3. Buat user khusus untuk monitoring
sudo useradd --no-create-home --system --shell /bin/false prometheus
sudo useradd --no-create-home --system --shell /bin/false node_exporter
sudo useradd --no-create-home --system --shell /bin/false grafana

# 4. Install Node Exporter (untuk system metrics)
echo -e "${GREEN}Menginstal Node Exporter...${NC}"
NODE_EXPORTER_VERSION="1.7.0"
wget https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
tar xvfz node_exporter-*.tar.gz
sudo cp node_exporter-*/node_exporter /usr/local/bin/
sudo chown node_exporter:node_exporter /usr/local/bin/node_exporter

# Buat service untuk Node Exporter
sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<EOF
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User =node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter \
  --collector.filesystem \
  --collector.diskstats \
  --collector.meminfo \
  --collector.vmstat \
  --collector.interrupts \
  --collector.netdev \
  --collector.stat

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl start node_exporter
sudo systemctl enable node_exporter

# 5. Install Prometheus
echo -e "${GREEN}Menginstal Prometheus...${NC}"
PROMETHEUS_VERSION="2.51.0"
wget https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz
tar xvfz prometheus-*.tar.gz
sudo mkdir /etc/prometheus
sudo mkdir /var/lib/prometheus
sudo cp prometheus-*/prometheus /usr/local/bin/
sudo cp prometheus-*/promtool /usr/local/bin/
sudo cp -r prometheus-*/consoles /etc/prometheus
sudo cp -r prometheus-*/console_libraries /etc/prometheus

# Buat konfigurasi Prometheus
sudo tee /etc/prometheus/prometheus.yml > /dev/null <<EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'node'
    static_configs:
    - targets: ['localhost:9100']
    metric_relabel_configs:
    - source_labels: [__name__]
      regex: 'node_.*'
      action: keep
EOF

sudo chown -R prometheus:prometheus /etc/prometheus
sudo chown prometheus:prometheus /var/lib/prometheus

# Buat service untuk Prometheus
sudo tee /etc/systemd/system/prometheus.service > /dev/null <<EOF
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User =prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus/ \
  --web.console.templates=/etc/prometheus/consoles \
  --web.console.libraries=/etc/prometheus/console_libraries

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl start prometheus
sudo systemctl enable prometheus

# 6. Install Grafana
echo -e "${GREEN}Menginstal Grafana...${NC}"
wget -q -O - https://packages.grafana.com/gpg.key | sudo apt-key add -
echo "deb https://packages.grafana.com/oss/deb stable main" | sudo tee /etc/apt/sources.list.d/grafana.list
sudo apt update
sudo apt install -y grafana
sudo systemctl start grafana-server
sudo systemctl enable grafana-server

# 7. Install plugin Grafana untuk Prometheus
sudo grafana-cli plugins install grafana-piechart-panel

# 8. Buat dashboard otomatis
DASHBOARD_JSON=$(cat <<EOF
{
  "annotations": {
    "list": [
      {
        "builtIn": 1,
        "datasource": "-- Grafana --",
        "enable": true,
        "hide": true,
        "iconColor": "rgba(0, 211, 255, 1)",
        "name": "Annotations & Alerts",
        "target": {
          "limit": 100,
          "matchAny": false,
          "tags": [],
          "type": "dashboard"
        },
        "type": "dashboard"
      }
    ]
  },
  "editable": true,
  "fiscalYearStartMonth": 0,
  "graphTooltip": 0,
  "links": [],
  "liveNow": false,
  "panels": [
    {
      "datasource": "Prometheus",
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "thresholds"
          },
          "custom": {
            "axisLabel": "",
            "axisPlacement": "auto",
            "barAlignment": 0,
            "drawStyle": "line",
            "fillOpacity": 20,
            "gradientMode": "none",
            "hideFrom": {
              "legend": false,
              "tooltip": false,
              "viz": false
            },
            "lineInterpolation": "linear",
            "lineWidth": 2,
            "pointSize": 5,
            "scaleDistribution": {
              "type": "linear"
            },
            "showPoints": "auto",
            "spanNulls": false,
            "thresholdsStyle": {
              "mode": "off"
            }
          },
          "thresholds": {
            "mode": "absolute",
            "steps": [
              {
                "color": "green",
                "value": null
              },
              {
                "color": "red",
                "value": 80
              }
            ]
          }
        },
        "overrides": []
      },
      "gridPos": {
        "h": 8,
        "w": 12,
        "x": 0,
        "y": 0
      },
      "id": 2,
      "options": {
        "legend": {
          "calcs": [],
          "displayMode": "list",
          "placement": "bottom"
        },
        "tooltip": {
          "mode": "single",
          "sort": "none"
        }
      },
      "targets": [
        {
          "expr": "100 * (1 - ((node_memory_MemFree_bytes + node_memory_Buffers_bytes + node_memory_Cached_bytes) / node_memory_MemTotal_bytes))",
          "legendFormat": "Memory Usage",
          "refId": "A"
        }
      ],
      "title": "Memory Usage",
      "type": "timeseries"
    },
    {
      "datasource": "Prometheus",
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "thresholds"
          },
          "custom": {
            "axisLabel": "",
            "axisPlacement": "auto",
            "barAlignment": 0,
            "drawStyle": "line",
            "fillOpacity": 20,
            "gradientMode": "none",
            "hideFrom": {
              "legend": false,
              "tooltip": false,
              "viz": false
            },
            "lineInterpolation": "linear",
            "lineWidth": 2,
            "pointSize": 5,
            "scaleDistribution": {
              "type": "linear"
            },
            "showPoints": "auto",
            "spanNulls": false,
            "thresholdsStyle": {
              "mode": "off"
            }
          },
          "thresholds": {
            "mode": "absolute",
            "steps": [
              {
                "color": "green",
                "value": null
              },
              {
                "color": "red",
                "value": 80
              }
            ]
          }
        },
        "overrides": []
      },
      "gridPos": {
        "h": 8,
        "w": 12,
        "x": 12,
        "y": 0
      },
      "id": 3,
      "options": {
        "legend": {
          "calcs": [],
          "displayMode": "list",
          "placement": "bottom"
        },
        "tooltip": {
          "mode": "single",
          "sort": "none"
        }
      },
      "targets": [
        {
          "expr": "node_memory_Cached_bytes",
          "legendFormat": "Cache Size",
          "refId": "A"
        }
      ],
      "title": "Memory Cache Size",
      "type": "timeseries"
    }
  ],
  "schemaVersion": 36,
  "style": "dark",
  "tags": [],
  "templating": {
    "list": []
  },
  "time": {
    "from": "now-6h",
    "to": "now"
  },
  "timepicker": {},
  "timezone": "",
  "title": "Cache Monitoring",
  "version": 1,
  "weekStart": ""
}
EOF
)

# Tunggu Grafana siap (30 detik)
echo -e "${GREEN}Menunggu Grafana siap...${NC}"
sleep 30

# Import dashboard
echo -e "${GREEN}Mengimpor dashboard untuk monitoring cache...${NC}"
curl -X POST -H "Content-Type: application/json" -d "{\"dashboard\": $DASHBOARD_JSON, \"overwrite\": true, \"folderId\": 0, \"inputs\": []}" http://admin:admin@localhost:3000/api/dashboards/import

# 9. Konfigurasi firewall (jika diperlukan)
if command -v ufw &> /dev/null; then
    sudo ufw allow 3000/tcp  # Grafana
    sudo ufw allow 9090/tcp  # Prometheus
    sudo ufw allow 9100/tcp  # Node Exporter
    sudo ufw reload
fi

echo -e "${GREEN}Instalasi selesai!${NC}"
echo "Akses monitoring di:"
echo -e "  - Grafana:     ${GREEN}http://$(hostname -I | awk '{print $1}'):3000${NC} (admin/admin)"
echo -e "  - Prometheus:  ${GREEN}http://$(hostname -I | awk '{print $1}'):9090${NC}"
echo -e "  - Node Exporter: ${GREEN}http://$(hostname -I | awk '{print $1}'):9100${NC}"

echo "Untuk mengubah password default Grafana, jalankan:"
echo "  sudo grafana-cli admin reset-admin-password newpassword"