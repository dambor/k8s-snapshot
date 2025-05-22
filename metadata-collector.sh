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
  "performance_configs": {},
  "cluster_events": {},
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

# Pods with additional performance-related data
PODS_DATA=$(safe_kubectl_json get pods --all-namespaces | jq '[.items[] | {
  name: .metadata.name,
  namespace: .metadata.namespace,
  creation_timestamp: .metadata.creationTimestamp,
  labels: .metadata.labels,
  annotations: .metadata.annotations,
  node_name: .spec.nodeName,
  phase: .status.phase,
  restart_policy: .spec.restartPolicy,
  qos_class: .status.qosClass,
  priority: .spec.priority,
  priority_class_name: .spec.priorityClassName,
  restart_count: ([.status.containerStatuses[]?.restartCount // 0] | add),
  containers: [.spec.containers[] | {
    name: .name,
    image: .image,
    resources: .resources,
    ports: .ports,
    liveness_probe: .livenessProbe,
    readiness_probe: .readinessProbe,
    startup_probe: .startupProbe
  }],
  init_containers: [.spec.initContainers[]? | {
    name: .name,
    image: .image,
    resources: .resources
  }],
  conditions: [.status.conditions[]? | {type: .type, status: .status, reason: .reason, message: .message}],
  container_statuses: [.status.containerStatuses[]? | {
    name: .name,
    restart_count: .restartCount,
    ready: .ready,
    state: .state,
    last_state: .lastState
  }],
  topology_spread_constraints: .spec.topologySpreadConstraints,
  node_selector: .spec.nodeSelector,
  affinity: .spec.affinity,
  tolerations: .spec.tolerations,
  termination_grace_period: .spec.terminationGracePeriodSeconds
}]')

# Deployments with performance configurations
DEPLOYMENTS_DATA=$(safe_kubectl_json get deployments --all-namespaces | jq '[.items[] | {
  name: .metadata.name,
  namespace: .metadata.namespace,
  creation_timestamp: .metadata.creationTimestamp,
  labels: .metadata.labels,
  annotations: .metadata.annotations,
  replicas: .spec.replicas,
  ready_replicas: .status.readyReplicas,
  available_replicas: .status.availableReplicas,
  updated_replicas: .status.updatedReplicas,
  unavailable_replicas: .status.unavailableReplicas,
  strategy: .spec.strategy,
  revision_history_limit: .spec.revisionHistoryLimit,
  progress_deadline_seconds: .spec.progressDeadlineSeconds,
  containers: [.spec.template.spec.containers[] | {
    name: .name,
    image: .image,
    resources: .resources,
    liveness_probe: .livenessProbe,
    readiness_probe: .readinessProbe,
    startup_probe: .startupProbe
  }],
  pod_template: {
    topology_spread_constraints: .spec.template.spec.topologySpreadConstraints,
    node_selector: .spec.template.spec.nodeSelector,
    affinity: .spec.template.spec.affinity,
    tolerations: .spec.template.spec.tolerations,
    priority_class_name: .spec.template.spec.priorityClassName,
    termination_grace_period: .spec.template.spec.terminationGracePeriodSeconds,
    restart_policy: .spec.template.spec.restartPolicy
  }
}]')

# StatefulSets with performance configurations
STATEFULSETS_DATA=$(safe_kubectl_json get statefulsets --all-namespaces | jq '[.items[] | {
  name: .metadata.name,
  namespace: .metadata.namespace,
  creation_timestamp: .metadata.creationTimestamp,
  labels: .metadata.labels,
  annotations: .metadata.annotations,
  replicas: .spec.replicas,
  ready_replicas: .status.readyReplicas,
  current_replicas: .status.currentReplicas,
  updated_replicas: .status.updatedReplicas,
  service_name: .spec.serviceName,
  update_strategy: .spec.updateStrategy,
  revision_history_limit: .spec.revisionHistoryLimit,
  pod_management_policy: .spec.podManagementPolicy,
  containers: [.spec.template.spec.containers[] | {
    name: .name,
    image: .image,
    resources: .resources,
    liveness_probe: .livenessProbe,
    readiness_probe: .readinessProbe,
    startup_probe: .startupProbe
  }],
  volume_claim_templates: .spec.volumeClaimTemplates,
  pod_template: {
    topology_spread_constraints: .spec.template.spec.topologySpreadConstraints,
    node_selector: .spec.template.spec.nodeSelector,
    affinity: .spec.template.spec.affinity,
    tolerations: .spec.template.spec.tolerations,
    priority_class_name: .spec.template.spec.priorityClassName,
    termination_grace_period: .spec.template.spec.terminationGracePeriodSeconds
  }
}]')

