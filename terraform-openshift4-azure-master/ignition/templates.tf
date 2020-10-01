data "template_file" "install_config_yaml" {
  template = <<EOF
apiVersion: v1
baseDomain: ${var.base_domain}
compute:
- hyperthreading: Enabled
  name: worker
  platform:
    azure:
      type: ${var.worker_vm_type}
      osDisk:
        diskSizeGB: ${var.worker_os_disk_size}
        diskType: Premium_LRS
  replicas: ${var.node_count}
controlPlane:
  hyperthreading: Enabled
  name: master
  platform:
    azure:
      type: ${var.master_vm_type}
      osDisk:
        diskSizeGB: ${var.master_os_disk_size}
        diskType: Premium_LRS
      zones:
      - "1"
      - "2"
      - "3"
  replicas: ${var.master_count}
metadata:
  creationTimestamp: null
  name: ${var.cluster_name}
networking:
  clusterNetwork:
  - cidr: ${var.cluster_network_cidr}
    hostPrefix: ${var.cluster_network_host_prefix}
  machineNetwork:
  - cidr: ${var.machine_cidr}
  networkType: OpenShiftSDN
  serviceNetwork:
  - ${var.service_network_cidr}
platform:
  azure:
    region: ${var.azure_region}
    baseDomainResourceGroupName: ${var.azure_dns_resource_group_name}
    networkResourceGroupName: ${var.network_resource_group_name}
    virtualNetwork: ${var.virtual_network_name}
    controlPlaneSubnet: ${var.control_plane_subnet}
    computeSubnet: ${var.compute_subnet}
    osDisk:
      diskSizeGB: ${var.worker_os_disk_size}
      diskType: Premium_LRS
publish: ${var.private ? "Internal" : "External"}
pullSecret: '${chomp(file(var.openshift_pull_secret))}'
sshKey: '${var.public_ssh_key}'
%{if var.airgapped["enabled"]}imageContentSources:
- mirrors:
  - ${var.airgapped["repository"]}
  source: quay.io/openshift-release-dev/ocp-release
- mirrors:
  - ${var.airgapped["repository"]}
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
%{endif}
EOF
}

resource "local_file" "install_config_yaml" {
  content  = data.template_file.install_config_yaml.rendered
  filename = "${local.installer_workspace}/install-config.yaml"
  depends_on = [
    null_resource.download_binaries,
  ]
}

data "template_file" "cluster-infrastructure-02-config" {
  template = <<EOF
apiVersion: config.openshift.io/v1
kind: Infrastructure
metadata:
  creationTimestamp: null
  name: cluster
spec:
  cloudConfig:
    key: config
    name: cloud-provider-config
status:
  apiServerInternalURI: https://api-int.${var.cluster_name}.${var.base_domain}:6443
  apiServerURL: https://api.${var.cluster_name}.${var.base_domain}:6443
  etcdDiscoveryDomain: ${var.cluster_name}.${var.base_domain}
  infrastructureName: ${var.cluster_id}
  platform: Azure
  platformStatus:
    azure:
      resourceGroupName: ${var.cluster_id}-rg
    type: Azure
EOF
}

resource "local_file" "cluster-infrastructure-02-config" {
  content  = data.template_file.cluster-infrastructure-02-config.rendered
  filename = "${local.installer_workspace}/manifests/cluster-infrastructure-02-config.yml"
  depends_on = [
    null_resource.download_binaries,
    null_resource.generate_manifests,
  ]
}

data "template_file" "cluster-dns-02-config" {
  template = <<EOF
apiVersion: config.openshift.io/v1
kind: DNS
metadata:
  creationTimestamp: null
  name: cluster
spec:
  baseDomain: ${var.cluster_name}.${var.base_domain}
  privateZone:
    id: /subscriptions/${var.azure_subscription_id}/resourceGroups/${var.cluster_id}-rg/providers/Microsoft.Network/privateDnsZones/${var.cluster_name}.${var.base_domain}
  publicZone:
    id: /subscriptions/${var.azure_subscription_id}/resourceGroups/${var.azure_dns_resource_group_name}/providers/Microsoft.Network/dnszones/${var.base_domain}
status: {}
EOF
}

