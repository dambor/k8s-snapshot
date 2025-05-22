#!/bin/bash

# Kubernetes Cluster Metadata JSON Collector
# Collects non-sensitive cluster metadata and outputs to a single JSON file
# No secrets or sensitive data is collected

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
OUTPUT_FILE="cluster-metadata-$(date +%Y%m%d-%H%M%S).json"

# Function to print colored output
print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to safely execute kubectl and return JSON
safe_kubectl_json() {
    kubectl "$@" -o json 2>/dev/null || echo '{"items":[]}'
}

# Function to get resource count
get_resource_count() {
    kubectl get "$1" --all-namespaces --no-headers 2>/dev/null | wc -l || echo "0"
}

# Check prerequisites
print_header "Prerequisites Check"
if ! command_exists kubectl; then
    print_error "kubectl not found. Please install kubectl."
    exit 1
fi

if ! command_exists jq; then
    print_error "jq not found. Please install jq for JSON processing."
    exit 1
fi

if ! kubectl cluster-info >/dev/null 2>&1; then
    print_error "Cannot connect to Kubernetes cluster."
    exit 1
fi

print_success "kubectl, jq, and cluster connectivity verified"

print_header "Collecting Cluster Metadata"

echo "Collecting data and generating JSON..."

# Start building the JSON structure
cat > "$OUTPUT_FILE" << 'EOF'
{
  "collection_timestamp": "",
  "cluster_info": {},
  "nodes": {},
  "workloads": {},
  "networking": {},
  "storage": {},
  "metrics": {},
  "resource_usage": {},
  "cluster_summary": {}
}
EOF

# Add timestamp
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
jq --arg ts "$TIMESTAMP" '.collection_timestamp = $ts' "$OUTPUT_FILE" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"

# Collect cluster info
print_success "Collecting cluster information..."
CLUSTER_INFO=$(kubectl cluster-info 2>/dev/null | head -5 || echo "Cluster info unavailable")
CONTEXT=$(kubectl config current-context 2>/dev/null || echo "unknown")
K8S_VERSION=$(kubectl version --short 2>/dev/null | grep "Server Version" | cut -d' ' -f3 || echo "unknown")

jq --arg info "$CLUSTER_INFO" --arg context "$CONTEXT" --arg version "$K8S_VERSION" '
.cluster_info = {
  "context": $context,
  "kubernetes_version": $version,
  "cluster_endpoints": $info
}' "$OUTPUT_FILE" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"

# Collect nodes data (without sensitive info)
print_success "Collecting node metadata..."
NODES_DATA=$(safe_kubectl_json get nodes | jq '[.items[] | {
  name: .metadata.name,
  creation_timestamp: .metadata.creationTimestamp,
  labels: (.metadata.labels | to_entries | map(select(.key | test("kubernetes.io|node.kubernetes.io|beta.kubernetes.io|topology.kubernetes.io|node-role.kubernetes.io") )) | from_entries),
  capacity: .status.capacity,
  allocatable: .status.allocatable,
  node_info: .status.nodeInfo,
  conditions: [.status.conditions[] | {type: .type, status: .status, reason: .reason}],
  addresses: [.status.addresses[] | {type: .type, address: .address}],
  taints: (.spec.taints // [])
}]')

jq --argjson nodes "$NODES_DATA" '.nodes = {
  count: ($nodes | length),
  details: $nodes
}' "$OUTPUT_FILE" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"

# Collect workloads metadata (excluding sensitive env vars and volumes)
print_success "Collecting workload metadata..."

# Pods
PODS_DATA=$(safe_kubectl_json get pods --all-namespaces | jq '[.items[] | {
  name: .metadata.name,
  namespace: .metadata.namespace,
  creation_timestamp: .metadata.creationTimestamp,
  labels: .metadata.labels,
  node_name: .spec.nodeName,
  phase: .status.phase,
  restart_policy: .spec.restartPolicy,
  containers: [.spec.containers[] | {
    name: .name,
    image: .image,
    resources: .resources,
    ports: .ports
  }],
  conditions: [.status.conditions[]? | {type: .type, status: .status}]
}]')

