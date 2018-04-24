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
  ssh -i $KEY_PATH -o "StrictHostKeyChecking no" ubuntu@$IP "sudo mv ${instance}-key.pem ${instance}.pem /var/lib/kubelet/"
  ssh -i $KEY_PATH -o "StrictHostKeyChecking no" ubuntu@$IP "sudo mv ${instance}.kubeconfig /var/lib/kubelet/kubeconfig"
  ssh -i $KEY_PATH -o "StrictHostKeyChecking no" ubuntu@$IP "sudo mv ca.pem /var/lib/kubernetes/"
  
  cat > kubelet.service <<EOF
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/kubernetes/kubernetes
After=cri-containerd.service
Requires=cri-containerd.service

[Service]
ExecStart=/usr/local/bin/kubelet \\
  --allow-privileged=true \\
  --anonymous-auth=false \\
  --authorization-mode=Webhook \\
  --client-ca-file=/var/lib/kubernetes/ca.pem \\
  --cloud-provider= \\
  --cluster-dns=10.32.0.10 \\
  --cluster-domain=cluster.local \\
  --container-runtime=remote \\
  --container-runtime-endpoint=unix:///var/run/cri-containerd.sock \\
  --image-pull-progress-deadline=2m \\
  --kubeconfig=/var/lib/kubelet/kubeconfig \\
  --network-plugin=cni \\
  --pod-cidr=${POD_CIDR[i]} \\
  --register-node=true \\
  --runtime-request-timeout=15m \\
  --tls-cert-file=/var/lib/kubelet/${instance}.pem \\
  --tls-private-key-file=/var/lib/kubelet/${instance}-key.pem \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  scp -i $KEY_PATH -o "StrictHostKeyChecking no" kubelet.service ubuntu@$IP:~/
  ssh -i $KEY_PATH -o "StrictHostKeyChecking no" ubuntu@$IP "sudo mv kube-proxy.kubeconfig /var/lib/kube-proxy/kubeconfig"
  cat > kube-proxy.service <<EOF
[Unit]
Description=Kubernetes Kube Proxy
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-proxy \\
  --cluster-cidr=10.200.0.0/16 \\
  --kubeconfig=/var/lib/kube-proxy/kubeconfig \\
  --proxy-mode=iptables \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  scp -i $KEY_PATH -o "StrictHostKeyChecking no" kube-proxy.service ubuntu@$IP:~/
  ssh -i $KEY_PATH -o "StrictHostKeyChecking no" ubuntu@$IP "sudo mv kubelet.service kube-proxy.service /etc/systemd/system/"
  ssh -i $KEY_PATH -o "StrictHostKeyChecking no" ubuntu@$IP "sudo systemctl daemon-reload"
  ssh -i $KEY_PATH -o "StrictHostKeyChecking no" ubuntu@$IP "sudo systemctl enable containerd cri-containerd kubelet kube-proxy"
  ssh -i $KEY_PATH -o "StrictHostKeyChecking no" ubuntu@$IP "sudo systemctl start containerd cri-containerd kubelet kube-proxy"

done