# DaemonSets with performance configurations
DAEMONSETS_DATA=$(safe_kubectl_json get daemonsets --all-namespaces | jq '[.items[] | {
  name: .metadata.name,
  namespace: .metadata.namespace,
  creation_timestamp: .metadata.creationTimestamp,
  labels: .metadata.labels,
  annotations: .metadata.annotations,
  desired_number_scheduled: .status.desiredNumberScheduled,
  current_number_scheduled: .status.currentNumberScheduled,
  number_ready: .status.numberReady,
  number_available: .status.numberAvailable,
  number_unavailable: .status.numberUnavailable,
  updated_number_scheduled: .status.updatedNumberScheduled,
  update_strategy: .spec.updateStrategy,
  containers: [.spec.template.spec.containers[] | {
    name: .name,
    image: .image,
    resources: .resources,
    liveness_probe: .livenessProbe,
    readiness_probe: .readinessProbe,
    startup_probe: .startupProbe
  }],
  pod_template: {
    topology_spread_constraints: .spec.template.spec.topologySpreadConstraints,
    node_selector: .spec.template.spec.nodeSelector,
    affinity: .spec.template.spec.affinity,
    tolerations: .spec.template.spec.tolerations,
    priority_class_name: .spec.template.spec.priorityClassName,
    termination_grace_period: .spec.template.spec.terminationGracePeriodSeconds
  }
}]')

# Jobs and CronJobs
JOBS_DATA=$(safe_kubectl_json get jobs --all-namespaces | jq '[.items[] | {
  name: .metadata.name,
  namespace: .metadata.namespace,
  creation_timestamp: .metadata.creationTimestamp,
  labels: .metadata.labels,
  annotations: .metadata.annotations,
  completions: .spec.completions,
  parallelism: .spec.parallelism,
  backoff_limit: .spec.backoffLimit,
  active_deadline_seconds: .spec.activeDeadlineSeconds,
  completion_mode: .spec.completionMode,
  suspend: .spec.suspend,
  succeeded: .status.succeeded,
  failed: .status.failed,
  active: .status.active,
  containers: [.spec.template.spec.containers[] | {
    name: .name,
    image: .image,
    resources: .resources
  }],
  pod_template: {
    restart_policy: .spec.template.spec.restartPolicy,
    node_selector: .spec.template.spec.nodeSelector,
    affinity: .spec.template.spec.affinity,
    tolerations: .spec.template.spec.tolerations,
    priority_class_name: .spec.template.spec.priorityClassName
  }
}]')

CRONJOBS_DATA=$(safe_kubectl_json get cronjobs --all-namespaces | jq '[.items[] | {
  name: .metadata.name,
  namespace: .metadata.namespace,
  creation_timestamp: .metadata.creationTimestamp,
  labels: .metadata.labels,
  annotations: .metadata.annotations,
  schedule: .spec.schedule,
  timezone: .spec.timeZone,
  suspend: .spec.suspend,
  concurrency_policy: .spec.concurrencyPolicy,
  failed_jobs_history_limit: .spec.failedJobsHistoryLimit,
  successful_jobs_history_limit: .spec.successfulJobsHistoryLimit,
  starting_deadline_seconds: .spec.startingDeadlineSeconds,
  last_schedule_time: .status.lastScheduleTime,
  last_successful_time: .status.lastSuccessfulTime,
  active: (.status.active | length),
  job_template: {
    completions: .spec.jobTemplate.spec.completions,
    parallelism: .spec.jobTemplate.spec.parallelism,
    backoff_limit: .spec.jobTemplate.spec.backoffLimit,
    active_deadline_seconds: .spec.jobTemplate.spec.activeDeadlineSeconds
  }
}]')