resource "local_file" "cluster-dns-02-config" {
  content  = data.template_file.cluster-dns-02-config.rendered
  filename = "${local.installer_workspace}/manifests/cluster-dns-02-config.yml"
  depends_on = [
    null_resource.download_binaries,
    null_resource.generate_manifests,
  ]
}

data "template_file" "cloud-provider-config" {
  template = <<EOF
apiVersion: v1
data:
  config: "{\n\t\"cloud\": \"AzurePublicCloud\",\n\t\"tenantId\": \"${var.azure_tenant_id}\",\n\t\"aadClientId\":
    \"\",\n\t\"aadClientSecret\": \"\",\n\t\"aadClientCertPath\": \"\",\n\t\"aadClientCertPassword\":
    \"\",\n\t\"useManagedIdentityExtension\": true,\n\t\"userAssignedIdentityID\":
    \"\",\n\t\"subscriptionId\": \"${var.azure_subscription_id}\",\n\t\"resourceGroup\":
    \"${var.cluster_id}-rg\",\n\t\"location\": \"${var.azure_region}\",\n\t\"vnetName\": \"${var.virtual_network_name}\",\n\t\"vnetResourceGroup\":
    \"${var.network_resource_group_name}\",\n\t\"subnetName\": \"${var.compute_subnet}\",\n\t\"securityGroupName\":
    \"${var.cluster_id}-nsg\",\n\t\"routeTableName\": \"${var.cluster_id}-node-routetable\",\n\t\"primaryAvailabilitySetName\":
    \"\",\n\t\"vmType\": \"\",\n\t\"primaryScaleSetName\": \"\",\n\t\"cloudProviderBackoff\":
    true,\n\t\"cloudProviderBackoffRetries\": 0,\n\t\"cloudProviderBackoffExponent\":
    0,\n\t\"cloudProviderBackoffDuration\": 6,\n\t\"cloudProviderBackoffJitter\":
    0,\n\t\"cloudProviderRateLimit\": true,\n\t\"cloudProviderRateLimitQPS\": 12,\n\t\"cloudProviderRateLimitBucket\":
    10,\n\t\"cloudProviderRateLimitQPSWrite\": 12,\n\t\"cloudProviderRateLimitBucketWrite\":
    10,\n\t\"useInstanceMetadata\": true,\n\t\"loadBalancerSku\": \"standard\",\n\t\"excludeMasterFromStandardLB\":
    null,\n\t\"disableOutboundSNAT\": null,\n\t\"maximumLoadBalancerRuleCount\": 0\n}\n"
kind: ConfigMap
metadata:
  name: cloud-provider-config
  namespace: openshift-config
EOF
}

resource "local_file" "cloud-provider-config" {
  content  = data.template_file.cloud-provider-config.rendered
  filename = "${local.installer_workspace}/manifests/cloud-provider-config.yaml"
  depends_on = [
    null_resource.download_binaries,
    null_resource.generate_manifests,
  ]
}

data "template_file" "openshift-cluster-api_master-machines" {
  count    = var.master_count
  template = <<EOF
apiVersion: machine.openshift.io/v1beta1
kind: Machine
metadata:
  creationTimestamp: null
  labels:
    machine.openshift.io/cluster-api-cluster: ${var.cluster_id}
    machine.openshift.io/cluster-api-machine-role: master
    machine.openshift.io/cluster-api-machine-type: master
  name: ${var.cluster_id}-master-${count.index}
  namespace: openshift-machine-api
spec:
  metadata:
    creationTimestamp: null
  providerSpec:
    value:
      apiVersion: azureproviderconfig.openshift.io/v1beta1
      credentialsSecret:
        name: azure-cloud-credentials
        namespace: openshift-machine-api
      image:
        offer: ""
        publisher: ""
        resourceID: /resourceGroups/${var.cluster_id}-rg/providers/Microsoft.Compute/images/${var.cluster_id}
        sku: ""
        version: ""
      internalLoadBalancer: ""
      kind: AzureMachineProviderSpec
      location: ${var.azure_region}
      managedIdentity: ${var.cluster_id}-identity
      metadata:
        creationTimestamp: null
      natRule: null
      networkResourceGroup: ${var.network_resource_group_name}
      osDisk:
        diskSizeGB: ${var.master_os_disk_size}
        managedDisk:
          storageAccountType: Premium_LRS
        osType: Linux
      publicIP: false
      publicLoadBalancer: ""
      resourceGroup: ${var.cluster_id}-rg
      sshPrivateKey: ""
      sshPublicKey: ""
      subnet: ${var.control_plane_subnet}
      userDataSecret:
        name: master-user-data
      vmSize: ${var.master_vm_type}
      vnet: ${var.virtual_network_name}
      zone: "${count.index + 1}"
status: {}
EOF
}