# Deployments
DEPLOYMENTS_DATA=$(safe_kubectl_json get deployments --all-namespaces | jq '[.items[] | {
  name: .metadata.name,
  namespace: .metadata.namespace,
  creation_timestamp: .metadata.creationTimestamp,
  labels: .metadata.labels,
  replicas: .spec.replicas,
  ready_replicas: .status.readyReplicas,
  available_replicas: .status.availableReplicas,
  strategy: .spec.strategy,
  containers: [.spec.template.spec.containers[] | {
    name: .name,
    image: .image,
    resources: .resources
  }]
}]')

# StatefulSets
STATEFULSETS_DATA=$(safe_kubectl_json get statefulsets --all-namespaces | jq '[.items[] | {
  name: .metadata.name,
  namespace: .metadata.namespace,
  creation_timestamp: .metadata.creationTimestamp,
  labels: .metadata.labels,
  replicas: .spec.replicas,
  ready_replicas: .status.readyReplicas,
  service_name: .spec.serviceName
}]')

# DaemonSets
DAEMONSETS_DATA=$(safe_kubectl_json get daemonsets --all-namespaces | jq '[.items[] | {
  name: .metadata.name,
  namespace: .metadata.namespace,
  creation_timestamp: .metadata.creationTimestamp,
  labels: .metadata.labels,
  desired_number_scheduled: .status.desiredNumberScheduled,
  current_number_scheduled: .status.currentNumberScheduled,
  number_ready: .status.numberReady
}]')

jq --argjson pods "$PODS_DATA" --argjson deployments "$DEPLOYMENTS_DATA" --argjson statefulsets "$STATEFULSETS_DATA" --argjson daemonsets "$DAEMONSETS_DATA" '
.workloads = {
  pods: {
    count: ($pods | length),
    details: $pods
  },
  deployments: {
    count: ($deployments | length),
    details: $deployments
  },
  statefulsets: {
    count: ($statefulsets | length),
    details: $statefulsets
  },
  daemonsets: {
    count: ($daemonsets | length),
    details: $daemonsets
  }
}' "$OUTPUT_FILE" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"

# Collect networking metadata
print_success "Collecting networking metadata..."

SERVICES_DATA=$(safe_kubectl_json get services --all-namespaces | jq '[.items[] | {
  name: .metadata.name,
  namespace: .metadata.namespace,
  type: .spec.type,
  cluster_ip: .spec.clusterIP,
  ports: .spec.ports,
  selector: .spec.selector
}]')

INGRESSES_DATA=$(safe_kubectl_json get ingresses --all-namespaces | jq '[.items[] | {
  name: .metadata.name,
  namespace: .metadata.namespace,
  creation_timestamp: .metadata.creationTimestamp,
  rules: .spec.rules
}]')

jq --argjson services "$SERVICES_DATA" --argjson ingresses "$INGRESSES_DATA" '
.networking = {
  services: {
    count: ($services | length),
    details: $services
  },
  ingresses: {
    count: ($ingresses | length),
    details: $ingresses
  }
}' "$OUTPUT_FILE" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"

# Collect storage metadata
print_success "Collecting storage metadata..."

PV_DATA=$(safe_kubectl_json get persistentvolumes | jq '[.items[] | {
  name: .metadata.name,
  capacity: .spec.capacity,
  access_modes: .spec.accessModes,
  reclaim_policy: .spec.persistentVolumeReclaimPolicy,
  status: .status.phase,
  storage_class: .spec.storageClassName
}]')