jq --argjson pods "$PODS_DATA" --argjson deployments "$DEPLOYMENTS_DATA" --argjson statefulsets "$STATEFULSETS_DATA" --argjson daemonsets "$DAEMONSETS_DATA" --argjson jobs "$JOBS_DATA" --argjson cronjobs "$CRONJOBS_DATA" '
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
  },
  jobs: {
    count: ($jobs | length),
    details: $jobs
  },
  cronjobs: {
    count: ($cronjobs | length),
    details: $cronjobs
  }
}' "$OUTPUT_FILE" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"

# Collect performance and reliability configurations
print_success "Collecting performance and reliability configurations..."

# Horizontal Pod Autoscalers
HPA_DATA=$(safe_kubectl_json get hpa --all-namespaces | jq '[.items[] | {
  name: .metadata.name,
  namespace: .metadata.namespace,
  creation_timestamp: .metadata.creationTimestamp,
  labels: .metadata.labels,
  annotations: .metadata.annotations,
  scale_target_ref: .spec.scaleTargetRef,
  min_replicas: .spec.minReplicas,
  max_replicas: .spec.maxReplicas,
  target_cpu_utilization_percentage: .spec.targetCPUUtilizationPercentage,
  metrics: .spec.metrics,
  behavior: .spec.behavior,
  current_replicas: .status.currentReplicas,
  desired_replicas: .status.desiredReplicas,
  current_cpu_utilization_percentage: .status.currentCPUUtilizationPercentage,
  current_metrics: .status.currentMetrics,
  conditions: .status.conditions
}]')

# Vertical Pod Autoscalers (if available)
VPA_DATA=$(safe_kubectl_json get vpa --all-namespaces 2>/dev/null | jq '[.items[] | {
  name: .metadata.name,
  namespace: .metadata.namespace,
  creation_timestamp: .metadata.creationTimestamp,
  labels: .metadata.labels,
  annotations: .metadata.annotations,
  target_ref: .spec.targetRef,
  update_policy: .spec.updatePolicy,
  resource_policy: .spec.resourcePolicy,
  recommendation: .status.recommendation,
  conditions: .status.conditions
}]' 2>/dev/null || echo '[]')

# Pod Disruption Budgets
PDB_DATA=$(safe_kubectl_json get poddisruptionbudgets --all-namespaces | jq '[.items[] | {
  name: .metadata.name,
  namespace: .metadata.namespace,
  creation_timestamp: .metadata.creationTimestamp,
  labels: .metadata.labels,
  annotations: .metadata.annotations,
  min_available: .spec.minAvailable,
  max_unavailable: .spec.maxUnavailable,
  selector: .spec.selector,
  current_healthy: .status.currentHealthy,
  desired_healthy: .status.desiredHealthy,
  disruptions_allowed: .status.disruptionsAllowed,
  expected_pods: .status.expectedPods,
  observed_generation: .status.observedGeneration
}]')

# Priority Classes
PRIORITY_CLASSES_DATA=$(safe_kubectl_json get priorityclasses | jq '[.items[] | {
  name: .metadata.name,
  creation_timestamp: .metadata.creationTimestamp,
  labels: .metadata.labels,
  annotations: .metadata.annotations,
  value: .value,
  global_default: .globalDefault,
  description: .description,
  preemption_policy: .preemptionPolicy
}]')

# Resource Quotas
RESOURCE_QUOTAS_DATA=$(safe_kubectl_json get resourcequotas --all-namespaces | jq '[.items[] | {
  name: .metadata.name,
  namespace: .metadata.namespace,
  creation_timestamp: .metadata.creationTimestamp,
  labels: .metadata.labels,
  annotations: .metadata.annotations,
  hard: .spec.hard,
  scope_selector: .spec.scopeSelector,
  scopes: .spec.scopes,
  used: .status.used
}]')

