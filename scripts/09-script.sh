#! /bin/bash

## variables for cidr
POD_CIDR=(10.200.0.0/24 10.200.1.0/24 10.200.2.0/24)

KEY_PATH="~/default-key.pem"

cat > 99-loopback.conf <<EOF
{
    "cniVersion": "0.3.1",
    "type": "loopback"
}
EOF

for i in 0 1 2; do
instance=ip-10-240-0-2$i
  IP=$(aws ec2 describe-instances --instance-id ${WORK_ID[i]} --query 'Reservations[].Instances[].PublicIpAddress'| jq .[0] | sed 's/"//g')

  cat > 10-bridge.conf <<EOF
{
    "cniVersion": "0.3.1",
    "name": "bridge",
    "type": "bridge",
    "bridge": "cnio0",
    "isGateway": true,
    "ipMasq": true,
    "ipam": {
        "type": "host-local",
        "ranges": [
          [{"subnet": "${POD_CIDR[i]}"}]
        ],
        "routes": [{"dst": "0.0.0.0/0"}]
    }
}
EOF
  
  scp -i $KEY_PATH -o "StrictHostKeyChecking no" 10-bridge.conf 99-loopback.conf ubuntu@$IP:~/
  ssh -i $KEY_PATH -o "StrictHostKeyChecking no" ubuntu@$IP "sudo mv 10-bridge.conf 99-loopback.conf /etc/cni/net.d/"
  
## containerd 
cat > config.toml <<EOF
[plugins]
  [plugins.cri.containerd]
    snapshotter = "overlayfs"
    [plugins.cri.containerd.default_runtime]
      runtime_type = "io.containerd.runtime.v1.linux"
      runtime_engine = "/usr/local/bin/runc"
      runtime_root = ""
    [plugins.cri.containerd.untrusted_workload_runtime]
      runtime_type = "io.containerd.runtime.v1.linux"
      runtime_engine = "/usr/local/bin/runsc"
      runtime_root = "/run/containerd/runsc"
EOF

cat > containerd.service <<EOF
[Unit]
  Description=containerd container runtime
  Documentation=https://containerd.io
  After=network.target

[Service]
  ExecStartPre=/sbin/modprobe overlay
  ExecStart=/bin/containerd
  Restart=always
  RestartSec=5
  Delegate=yes
  KillMode=process
  OOMScoreAdjust=-999
  LimitNOFILE=1048576
  LimitNPROC=infinity
  LimitCORE=infinity

[Install]
  WantedBy=multi-user.target
EOF


  scp -i $KEY_PATH -o "StrictHostKeyChecking no" config.toml containerd.service ubuntu@$IP:~/
  ssh -i $KEY_PATH -o "StrictHostKeyChecking no" ubuntu@$IP "sudo mv config.toml /etc/containerd/"
  ssh -i $KEY_PATH -o "StrictHostKeyChecking no" ubuntu@$IP "sudo mv containerd.service /etc/systemd/system/"

# kubelet

  ssh -i $KEY_PATH -o "StrictHostKeyChecking no" ubuntu@$IP "sudo mv ${instance}-key.pem ${instance}.pem /var/lib/kubelet/"
  ssh -i $KEY_PATH -o "StrictHostKeyChecking no" ubuntu@$IP "sudo mv ${instance}.kubeconfig /var/lib/kubelet/kubeconfig"
  ssh -i $KEY_PATH -o "StrictHostKeyChecking no" ubuntu@$IP "sudo mv ca.pem /var/lib/kubernetes/"

  cat > kubelet-config.yaml <<EOF
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
  x509:
    clientCAFile: "/var/lib/kubernetes/ca.pem"
authorization:
  mode: Webhook
clusterDomain: "cluster.local"
clusterDNS:
  - "10.32.0.10"
podCIDR: "${POD_CIDR}"
runtimeRequestTimeout: "15m"
tlsCertFile: "/var/lib/kubelet/${instance}.pem"
tlsPrivateKeyFile: "/var/lib/kubelet/${instance}-key.pem"
EOF

  cat > kubelet.service <<EOF
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/kubernetes/kubernetes
After=containerd.service
Requires=containerd.service

[Service]
ExecStart=/usr/local/bin/kubelet \\
  --config=/var/lib/kubelet/kubelet-config.yaml \\
  --container-runtime=remote \\
  --container-runtime-endpoint=unix:///var/run/containerd/containerd.sock \\
  --image-pull-progress-deadline=2m \\
  --kubeconfig=/var/lib/kubelet/kubeconfig \\
  --network-plugin=cni \\
  --register-node=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  scp -i $KEY_PATH -o "StrictHostKeyChecking no" kubelet.service kubelet-config.yaml ubuntu@$IP:~/
  ssh -i $KEY_PATH -o "StrictHostKeyChecking no" ubuntu@$IP "sudo mv kubelet-config.yaml /var/lib/kubelet/"
  ssh -i $KEY_PATH -o "StrictHostKeyChecking no" ubuntu@$IP "sudo mv kubelet.service /etc/systemd/system/"

# kube-proxy 
  
  ssh -i $KEY_PATH -o "StrictHostKeyChecking no" ubuntu@$IP "sudo mv kube-proxy.kubeconfig /var/lib/kube-proxy/kubeconfig"

  cat > kube-proxy-config.yaml <<EOF
kind: KubeProxyConfiguration
apiVersion: kubeproxy.config.k8s.io/v1alpha1
clientConnection:
  kubeconfig: "/var/lib/kube-proxy/kubeconfig"
mode: "iptables"
clusterCIDR: "10.200.0.0/16"
EOF

  cat > kube-proxy.service <<EOF
[Unit]
Description=Kubernetes Kube Proxy
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-proxy \\
  --config=/var/lib/kube-proxy/kube-proxy-config.yaml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  scp -i $KEY_PATH -o "StrictHostKeyChecking no" kube-proxy.service kube-proxy-config.yaml ubuntu@$IP:~/
  ssh -i $KEY_PATH -o "StrictHostKeyChecking no" ubuntu@$IP "sudo mv kube-proxy-config.yaml /var/lib/kube-proxy/"
  ssh -i $KEY_PATH -o "StrictHostKeyChecking no" ubuntu@$IP "sudo mv kube-proxy.service /etc/systemd/system/"


  ssh -i $KEY_PATH -o "StrictHostKeyChecking no" ubuntu@$IP "sudo systemctl daemon-reload"
  ssh -i $KEY_PATH -o "StrictHostKeyChecking no" ubuntu@$IP "sudo systemctl enable containerd kubelet kube-proxy"
  ssh -i $KEY_PATH -o "StrictHostKeyChecking no" ubuntu@$IP "sudo systemctl start containerd kubelet kube-proxy"

done