resource "local_file" "openshift-cluster-api_master-machines" {
  count    = var.master_count
  content  = element(data.template_file.openshift-cluster-api_master-machines.*.rendered, count.index)
  filename = "${local.installer_workspace}/openshift/99_openshift-cluster-api_master-machines-${count.index}.yaml"
  depends_on = [
    null_resource.download_binaries,
    null_resource.generate_manifests,
  ]
}

data "template_file" "openshift-cluster-api_worker-machineset" {
  count    = var.node_count
  template = <<EOF
apiVersion: machine.openshift.io/v1beta1
kind: MachineSet
metadata:
  creationTimestamp: null
  labels:
    machine.openshift.io/cluster-api-cluster: ${var.cluster_id}
    machine.openshift.io/cluster-api-machine-role: worker
    machine.openshift.io/cluster-api-machine-type: worker
  name: ${var.cluster_id}-worker-${var.azure_region}${count.index + 1}
  namespace: openshift-machine-api
spec:
  replicas: 1
  selector:
    matchLabels:
      machine.openshift.io/cluster-api-cluster: ${var.cluster_id}
      machine.openshift.io/cluster-api-machineset: ${var.cluster_id}-worker-${var.azure_region}${count.index + 1}
  template:
    metadata:
      creationTimestamp: null
      labels:
        machine.openshift.io/cluster-api-cluster: ${var.cluster_id}
        machine.openshift.io/cluster-api-machine-role: worker
        machine.openshift.io/cluster-api-machine-type: worker
        machine.openshift.io/cluster-api-machineset: ${var.cluster_id}-worker-${var.azure_region}${count.index + 1}
    spec:
      metadata:
        creationTimestamp: null
      providerSpec:
        value:
          apiVersion: azureproviderconfig.openshift.io/v1beta1
          credentialsSecret:
            name: azure-cloud-credentials
            namespace: openshift-machine-api
          image:
            offer: ""
            publisher: ""
            resourceID: /resourceGroups/${var.cluster_id}-rg/providers/Microsoft.Compute/images/${var.cluster_id}
            sku: ""
            version: ""
          internalLoadBalancer: ""
          kind: AzureMachineProviderSpec
          location: ${var.azure_region}
          managedIdentity: ${var.cluster_id}-identity
          metadata:
            creationTimestamp: null
          natRule: null
          networkResourceGroup: ${var.network_resource_group_name}
          osDisk:
            diskSizeGB: ${var.worker_os_disk_size}
            managedDisk:
              storageAccountType: Premium_LRS
            osType: Linux
          publicIP: false
          publicLoadBalancer: ""
          resourceGroup: ${var.cluster_id}-rg
          sshPrivateKey: ""
          sshPublicKey: ""
          subnet: ${var.compute_subnet}
          userDataSecret:
            name: worker-user-data
          vmSize: ${var.worker_vm_type}
          vnet: ${var.virtual_network_name}
          zone: "${count.index + 1}"
status:
  replicas: 0
EOF
}

resource "local_file" "openshift-cluster-api_worker-machineset" {
  count    = var.node_count
  content  = element(data.template_file.openshift-cluster-api_worker-machineset.*.rendered, count.index)
  filename = "${local.installer_workspace}/openshift/99_openshift-cluster-api_worker-machineset-${count.index}.yaml"
  depends_on = [
    null_resource.download_binaries,
    null_resource.generate_manifests,
  ]
}