# Limit Ranges
LIMIT_RANGES_DATA=$(safe_kubectl_json get limitranges --all-namespaces | jq '[.items[] | {
  name: .metadata.name,
  namespace: .metadata.namespace,
  creation_timestamp: .metadata.creationTimestamp,
  labels: .metadata.labels,
  annotations: .metadata.annotations,
  limits: .spec.limits
}]')

# Network Policies (performance impact)
NETWORK_POLICIES_DATA=$(safe_kubectl_json get networkpolicies --all-namespaces | jq '[.items[] | {
  name: .metadata.name,
  namespace: .metadata.namespace,
  creation_timestamp: .metadata.creationTimestamp,
  labels: .metadata.labels,
  annotations: .metadata.annotations,
  pod_selector: .spec.podSelector,
  policy_types: .spec.policyTypes,
  ingress: .spec.ingress,
  egress: .spec.egress
}]')

# Pod Security Policies (if available)
PSP_DATA=$(safe_kubectl_json get podsecuritypolicies 2>/dev/null | jq '[.items[] | {
  name: .metadata.name,
  creation_timestamp: .metadata.creationTimestamp,
  labels: .metadata.labels,
  annotations: .metadata.annotations,
  privileged: .spec.privileged,
  allow_privilege_escalation: .spec.allowPrivilegeEscalation,
  default_allow_privilege_escalation: .spec.defaultAllowPrivilegeEscalation,
  required_drop_capabilities: .spec.requiredDropCapabilities,
  allowed_capabilities: .spec.allowedCapabilities,
  volumes: .spec.volumes,
  host_network: .spec.hostNetwork,
  host_ports: .spec.hostPorts,
  host_pid: .spec.hostPID,
  host_ipc: .spec.hostIPC,
  se_linux: .spec.seLinux,
  run_as_user: .spec.runAsUser,
  run_as_group: .spec.runAsGroup,
  supplemental_groups: .spec.supplementalGroups,
  fs_group: .spec.fsGroup
}]' 2>/dev/null || echo '[]')

jq --argjson hpa "$HPA_DATA" --argjson vpa "$VPA_DATA" --argjson pdb "$PDB_DATA" --argjson pc "$PRIORITY_CLASSES_DATA" --argjson rq "$RESOURCE_QUOTAS_DATA" --argjson lr "$LIMIT_RANGES_DATA" --argjson np "$NETWORK_POLICIES_DATA" --argjson psp "$PSP_DATA" '
.performance_configs = {
  horizontal_pod_autoscalers: {
    count: ($hpa | length),
    details: $hpa
  },
  vertical_pod_autoscalers: {
    count: ($vpa | length),
    details: $vpa
  },
  pod_disruption_budgets: {
    count: ($pdb | length),
    details: $pdb
  },
  priority_classes: {
    count: ($pc | length),
    details: $pc
  },
  resource_quotas: {
    count: ($rq | length),
    details: $rq
  },
  limit_ranges: {
    count: ($lr | length),
    details: $lr
  },
  network_policies: {
    count: ($np | length),
    details: $np
  },
  pod_security_policies: {
    count: ($psp | length),
    details: $psp
  }
}' "$OUTPUT_FILE" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"

# Collect cluster events and performance indicators
print_success "Collecting cluster events and performance indicators..."

# Recent events (last 100)
EVENTS_DATA=$(kubectl get events --all-namespaces --sort-by='.lastTimestamp' --output=json 2>/dev/null | jq '[.items[-100:] | .[] | {
  namespace: .namespace,
  name: .metadata.name,
  creation_timestamp: .metadata.creationTimestamp,
  first_timestamp: .firstTimestamp,
  last_timestamp: .lastTimestamp,
  count: .count,
  type: .type,
  reason: .reason,
  message: .message,
  source: .source,
  involved_object: {
    kind: .involvedObject.kind,
    name: .involvedObject.name,
    namespace: .involvedObject.namespace
  }
}]' || echo '[]')

# OOMKilled events specifically
OOMKILL_EVENTS=$(echo "$EVENTS_DATA" | jq '[.[] | select(.reason == "OOMKilling" or .reason == "OOMKilled" or (.message | contains("OOMKilled")))]')

