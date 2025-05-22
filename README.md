# Kubernetes Cluster Metadata Collector

A secure script to collect comprehensive cluster metadata for analysis, optimization, and monitoring purposes. This tool gathers the same type of data that monitoring and optimization platforms typically access, while ensuring **no sensitive information** is collected.

## 🔒 Security First

This script is designed with security as a top priority:

- ✅ **No secrets or sensitive data collected**
- ✅ **No environment variables or configuration details**
- ✅ **No volume mounts or storage credentials**
- ✅ **Only public metadata and resource specifications**
- ✅ **Filters out sensitive labels and annotations**
- ✅ **Read-only operations only**

## 📋 Prerequisites

Before running the script, ensure you have:

- `kubectl` installed and configured
- `jq` installed for JSON processing
- Access to your Kubernetes cluster
- Appropriate RBAC permissions to read cluster resources

### Installing Prerequisites

**On macOS:**
```bash
brew install kubectl jq
```

**On Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install kubectl jq
```

**On CentOS/RHEL:**
```bash
sudo yum install kubectl jq
```

## 🚀 Usage

### Basic Usage

1. **Make the script executable:**
   ```bash
   chmod +x cluster-metadata-collector.sh
   ```

2. **Run the collection:**
   ```bash
   ./cluster-metadata-collector.sh
   ```

3. **View the results:**
   ```bash
   # The script will output a file named: cluster-metadata-YYYYMMDD-HHMMSS.json
   ls cluster-metadata-*.json
   ```

### Querying the Data

Use `jq` to query specific information from the collected data:

```bash
# View cluster summary
jq '.cluster_summary' cluster-metadata-*.json

# Check node information
jq '.nodes.details[] | {name, capacity, allocatable}' cluster-metadata-*.json

# List all deployments
jq '.workloads.deployments.details[] | {name, namespace, replicas}' cluster-metadata-*.json

# Check resource utilization
jq '.resource_usage' cluster-metadata-*.json

# View pod distribution by namespace
jq '.workloads.pods.details | group_by(.namespace) | map({namespace: .[0].namespace, count: length})' cluster-metadata-*.json
```

## 📊 Data Structure

The generated JSON file contains the following sections:

### Root Structure
```json
{
  "collection_timestamp": "2024-01-15T10:30:00Z",
  "cluster_info": {},
  "nodes": {},
  "workloads": {},
  "networking": {},
  "storage": {},
  "metrics": {},
  "resource_usage": {},
  "cluster_summary": {}
}
```

### Detailed Sections

#### 🖥️ **cluster_info**
- Kubernetes version
- Cluster context
- Cluster endpoints

#### 🔧 **nodes**
- Node count and details
- Capacity and allocatable resources
- Node conditions and status
- Operating system information
- Node addresses (internal/external IPs)

#### 🚀 **workloads**
- **Pods**: Running workloads, phases, resource usage
- **Deployments**: Replica counts, strategies, container specs
- **StatefulSets**: Ordered deployments, persistent workloads
- **DaemonSets**: Node-level services, system components

#### 🌐 **networking**
- **Services**: Load balancing, service discovery
- **Ingresses**: HTTP routing rules, external access

#### 💾 **storage**
- **Persistent Volumes**: Available storage resources
- **Persistent Volume Claims**: Storage requests
- **Storage Classes**: Available storage types

#### 📈 **metrics** (if metrics-server available)
- Node CPU and memory usage
- Pod resource consumption
- Performance data

#### 📊 **resource_usage**
- Cluster capacity calculations
- Resource utilization percentages
- Pod density analysis

#### 📋 **cluster_summary**
- High-level statistics
- Resource utilization overview
- Quick cluster health indicators

## 🔍 Common Use Cases

### 1. **Cluster Optimization Analysis**
```bash
# Check resource utilization
jq '.resource_usage.current_usage' cluster-metadata-*.json

