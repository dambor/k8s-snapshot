# Kubernetes Cluster Metadata Collector

A secure script that collects comprehensive cluster metadata for analysis and optimization. Gathers the same data that monitoring platforms use while ensuring **no sensitive information** is collected.

## 🔒 Security

- ✅ **No secrets, passwords, or sensitive data collected**
- ✅ **No environment variables or configuration details**
- ✅ **Read-only operations only**
- ✅ **Only public metadata and resource specifications**

## 📋 Prerequisites

```bash
# Install required tools
brew install kubectl jq              # macOS
sudo apt-get install kubectl jq      # Ubuntu/Debian
sudo yum install kubectl jq          # CentOS/RHEL
```

## 🚀 Usage

```bash
# Make executable and run
chmod +x metadata-collector.sh
./metadata-collector.sh

# Output: cluster-metadata-YYYYMMDD-HHMMSS.json
```

## 📊 Collected Data

### **Core Resources**
- **Nodes**: Capacity, conditions, taints, allocatable resources
- **Workloads**: Pods, Deployments, StatefulSets, DaemonSets, Jobs, CronJobs
- **Storage**: Persistent Volumes, Claims, Storage Classes
- **Networking**: Services, Ingresses, Network Policies

### **Performance Configurations**
- **Autoscaling**: HPA, VPA configurations and current status
- **Reliability**: Pod Disruption Budgets, Priority Classes
- **Resource Management**: Resource Quotas, Limit Ranges
- **Scheduling**: Topology spread constraints, affinity rules

### **Performance Indicators**
- **Health Checks**: Liveness, readiness, startup probes
- **Resource Limits**: CPU/memory constraints coverage
- **Recent Issues**: OOM kills, scheduling failures, restart loops
- **Utilization**: Cluster capacity and current usage

## 🔍 Quick Analysis

```bash
# View cluster summary
jq '.cluster_summary' cluster-metadata-*.json

# Check performance indicators
jq '.cluster_summary.performance_indicators' cluster-metadata-*.json

# Find pods without resource limits
jq '.workloads.pods.details[] | select(.containers[] | .resources.limits == null) | {name, namespace}' cluster-metadata-*.json

# Check recent OOM kills
jq '.cluster_events.oom_kills.details[] | {pod: .involved_object.name, namespace: .involved_object.namespace}' cluster-metadata-*.json

# Analyze HPA configurations
jq '.performance_configs.horizontal_pod_autoscalers.details[] | {name, namespace, min_replicas, max_replicas}' cluster-metadata-*.json
```

## 📈 Output Structure

```json
{
  "collection_timestamp": "2024-01-15T10:30:00Z",
  "cluster_info": { "kubernetes_version": "v1.28.2", "context": "..." },
  "nodes": { "count": 5, "details": [...] },
  "workloads": { "pods": {...}, "deployments": {...}, ... },
  "performance_configs": { "horizontal_pod_autoscalers": {...}, ... },
  "cluster_events": { "oom_kills": {...}, "scheduling_failures": {...} },
  "networking": { "services": {...}, "ingresses": {...} },
  "storage": { "persistent_volumes": {...}, ... },
  "metrics": { "node_metrics": [...], "pod_metrics": [...] },
  "resource_usage": { "cluster_capacity": {...}, "current_usage": {...} },
  "cluster_summary": { "performance_indicators": {...}, ... }
}
```

## ⚡ Performance Analysis

The script identifies:
- **Resource bottlenecks**: Pods without limits, over-utilized nodes
- **Configuration gaps**: Missing health checks, no PDBs
- **Reliability issues**: High restart counts, scheduling failures
- **Optimization opportunities**: Unused HPA, poor resource distribution

## 🛠️ Troubleshooting

**Missing Metrics:**
```bash
# Install metrics-server if needed
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```