PVC_DATA=$(safe_kubectl_json get persistentvolumeclaims --all-namespaces | jq '[.items[] | {
  name: .metadata.name,
  namespace: .metadata.namespace,
  status: .status.phase,
  capacity: .status.capacity,
  access_modes: .spec.accessModes,
  storage_class: .spec.storageClassName,
  volume_name: .spec.volumeName
}]')

STORAGE_CLASSES_DATA=$(safe_kubectl_json get storageclasses | jq '[.items[] | {
  name: .metadata.name,
  provisioner: .provisioner,
  reclaim_policy: .reclaimPolicy,
  volume_binding_mode: .volumeBindingMode
}]')

jq --argjson pvs "$PV_DATA" --argjson pvcs "$PVC_DATA" --argjson sc "$STORAGE_CLASSES_DATA" '
.storage = {
  persistent_volumes: {
    count: ($pvs | length),
    details: $pvs
  },
  persistent_volume_claims: {
    count: ($pvcs | length),
    details: $pvcs
  },
  storage_classes: {
    count: ($sc | length),
    details: $sc
  }
}' "$OUTPUT_FILE" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"

# Collect metrics (if available)
print_success "Collecting metrics data..."

if kubectl get deployment metrics-server -n kube-system >/dev/null 2>&1; then
    # Node metrics
    NODE_METRICS=$(kubectl top nodes --no-headers 2>/dev/null | awk '{print "{\"node\":\"" $1 "\",\"cpu\":\"" $2 "\",\"cpu_percent\":\"" $3 "\",\"memory\":\"" $4 "\",\"memory_percent\":\"" $5 "\"}"}' | jq -s '.' 2>/dev/null || echo '[]')
    
    # Pod metrics (top 50 by CPU)
    POD_METRICS=$(kubectl top pods --all-namespaces --no-headers 2>/dev/null | head -50 | awk '{print "{\"namespace\":\"" $1 "\",\"pod\":\"" $2 "\",\"cpu\":\"" $3 "\",\"memory\":\"" $4 "\"}"}' | jq -s '.' 2>/dev/null || echo '[]')
    
    jq --argjson node_metrics "$NODE_METRICS" --argjson pod_metrics "$POD_METRICS" '
    .metrics = {
      metrics_server_available: true,
      node_metrics: $node_metrics,
      pod_metrics: $pod_metrics
    }' "$OUTPUT_FILE" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"
else
    jq '.metrics = {
      metrics_server_available: false,
      message: "Metrics server not found"
    }' "$OUTPUT_FILE" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"
fi

# Collect resource usage summary
print_success "Calculating resource usage summary..."

# Calculate total cluster capacity
TOTAL_CPU=$(jq -r '.nodes.details[] | .capacity.cpu' "$OUTPUT_FILE" | sed 's/m$//' | awk '{if($1~/m$/) {gsub(/m/,"",$1); $1=$1/1000} sum+=$1} END{print sum}' 2>/dev/null || echo "0")
TOTAL_MEMORY=$(jq -r '.nodes.details[] | .capacity.memory' "$OUTPUT_FILE" | sed 's/Ki$//' | awk '{sum+=$1} END{print sum}' 2>/dev/null || echo "0")
TOTAL_PODS=$(jq -r '.nodes.details[] | .capacity.pods' "$OUTPUT_FILE" | awk '{sum+=$1} END{print sum}' 2>/dev/null || echo "0")

# Calculate allocatable resources
ALLOCATABLE_CPU=$(jq -r '.nodes.details[] | .allocatable.cpu' "$OUTPUT_FILE" | sed 's/m$//' | awk '{if($1~/m$/) {gsub(/m/,"",$1); $1=$1/1000} sum+=$1} END{print sum}' 2>/dev/null || echo "0")
ALLOCATABLE_MEMORY=$(jq -r '.nodes.details[] | .allocatable.memory' "$OUTPUT_FILE" | sed 's/Ki$//' | awk '{sum+=$1} END{print sum}' 2>/dev/null || echo "0")
ALLOCATABLE_PODS=$(jq -r '.nodes.details[] | .allocatable.pods' "$OUTPUT_FILE" | awk '{sum+=$1} END{print sum}' 2>/dev/null || echo "0")