# Find over/under-utilized nodes
jq '.metrics.node_metrics[] | select(.cpu_percent | tonumber > 80)' cluster-metadata-*.json
```

### 2. **Capacity Planning**
```bash
# Total cluster capacity
jq '.resource_usage.cluster_capacity' cluster-metadata-*.json

# Current vs. allocatable resources
jq '{capacity: .resource_usage.cluster_capacity, allocatable: .resource_usage.allocatable_resources}' cluster-metadata-*.json
```

### 3. **Workload Distribution**
```bash
# Pods per node
jq '.workloads.pods.details | group_by(.node_name) | map({node: .[0].node_name, pod_count: length})' cluster-metadata-*.json

# Resource requests by namespace
jq '.workloads.deployments.details | group_by(.namespace) | map({namespace: .[0].namespace, deployments: length})' cluster-metadata-*.json
```

### 4. **Security and Compliance**
```bash
# Check for pods without resource limits
jq '.workloads.pods.details[] | select(.containers[].resources.limits == null) | {name, namespace}' cluster-metadata-*.json

# Identify privileged or system workloads
jq '.workloads.pods.details[] | select(.namespace | startswith("kube-")) | {name, namespace}' cluster-metadata-*.json
```

## 📝 Output Example

The script provides a summary upon completion:

```
=== CLUSTER SUMMARY ===
Collection Date: 2024-01-15T10:30:00Z
Kubernetes Version: v1.28.2
Context: my-cluster-context
Nodes: 5
Namespaces: 12
Total Pods: 156
Running Pods: 142
Deployments: 45
Services: 38
Total CPU Cores: 20
Total Memory (Gi): 80
Pod Capacity Used: 67%
```

## 🛠️ Troubleshooting

### Permission Issues
```bash
# Check cluster access
kubectl cluster-info

# Verify permissions
kubectl auth can-i get nodes
kubectl auth can-i get pods --all-namespaces
```

### Missing Dependencies
```bash
# Check if kubectl is installed
kubectl version --client

# Check if jq is installed
jq --version
```

### Metrics Server Not Available
If you see "Metrics server not found", this is normal and the script will continue without real-time metrics. To install metrics-server:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

## 🔧 Customization

### Modifying Collection Scope

To exclude certain resource types, comment out the relevant sections in the script:

```bash
# Comment out these lines to skip specific collections
# STATEFULSETS_DATA=$(safe_kubectl_json get statefulsets --all-namespaces | jq '...')
```

### Adding Custom Queries

Add custom jq queries to the summary section:

```bash
# Add to the end of the script
echo "Custom Analysis:"
jq '.workloads.pods.details | map(select(.phase != "Running")) | length' "$OUTPUT_FILE"
```

## 📄 File Management

### Cleanup Old Files
```bash
# Remove files older than 7 days
find . -name "cluster-metadata-*.json" -mtime +7 -delete
```

### Archive Collections
```bash
# Create monthly archives
mkdir -p archives/$(date +%Y-%m)
mv cluster-metadata-*.json archives/$(date +%Y-%m)/
```

## 🤝 Contributing

Feel free to submit issues, feature requests, or pull requests to improve this tool.

### Development Setup
```bash
# Clone and make executable
git clone <repository>
chmod +x cluster-metadata-collector.sh

# Test with your cluster
./cluster-metadata-collector.sh
```

## 📜 License

This script is provided as-is for cluster analysis purposes. Use responsibly and in accordance with your organization's security policies.

## ⚠️ Important Notes

- **Data Privacy**: While this script doesn't collect sensitive data, review the output before sharing
- **Network Usage**: The script makes multiple API calls to your cluster
- **Performance**: Collection time depends on cluster size (typically 30 seconds to 2 minutes)
- **Storage**: JSON files can be large for big clusters (1-50MB typical)

## 📞 Support

For issues or questions:
1. Check the troubleshooting section above
2. Verify prerequisites are installed
3. Ensure proper cluster access and permissions
4. Review the script output for specific error messages