data "template_file" "openshift-cluster-api_infra-machineset" {
  count    = var.infra_count
  template = <<EOF
apiVersion: machine.openshift.io/v1beta1
kind: MachineSet
metadata:
  creationTimestamp: null
  labels:
    machine.openshift.io/cluster-api-cluster: ${var.cluster_id}
    machine.openshift.io/cluster-api-machine-role: infra
    machine.openshift.io/cluster-api-machine-type: infra
  name: ${var.cluster_id}-infra-${var.azure_region}${count.index + 1}
  namespace: openshift-machine-api
spec:
  replicas: 1
  selector:
    matchLabels:
      machine.openshift.io/cluster-api-cluster: ${var.cluster_id}
      machine.openshift.io/cluster-api-machineset: ${var.cluster_id}-infra-${var.azure_region}${count.index + 1}
  template:
    metadata:
      creationTimestamp: null
      labels:
        machine.openshift.io/cluster-api-cluster: ${var.cluster_id}
        machine.openshift.io/cluster-api-machine-role: infra
        machine.openshift.io/cluster-api-machine-type: infra
        machine.openshift.io/cluster-api-machineset: ${var.cluster_id}-infra-${var.azure_region}${count.index + 1}
    spec:
      metadata:
        creationTimestamp: null
        labels:
          node-role.kubernetes.io/infra: ""
      providerSpec:
        value:
          apiVersion: azureproviderconfig.openshift.io/v1beta1
          credentialsSecret:
            name: azure-cloud-credentials
            namespace: openshift-machine-api
          image:
            offer: ""
            publisher: ""
            resourceID: /resourceGroups/${var.cluster_id}-rg/providers/Microsoft.Compute/images/${var.cluster_id}
            sku: ""
            version: ""
          internalLoadBalancer: ""
          kind: AzureMachineProviderSpec
          location: ${var.azure_region}
          managedIdentity: ${var.cluster_id}-identity
          metadata:
            creationTimestamp: null
          natRule: null
          networkResourceGroup: ${var.network_resource_group_name}
          osDisk:
            diskSizeGB: ${var.infra_os_disk_size}
            managedDisk:
              storageAccountType: Premium_LRS
            osType: Linux
          publicIP: false
          publicLoadBalancer: ""
          resourceGroup: ${var.cluster_id}-rg
          sshPrivateKey: ""
          sshPublicKey: ""
          subnet: ${var.compute_subnet}
          userDataSecret:
            name: worker-user-data
          vmSize: ${var.infra_vm_type}
          vnet: ${var.virtual_network_name}
          zone: "${count.index + 1}"
EOF
}

resource "local_file" "openshift-cluster-api_infra-machineset" {
  count    = var.infra_count
  content  = element(data.template_file.openshift-cluster-api_infra-machineset.*.rendered, count.index)
  filename = "${local.installer_workspace}/openshift/99_openshift-cluster-api_infra-machineset-${count.index}.yaml"
  depends_on = [
    null_resource.download_binaries,
    null_resource.generate_manifests,
  ]
}


data "template_file" "cloud-creds-secret-kube-system" {
  template = <<EOF
kind: Secret
apiVersion: v1
metadata:
  namespace: kube-system
  name: azure-credentials
data:
  azure_subscription_id: ${base64encode(var.azure_subscription_id)}
  azure_client_id: ${base64encode(var.azure_client_id)}
  azure_client_secret: ${base64encode(var.azure_client_secret)}
  azure_tenant_id: ${base64encode(var.azure_tenant_id)}
  azure_resource_prefix: ${base64encode(var.cluster_id)}
  azure_resourcegroup: ${base64encode("${var.cluster_id}-rg")}
  azure_region: ${base64encode(var.azure_region)}
EOF
}

resource "local_file" "cloud-creds-secret-kube-system" {
  content  = data.template_file.cloud-creds-secret-kube-system.rendered
  filename = "${local.installer_workspace}/openshift/99_cloud-creds-secret.yaml"
  depends_on = [
    null_resource.download_binaries,
    null_resource.generate_manifests,
  ]
}

data "template_file" "cluster-monitoring-configmap" {
  template = <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-monitoring-config
  namespace: openshift-monitoring
data:
  config.yaml: |+
    alertmanagerMain:
      nodeSelector:
        node-role.kubernetes.io/infra: ""
    prometheusK8s:
      nodeSelector:
        node-role.kubernetes.io/infra: ""
    prometheusOperator:
      nodeSelector:
        node-role.kubernetes.io/infra: ""
    grafana:
      nodeSelector:
        node-role.kubernetes.io/infra: ""
    k8sPrometheusAdapter:
      nodeSelector:
        node-role.kubernetes.io/infra: ""
    kubeStateMetrics:
      nodeSelector:
        node-role.kubernetes.io/infra: ""
    telemeterClient:
      nodeSelector:
        node-role.kubernetes.io/infra: ""
EOF
}