# Failed scheduling events
SCHEDULING_EVENTS=$(echo "$EVENTS_DATA" | jq '[.[] | select(.reason == "FailedScheduling" or .reason == "Preempted")]')

# Image pull issues
IMAGE_EVENTS=$(echo "$EVENTS_DATA" | jq '[.[] | select(.reason | test("Failed.*Pull|BackOff|ErrImagePull"))]')

# Node events
NODE_EVENTS=$(echo "$EVENTS_DATA" | jq '[.[] | select(.involved_object.kind == "Node")]')

jq --argjson events "$EVENTS_DATA" --argjson oomkills "$OOMKILL_EVENTS" --argjson scheduling "$SCHEDULING_EVENTS" --argjson images "$IMAGE_EVENTS" --argjson nodes "$NODE_EVENTS" '
.cluster_events = {
  recent_events: {
    count: ($events | length),
    details: $events
  },
  oom_kills: {
    count: ($oomkills | length),
    details: $oomkills
  },
  scheduling_failures: {
    count: ($scheduling | length),
    details: $scheduling
  },
  image_pull_issues: {
    count: ($images | length),
    details: $images
  },
  node_events: {
    count: ($nodes | length),
    details: $nodes
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

# Calculate performance metrics
PODS_WITH_RESOURCE_LIMITS=$(jq '[.workloads.pods.details[] | select(.containers[].resources.limits != null)] | length' "$OUTPUT_FILE")
PODS_WITH_RESTART_ISSUES=$(jq '[.workloads.pods.details[] | select(.restart_count > 5)] | length' "$OUTPUT_FILE")
DEPLOYMENTS_WITH_HPA=$(jq '[.performance_configs.horizontal_pod_autoscalers.details[].scale_target_ref.name] as $hpa_targets | [.workloads.deployments.details[] | select(.name as $name | $hpa_targets | index($name))] | length' "$OUTPUT_FILE")
NAMESPACES_WITH_QUOTAS=$(jq '[.performance_configs.resource_quotas.details[].namespace] | unique | length' "$OUTPUT_FILE")

# Calculate topology spread usage
WORKLOADS_WITH_TOPOLOGY_SPREAD=$(jq '[.workloads.deployments.details[], .workloads.statefulsets.details[], .workloads.daemonsets.details[] | select(.pod_template.topology_spread_constraints != null and (.pod_template.topology_spread_constraints | length) > 0)] | length' "$OUTPUT_FILE")

# Calculate affinity usage
WORKLOADS_WITH_AFFINITY=$(jq '[.workloads.deployments.details[], .workloads.statefulsets.details[], .workloads.daemonsets.details[] | select(.pod_template.affinity != null)] | length' "$OUTPUT_FILE")

# Calculate probe configurations
PODS_WITH_HEALTH_CHECKS=$(jq '[.workloads.pods.details[] | select(.containers[] | .liveness_probe != null or .readiness_probe != null or .startup_probe != null)] | length' "$OUTPUT_FILE")

jq --arg ns_count "$NAMESPACE_COUNT" --arg pods_limits "$PODS_WITH_RESOURCE_LIMITS" --arg pods_restarts "$PODS_WITH_RESTART_ISSUES" --arg deps_hpa "$DEPLOYMENTS_WITH_HPA" --arg ns_quotas "$NAMESPACES_WITH_QUOTAS" --arg topo_spread "$WORKLOADS_WITH_TOPOLOGY_SPREAD" --arg affinity "$WORKLOADS_WITH_AFFINITY" --arg health_checks "$PODS_WITH_HEALTH_CHECKS" '
.cluster_summary = {
  namespace_count: ($ns_count | tonumber),
  node_count: .nodes.count,
  total_pods: .workloads.pods.count,
  running_pods: .resource_usage.current_usage.running_pods,
  deployment_count: .workloads.deployments.count,
  statefulset_count: .workloads.statefulsets.count,
  daemonset_count: .workloads.daemonsets.count,
  job_count: .workloads.jobs.count,
  cronjob_count: .workloads.cronjobs.count,
  service_count: .networking.services.count,
  ingress_count: .networking.ingresses.count,
  pv_count: .storage.persistent_volumes.count,
  pvc_count: .storage.persistent_volume_claims.count,
  hpa_count: .performance_configs.horizontal_pod_autoscalers.count,
  vpa_count: .performance_configs.vertical_pod_autoscalers.count,
  pdb_count: .performance_configs.pod_disruption_budgets.count,
  priority_class_count: .performance_configs.priority_classes.count,
  resource_quota_count: .performance_configs.resource_quotas.count,
  limit_range_count: .performance_configs.limit_ranges.count,
  network_policy_count: .performance_configs.network_policies.count,
  oom_kills_recent: .cluster_events.oom_kills.count,
  scheduling_failures_recent: .cluster_events.scheduling_failures.count,
  image_pull_issues_recent: .cluster_events.image_pull_issues.count,
  resource_utilization: {
    pod_capacity_used_percent: .resource_usage.current_usage.pod_utilization_percent,
    total_cpu_cores: .resource_usage.cluster_capacity.cpu_cores,
    total_memory_gi: (.resource_usage.cluster_capacity.memory_ki / 1024 / 1024 | round),
    pods_with_resource_limits: ($pods_limits | tonumber),
    pods_with_restart_issues: ($pods_restarts | tonumber),
    deployments_with_hpa: ($deps_hpa | tonumber),
    namespaces_with_quotas: ($ns_quotas | tonumber),
    workloads_with_topology_spread: ($topo_spread | tonumber),
    workloads_with_affinity: ($affinity | tonumber),
    pods_with_health_checks: ($health_checks | tonumber)
  },
  performance_indicators: {
    resource_limit_coverage_percent: (($pods_limits | tonumber) / .workloads.pods.count * 100 | round),
    hpa_coverage_percent: (($deps_hpa | tonumber) / .workloads.deployments.count * 100 | round),
    health_check_coverage_percent: (($health_checks | tonumber) / .workloads.pods.count * 100 | round),
    namespace_quota_coverage_percent: (($ns_quotas | tonumber) / ($ns_count | tonumber) * 100 | round)
  }
}' "$OUTPUT_FILE" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"

print_header "Collection Complete"
print_success "Cluster metadata collected successfully!"
echo "Output file: $OUTPUT_FILE"
echo "File size: $(du -h "$OUTPUT_FILE" | cut -f1)"
echo ""

# Show enhanced summary
echo "=== ENHANCED CLUSTER SUMMARY ==="
jq -r '
"Collection Date: " + .collection_timestamp +
"\nKubernetes Version: " + .cluster_info.kubernetes_version +
"\nContext: " + .cluster_info.context +
"\n" +
"\n📊 CLUSTER RESOURCES:" +
"\nNodes: " + (.cluster_summary.node_count | tostring) +
"\nNamespaces: " + (.cluster_summary.namespace_count | tostring) +
"\nTotal Pods: " + (.cluster_summary.total_pods | tostring) +
"\nRunning Pods: " + (.cluster_summary.running_pods | tostring) +
"\nDeployments: " + (.cluster_summary.deployment_count | tostring) +
"\nStatefulSets: " + (.cluster_summary.statefulset_count | tostring) +
"\nDaemonSets: " + (.cluster_summary.daemonset_count | tostring) +
"\nJobs: " + (.cluster_summary.job_count | tostring) +
"\nCronJobs: " + (.cluster_summary.cronjob_count | tostring) +
"\nServices: " + (.cluster_summary.service_count | tostring) +
"\nPersistent Volumes: " + (.cluster_summary.pv_count | tostring) +
"\n" +
"\n⚡ PERFORMANCE CONFIGURATIONS:" +
"\nHorizontal Pod Autoscalers: " + (.cluster_summary.hpa_count | tostring) +
"\nVertical Pod Autoscalers: " + (.cluster_summary.vpa_count | tostring) +
"\nPod Disruption Budgets: " + (.cluster_summary.pdb_count | tostring) +
"\nPriority Classes: " + (.cluster_summary.priority_class_count | tostring) +
"\nResource Quotas: " + (.cluster_summary.resource_quota_count | tostring) +
"\nLimit Ranges: " + (.cluster_summary.limit_range_count | tostring) +
"\nNetwork Policies: " + (.cluster_summary.network_policy_count | tostring) +
"\n" +
"\n💾 RESOURCE UTILIZATION:" +
"\nTotal CPU Cores: " + (.cluster_summary.resource_utilization.total_cpu_cores | tostring) +
"\nTotal Memory (Gi): " + (.cluster_summary.resource_utilization.total_memory_gi | tostring) +
"\nPod Capacity Used: " + (.cluster_summary.resource_utilization.pod_capacity_used_percent | tostring) + "%" +
"\nPods with Resource Limits: " + (.cluster_summary.resource_utilization.pods_with_resource_limits | tostring) +
"\nPods with Health Checks: " + (.cluster_summary.resource_utilization.pods_with_health_checks | tostring) +
"\nWorkloads with Topology Spread: " + (.cluster_summary.resource_utilization.workloads_with_topology_spread | tostring) +
"\nWorkloads with Affinity Rules: " + (.cluster_summary.resource_utilization.workloads_with_affinity | tostring) +
"\n" +
"\n📈 PERFORMANCE INDICATORS:" +
"\nResource Limit Coverage: " + (.cluster_summary.performance_indicators.resource_limit_coverage_percent | tostring) + "%" +
"\nHPA Coverage: " + (.cluster_summary.performance_indicators.hpa_coverage_percent | tostring) + "%" +
"\nHealth Check Coverage: " + (.cluster_summary.performance_indicators.health_check_coverage_percent | tostring) + "%" +
"\nNamespace Quota Coverage: " + (.cluster_summary.performance_indicators.namespace_quota_coverage_percent | tostring) + "%" +
"\n" +
"\n🚨 RECENT ISSUES:" +
"\nOOM Kills (recent): " + (.cluster_summary.oom_kills_recent | tostring) +
"\nScheduling Failures (recent): " + (.cluster_summary.scheduling_failures_recent | tostring) +
"\nImage Pull Issues (recent): " + (.cluster_summary.image_pull_issues_recent | tostring) +
"\nPods with Restart Issues: " + (.cluster_summary.resource_utilization.pods_with_restart_issues | tostring)
' "$OUTPUT_FILE"

echo ""
echo "=== PERFORMANCE ANALYSIS QUERIES ==="
echo "🔍 Query examples for performance analysis:"
echo ""
echo "# Check OOM killed pods:"
echo "jq '.cluster_events.oom_kills.details[] | {pod: .involved_object.name, namespace: .involved_object.namespace, message: .message}' $OUTPUT_FILE"
echo ""
echo "# Find pods without resource limits:"
echo "jq '.workloads.pods.details[] | select(.containers[] | .resources.limits == null) | {name, namespace, node_name}' $OUTPUT_FILE"
echo ""
echo "# Check HPA configurations:"
echo "jq '.performance_configs.horizontal_pod_autoscalers.details[] | {name, namespace, min_replicas, max_replicas, current_replicas}' $OUTPUT_FILE"
echo ""
echo "# Analyze topology spread constraints:"
echo "jq '.workloads.deployments.details[] | select(.pod_template.topology_spread_constraints != null) | {name, namespace, topology_constraints: .pod_template.topology_spread_constraints}' $OUTPUT_FILE"
echo ""
echo "# Check pod disruption budgets:"
echo "jq '.performance_configs.pod_disruption_budgets.details[] | {name, namespace, min_available, max_unavailable, disruptions_allowed}' $OUTPUT_FILE"
echo ""
echo "# Find high restart count pods:"
echo "jq '.workloads.pods.details[] | select(.restart_count > 5) | {name, namespace, restart_count, phase}' $OUTPUT_FILE"
echo ""
echo "# Check priority class usage:"
echo "jq '.workloads.pods.details[] | select(.priority_class_name != null) | {name, namespace, priority_class: .priority_class_name}' $OUTPUT_FILE"

echo ""
print_success "Enhanced cluster analysis with performance configurations completed!"
echo "Use the query examples above to analyze specific performance aspects of your cluster."