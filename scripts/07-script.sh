#! /bin/bash

## variables for key
KEY_PATH="~/default-key.pem"

for i in 0 1 2; do
  instance=controller-$i
  IP=$(aws ec2 describe-instances --instance-id ${CONTR_ID[i]} --query 'Reservations[].Instances[].PublicIpAddress'| jq .[0] | sed 's/"//g')
  ssh -i $KEY_PATH -o "StrictHostKeyChecking no" ubuntu@$IP "sudo cp ca.pem kubernetes-key.pem kubernetes.pem /etc/etcd/"
  
  # modified to support aws 
  ETCD_NAME=$instance
  INTERNAL_IP=$(aws ec2 describe-instances --instance-id ${CONTR_ID[i]} --query 'Reservations[].Instances[].PrivateIpAddress'| jq .[0] | sed 's/"//g')
  cat > etcd.service <<EOF
[Unit]
Description=etcd
Documentation=https://github.com/coreos

[Service]
ExecStart=/usr/local/bin/etcd \\
  --name ${ETCD_NAME} \\
  --cert-file=/etc/etcd/kubernetes.pem \\
  --key-file=/etc/etcd/kubernetes-key.pem \\
  --peer-cert-file=/etc/etcd/kubernetes.pem \\
  --peer-key-file=/etc/etcd/kubernetes-key.pem \\
  --trusted-ca-file=/etc/etcd/ca.pem \\
  --peer-trusted-ca-file=/etc/etcd/ca.pem \\
  --peer-client-cert-auth \\
  --client-cert-auth \\
  --initial-advertise-peer-urls https://${INTERNAL_IP}:2380 \\
  --listen-peer-urls https://${INTERNAL_IP}:2380 \\
  --listen-client-urls https://${INTERNAL_IP}:2379,https://127.0.0.1:2379 \\
  --advertise-client-urls https://${INTERNAL_IP}:2379 \\
  --initial-cluster-token etcd-cluster-0 \\
  --initial-cluster controller-0=https://10.240.0.10:2380,controller-1=https://10.240.0.11:2380,controller-2=https://10.240.0.12:2380 \\
  --initial-cluster-state new \\
  --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  scp -i $KEY_PATH -o "StrictHostKeyChecking no" etcd.service ubuntu@$IP:~/
  ssh -i $KEY_PATH -o "StrictHostKeyChecking no" ubuntu@$IP "sudo mv etcd.service /etc/systemd/system/"
  ssh -i $KEY_PATH -o "StrictHostKeyChecking no" ubuntu@$IP "sudo systemctl daemon-reload"
  ssh -i $KEY_PATH -o "StrictHostKeyChecking no" ubuntu@$IP "sudo systemctl enable etcd"
  ssh -i $KEY_PATH -o "StrictHostKeyChecking no" ubuntu@$IP "sudo systemctl start etcd"
  
done
