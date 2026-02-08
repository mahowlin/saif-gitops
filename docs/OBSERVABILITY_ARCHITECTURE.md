# Observability Architecture

This document describes the complete observability data flow for the SAIF Platform, including all data sources, collection methods, and destinations.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                    OPENSHIFT CLUSTER                                     │
│                                                                                          │
│  ┌────────────────────────────────────────────────────────────────────────────────────┐ │
│  │                              DATA SOURCES                                           │ │
│  │                                                                                     │ │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐               │ │
│  │  │   CILIUM    │  │  TETRAGON   │  │    DCGM     │  │ KUBERNETES  │               │ │
│  │  │   (CNI)     │  │  (Security) │  │   (GPU)     │  │   (API)     │               │ │
│  │  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘               │ │
│  │         │                │                │                │                       │ │
│  └─────────┼────────────────┼────────────────┼────────────────┼───────────────────────┘ │
│            │                │                │                │                          │
│            ▼                ▼                ▼                ▼                          │
│  ┌─────────────────────────────────────────────────────────────────────────────────────┐│
│  │                              DATA TYPES                                              ││
│  │                                                                                      ││
│  │  ┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐         ││
│  │  │     LOG EVENTS      │  │      METRICS        │  │    K8S EVENTS       │         ││
│  │  │                     │  │                     │  │                     │         ││
│  │  │ • hubble.log        │  │ • cilium_*          │  │ • k8s-events.log    │         ││
│  │  │ • tetragon.log      │  │ • tetragon_*        │  │ • Policy changes    │         ││
│  │  │ • tetragon-         │  │ • hubble_*          │  │ • Identity changes  │         ││
│  │  │   connections.log   │  │ • DCGM_FI_*         │  │                     │         ││
│  │  └──────────┬──────────┘  └──────────┬──────────┘  └──────────┬──────────┘         ││
│  │             │                        │                        │                     ││
│  └─────────────┼────────────────────────┼────────────────────────┼─────────────────────┘│
│                │                        │                        │                       │
│                ▼                        ▼                        ▼                       │
│  ┌─────────────────────────────────────────────────────────────────────────────────────┐│
│  │                              COLLECTORS                                              ││
│  │                                                                                      ││
│  │  ┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐         ││
│  │  │       VECTOR        │  │    SPLUNK OTEL      │  │    K8S-EXPORTER     │         ││
│  │  │    (DaemonSet)      │  │     COLLECTOR       │  │    (Deployment)     │         ││
│  │  │                     │  │                     │  │                     │         ││
│  │  │ Reads:              │  │ Scrapes:            │  │ Watches:            │         ││
│  │  │ • /var/run/cilium/  │  │ • :9962 (Cilium)    │  │ • CiliumIdentity    │         ││
│  │  │   hubble/*.log      │  │ • :9965 (Hubble)    │  │ • NetworkPolicy     │         ││
│  │  │                     │  │ • :2112 (Tetragon)  │  │ • CiliumNetPolicy   │         ││
│  │  │ Sends to:           │  │ • :9400 (DCGM)      │  │                     │         ││
│  │  │ • Push API (HTTP)   │  │                     │  │ Writes to:          │         ││
│  │  │                     │  │ Sends to:           │  │ • k8s-events.log    │         ││
│  │  │                     │  │ • Splunk Cloud      │  │                     │         ││
│  │  └──────────┬──────────┘  └──────────┬──────────┘  └──────────┬──────────┘         ││
│  │             │                        │                        │                     ││
│  └─────────────┼────────────────────────┼────────────────────────┼─────────────────────┘│
│                │                        │                        │                       │
└────────────────┼────────────────────────┼────────────────────────┼───────────────────────┘
                 │                        │                        │
                 ▼                        ▼                        ▼
┌────────────────────────────┐ ┌────────────────────────┐ ┌────────────────────────┐
│    HUBBLE TIMESCAPE        │ │   SPLUNK OBSERVABILITY │ │   (Same as Vector)     │
│                            │ │        CLOUD           │ │                        │
│ • Ingester (Push API)      │ │                        │ │ k8s-events.log is      │
│ • ClickHouse (Storage)     │ │ • Metrics dashboards   │ │ read by Vector and     │
│ • Server (Query API)       │ │ • Alerting             │ │ sent to Timescape      │
│ • UI (Visualization)       │ │ • GPU monitoring       │ │                        │
│                            │ │ • Network monitoring   │ │                        │
│ Access: LoadBalancer IP    │ │ • Security metrics     │ │                        │
└────────────────────────────┘ └────────────────────────┘ └────────────────────────┘
```

---

## Data Sources

### 1. Cilium (CNI)

**Component:** Cilium Agent DaemonSet
**Namespace:** `cilium`

| Data Type | Source | Format | Destination |
|-----------|--------|--------|-------------|
| Network Flows | Hubble | JSON | **Timescape** (via Vector) |
| Connection Logs | Hubble | JSON | **Timescape** (via Vector) |
| Metrics | :9962 | Prometheus | **Splunk** (via OTEL) |
| Hubble Metrics | :9965 | Prometheus | **Splunk** (via OTEL) |

**Log Files:**
- `/var/run/cilium/hubble/hubble.log` - Network flows
- `/var/run/cilium/hubble/connectionlog.log` - Connection logs (for Timescape Connections tab)

**Sample Flow Event:**
```json
{
  "flow": {
    "time": "2024-01-15T10:30:00Z",
    "source": {
      "identity": 12345,
      "namespace": "default",
      "pod_name": "frontend-abc123",
      "labels": ["app=frontend"]
    },
    "destination": {
      "identity": 67890,
      "namespace": "default",
      "pod_name": "backend-xyz789",
      "labels": ["app=backend"]
    },
    "l4": {
      "TCP": {"source_port": 45678, "destination_port": 8080}
    },
    "verdict": "FORWARDED"
  }
}
```

---

### 2. Tetragon (Runtime Security)

**Component:** Tetragon DaemonSet
**Namespace:** `tetragon`

| Data Type | Source | Format | Destination |
|-----------|--------|--------|-------------|
| Metrics | :2112 | Prometheus | **Splunk** (via OTEL) |

**Note:** Tetragon process events are collected as **metrics** and sent to Splunk, not Timescape.
The Timescape Connections tab uses **Hubble connection logs** (see Cilium section above).

**Log Files:**
- `/var/run/cilium/hubble/tetragon.log` - Process events (for debugging, not Timescape)

**Supported Event Types:**
| Event | Description |
|-------|-------------|
| `PROCESS_EXEC` | Process execution |
| `PROCESS_EXIT` | Process termination |
| `PROCESS_CONNECT` | Outbound TCP connection |
| `PROCESS_CLOSE` | Connection close |
| `PROCESS_ACCEPT` | Inbound TCP connection |
| `PROCESS_LISTEN` | Socket listen |
| `PROCESS_DNS` | DNS query/response |
| `PROCESS_HTTP` | HTTP request/response |
| `PROCESS_TLS` | TLS handshake |

**Sample Connection Event:**
```json
{
  "process_connect": {
    "process": {
      "exec_id": "abc123",
      "pid": 1234,
      "binary": "/usr/bin/curl",
      "arguments": "https://api.example.com",
      "pod": {
        "namespace": "default",
        "name": "app-pod-xyz"
      }
    },
    "destination_ip": "10.0.1.100",
    "destination_port": 443,
    "destination_names": ["api.example.com"]
  },
  "node_name": "worker-1",
  "time": "2024-01-15T10:30:00Z"
}
```

**Key Metrics:**
| Metric | Description |
|--------|-------------|
| `tetragon_events_total` | Total events by type |
| `tetragon_dns_total` | DNS queries by binary, namespace, workload |
| `tetragon_bpf_missed_events_total` | Dropped events |

---

### 3. DCGM (GPU Monitoring)

**Component:** NVIDIA DCGM Exporter
**Namespace:** `nvidia-gpu-operator`

| Data Type | Source | Format | Description |
|-----------|--------|--------|-------------|
| GPU Metrics | :9400 | Prometheus | `DCGM_FI_*` metrics |

**Key Metrics:**
| Metric | Description |
|--------|-------------|
| `DCGM_FI_DEV_GPU_UTIL` | GPU utilization % |
| `DCGM_FI_DEV_MEM_COPY_UTIL` | Memory copy utilization |
| `DCGM_FI_DEV_FB_USED` | Framebuffer memory used |
| `DCGM_FI_DEV_FB_FREE` | Framebuffer memory free |
| `DCGM_FI_DEV_POWER_USAGE` | Power consumption (W) |
| `DCGM_FI_DEV_GPU_TEMP` | GPU temperature (C) |

---

### 4. Kubernetes Events

**Component:** k8s-exporter (Hubble Timescape)
**Namespace:** `hubble-timescape`

| Data Type | Source | Format | Description |
|-----------|--------|--------|-------------|
| K8s Events | K8s API | JSON | Policy and identity changes |

**Log File:** `/var/run/cilium/hubble/k8s-events.log`

**Watched Resources:**
- CiliumIdentity
- CiliumNetworkPolicy
- CiliumClusterwideNetworkPolicy
- NetworkPolicy

---

## Collectors

### Vector (Log Collector)

**Deployment:** DaemonSet
**Namespace:** `hubble-timescape`

**Sources:**
```yaml
sources:
  hubble_logs:
    type: file
    include:
      - /var/run/cilium/hubble/hubble.log
      - /var/run/cilium/hubble/k8s-events.log
  tetragon_logs:
    type: file
    include:
      - /var/run/cilium/hubble/tetragon-connections.log
```

**Destination:** Hubble Timescape Push API (HTTP POST to port 4260)

---

### Splunk OTEL Collector

**Deployment:** DaemonSet + ClusterReceiver
**Namespace:** `splunk-otel`

**Scrape Targets:**
| Target | Endpoint | Metrics Pattern |
|--------|----------|-----------------|
| Cilium Agent | cilium-agent.cilium.svc:9962 | `cilium_*` |
| Hubble | hubble-metrics.cilium.svc:9965 | `hubble_*` |
| Tetragon | tetragon-metrics.tetragon.svc:2112 | `tetragon_*` |
| DCGM | nvidia-dcgm-exporter.nvidia-gpu-operator.svc:9400 | `DCGM_FI_*` |

**Destination:** Splunk Observability Cloud (us1 realm)

---

## Destinations

### Hubble Timescape

**Access:** LoadBalancer IP (check `oc get svc -n hubble-timescape hubble-timescape-ui`)

**Data Available:**
| Tab | Data Source | Description |
|-----|-------------|-------------|
| Flows | hubble.log | Network flow visualization |
| Connections | tetragon-connections.log | Process-to-network correlation |
| Policies | k8s-events.log | Network policy audit |
| Explorer | All | Query interface |
| Assessment | All | Security posture analysis |

**Query Capabilities:**
- Filter by namespace, pod, identity
- Time range selection
- Flow verdict analysis
- Policy impact analysis

---

### Splunk Observability Cloud

**Access:** https://app.us1.signalfx.com

**Dashboards Available:**
| Dashboard | Metrics | Use Case |
|-----------|---------|----------|
| GPU Monitoring | DCGM_FI_* | GPU utilization, temperature, power |
| Network | cilium_*, hubble_* | Connection counts, policy drops |
| Security | tetragon_* | Process events, DNS queries |

---

## Integration Points

### For AI/ML Workloads

1. **GPU Metrics** → Splunk
   - Monitor GPU utilization during training/inference
   - Alert on thermal throttling
   - Capacity planning

2. **Network Flows** → Timescape
   - Analyze model API traffic patterns
   - Identify data exfiltration attempts
   - Troubleshoot connectivity issues

3. **Process Events** → Timescape
   - Track process execution in AI pods
   - Monitor library loading (CUDA, PyTorch)
   - Detect anomalous behavior

### For Security Operations

1. **Connection Logs** → Timescape
   - Process-aware network visibility
   - Identify which binary made each connection
   - DNS query correlation

2. **Policy Events** → Timescape
   - Network policy change audit
   - Before/after policy comparison
   - Compliance reporting

3. **Security Metrics** → Splunk
   - Event volume trending
   - Alert on unusual activity spikes
   - Long-term security posture tracking

---

## Configuration Reference

| Component | Config Location | Key Settings |
|-----------|-----------------|--------------|
| Tetragon | `apps/tetragon/operator-config.yaml` | export-filename, connection-log-filename |
| Vector | `clusters/_base/tier2-isovalent/vector-exporter.yaml` | sources, sinks |
| Timescape | `clusters/_base/tier2-isovalent/hubble-timescape.yaml` | ingester, UI features |
| Splunk OTEL | `clusters/_base/tier4-observability/splunk-otel.yaml` | scrape configs |

---

## Troubleshooting

### No data in Timescape

1. Check Vector logs: `oc logs -n hubble-timescape -l app.kubernetes.io/name=vector`
2. Check Ingester logs: `oc logs -n hubble-timescape deployment/hubble-timescape-ingester`
3. Verify log files exist: `oc debug node/<node> -- ls -la /var/run/cilium/hubble/`

### No metrics in Splunk

1. Check OTEL collector logs: `oc logs -n splunk-otel -l app=splunk-otel-collector`
2. Verify scrape targets are reachable
3. Check Splunk access token validity

### Missing Tetragon events

1. Verify Tetragon DaemonSet running: `oc get pods -n tetragon`
2. Check export allowlist in operator-config.yaml
3. Verify export directory permissions