# Count running pods
RUNNING_PODS=$(jq '[.workloads.pods.details[] | select(.phase == "Running")] | length' "$OUTPUT_FILE")

jq --arg total_cpu "$TOTAL_CPU" --arg total_memory "$TOTAL_MEMORY" --arg total_pods "$TOTAL_PODS" \
   --arg alloc_cpu "$ALLOCATABLE_CPU" --arg alloc_memory "$ALLOCATABLE_MEMORY" --arg alloc_pods "$ALLOCATABLE_PODS" \
   --arg running_pods "$RUNNING_PODS" '
.resource_usage = {
  cluster_capacity: {
    cpu_cores: ($total_cpu | tonumber),
    memory_ki: ($total_memory | tonumber),
    max_pods: ($total_pods | tonumber)
  },
  allocatable_resources: {
    cpu_cores: ($alloc_cpu | tonumber),
    memory_ki: ($alloc_memory | tonumber),
    max_pods: ($alloc_pods | tonumber)
  },
  current_usage: {
    running_pods: ($running_pods | tonumber),
    pod_utilization_percent: (($running_pods | tonumber) / ($alloc_pods | tonumber) * 100 | round)
  }
}' "$OUTPUT_FILE" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"

# Generate cluster summary
print_success "Generating cluster summary..."

NAMESPACE_COUNT=$(kubectl get namespaces --no-headers 2>/dev/null | wc -l || echo "0")

jq --arg ns_count "$NAMESPACE_COUNT" '
.cluster_summary = {
  namespace_count: ($ns_count | tonumber),
  node_count: .nodes.count,
  total_pods: .workloads.pods.count,
  running_pods: .resource_usage.current_usage.running_pods,
  deployment_count: .workloads.deployments.count,
  service_count: .networking.services.count,
  pv_count: .storage.persistent_volumes.count,
  resource_utilization: {
    pod_capacity_used_percent: .resource_usage.current_usage.pod_utilization_percent,
    total_cpu_cores: .resource_usage.cluster_capacity.cpu_cores,
    total_memory_gi: (.resource_usage.cluster_capacity.memory_ki / 1024 / 1024 | round)
  }
}' "$OUTPUT_FILE" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"

print_header "Collection Complete"
print_success "Cluster metadata collected successfully!"
echo "Output file: $OUTPUT_FILE"
echo "File size: $(du -h "$OUTPUT_FILE" | cut -f1)"
echo ""

# Show summary
echo "=== CLUSTER SUMMARY ==="
jq -r '
"Collection Date: " + .collection_timestamp +
"\nKubernetes Version: " + .cluster_info.kubernetes_version +
"\nContext: " + .cluster_info.context +
"\nNodes: " + (.cluster_summary.node_count | tostring) +
"\nNamespaces: " + (.cluster_summary.namespace_count | tostring) +
"\nTotal Pods: " + (.cluster_summary.total_pods | tostring) +
"\nRunning Pods: " + (.cluster_summary.running_pods | tostring) +
"\nDeployments: " + (.cluster_summary.deployment_count | tostring) +
"\nServices: " + (.cluster_summary.service_count | tostring) +
"\nTotal CPU Cores: " + (.cluster_summary.resource_utilization.total_cpu_cores | tostring) +
"\nTotal Memory (Gi): " + (.cluster_summary.resource_utilization.total_memory_gi | tostring) +
"\nPod Capacity Used: " + (.cluster_summary.resource_utilization.pod_capacity_used_percent | tostring) + "%"
' "$OUTPUT_FILE"

echo ""
print_success "JSON file contains comprehensive cluster metadata without sensitive data"
echo "Use 'jq' to query specific data: jq '.cluster_summary' $OUTPUT_FILE"