resource "local_file" "cluster-monitoring-configmap" {
  count    = var.infra_count > 0 ? 1 : 0
  content  = data.template_file.cluster-monitoring-configmap.rendered
  filename = "${local.installer_workspace}/openshift/99_cluster-monitoring-configmap.yml"
  depends_on = [
    null_resource.download_binaries,
    null_resource.generate_manifests,
  ]
}


data "template_file" "configure-image-registry-job" {
  template = <<EOF
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: infra
  namespace: openshift-image-registry
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: system:ibm-patch-cluster-storage
rules:
- apiGroups: ['imageregistry.operator.openshift.io']
  resources: ['configs']
  verbs:     ['get','patch']
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: system:ibm-patch-cluster-storage
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:ibm-patch-cluster-storage
subjects:
  - kind: ServiceAccount
    name: default
    namespace: openshift-image-registry
---
apiVersion: batch/v1
kind: Job
metadata:
  name: ibm-configure-image-registry
  namespace: openshift-image-registry
spec:
  parallelism: 1
  completions: 1
  template:
    metadata:
      name: configure-image-registry
      labels:
        app: configure-image-registry
    serviceAccountName: infra
    spec:
      containers:
      - name:  client
        image: quay.io/openshift/origin-cli:latest
        command: ["/bin/sh","-c"]
        args: ["while ! /usr/bin/oc get configs cluster >/dev/null 2>&1; do sleep 1;done;/usr/bin/oc patch configs cluster --type merge --patch '{\"spec\": {\"nodeSelector\": {\"node-role.kubernetes.io/infra\": \"\"}}}'"]
      restartPolicy: Never
EOF
}

resource "local_file" "configure-image-registry-job" {
  count    = var.infra_count > 0 ? 1 : 0
  content  = data.template_file.configure-image-registry-job.rendered
  filename = "${local.installer_workspace}/openshift/99_configure-image-registry-job.yml"
  depends_on = [
    null_resource.download_binaries,
    null_resource.generate_manifests,
  ]
}

# data "template_file" "private-cluster-outbound-service" {
#   template = <<EOF
# ---
# apiVersion: v1	
# kind: Service	
# metadata:	
#   namespace: openshift-config-managed	
#   name: outbound-provider
#   annotations:
#     service.beta.kubernetes.io/azure-load-balancer-internal: "true"
# spec:	
#   type: LoadBalancer	
#   ports:	
#   - port: 27627	
# EOF	
# }

# resource "local_file" "private-cluster-outbound-service" {
#   count    = var.private ? (var.outbound_udr ? 0 : 1) : 0
#   content  = data.template_file.private-cluster-outbound-service.rendered
#   filename = "${local.installer_workspace}/openshift/99_private-cluster-outbound-service.yaml"
#   depends_on = [
#     null_resource.download_binaries,
#     null_resource.generate_manifests,
#   ]
# }


data "template_file" "airgapped_registry_upgrades" {
  count    = var.airgapped["enabled"] ? 1 : 0
  template = <<EOF
apiVersion: operator.openshift.io/v1alpha1
kind: ImageContentSourcePolicy
metadata:
  name: airgapped
spec:
  repositoryDigestMirrors:
  - mirrors:
    - ${var.airgapped["repository"]}
    source: quay.io/openshift-release-dev/ocp-release
  - mirrors:
    - ${var.airgapped["repository"]}
    source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
EOF
}

resource "local_file" "airgapped_registry_upgrades" {
  count    = var.airgapped["enabled"] ? 1 : 0
  content  = element(data.template_file.airgapped_registry_upgrades.*.rendered, count.index)
  filename = "${local.installer_workspace}/openshift/99_airgapped_registry_upgrades.yaml"
  depends_on = [
    null_resource.download_binaries,
    null_resource.generate_manifests,
  ]
}
