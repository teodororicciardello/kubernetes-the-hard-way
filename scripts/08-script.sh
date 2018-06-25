#! /bin/bash

## variable for key
KEY_PATH="~/default-key.pem"

for i in 0 1 2; do
  instance=controller-$i
  IP=$(aws ec2 describe-instances --instance-id ${CONTR_ID[i]} --query 'Reservations[].Instances[].PublicIpAddress'| jq .[0] | sed 's/"//g')
  ssh -i $KEY_PATH -o "StrictHostKeyChecking no" ubuntu@$IP "sudo mv ca.pem ca-key.pem kubernetes-key.pem kubernetes.pem service-account-key.pem service-account.pem encryption-config.yaml /var/lib/kubernetes/"
  
  INTERNAL_IP=$(aws ec2 describe-instances --instance-id ${CONTR_ID[i]} --query 'Reservations[].Instances[].PrivateIpAddress'| jq .[0] | sed 's/"//g')
  
  cat > kube-apiserver.service <<EOF
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-apiserver \\
  --advertise-address=${INTERNAL_IP} \\
  --allow-privileged=true \\
  --apiserver-count=3 \\
  --audit-log-maxage=30 \\
  --audit-log-maxbackup=3 \\
  --audit-log-maxsize=100 \\
  --audit-log-path=/var/log/audit.log \\
  --authorization-mode=Node,RBAC \\
  --bind-address=0.0.0.0 \\
  --client-ca-file=/var/lib/kubernetes/ca.pem \\
  --enable-admission-plugins=Initializers,NamespaceLifecycle,NodeRestriction,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota \\
  --enable-swagger-ui=true \\
  --etcd-cafile=/var/lib/kubernetes/ca.pem \\
  --etcd-certfile=/var/lib/kubernetes/kubernetes.pem \\
  --etcd-keyfile=/var/lib/kubernetes/kubernetes-key.pem \\
  --etcd-servers=https://10.240.0.10:2379,https://10.240.0.11:2379,https://10.240.0.12:2379 \\
  --event-ttl=1h \\
  --experimental-encryption-provider-config=/var/lib/kubernetes/encryption-config.yaml \\
  --kubelet-certificate-authority=/var/lib/kubernetes/ca.pem \\
  --kubelet-client-certificate=/var/lib/kubernetes/kubernetes.pem \\
  --kubelet-client-key=/var/lib/kubernetes/kubernetes-key.pem \\
  --kubelet-https=true \\
  --runtime-config=api/all,admissionregistration.k8s.io/v1alpha1=true \\
  --service-account-key-file=/var/lib/kubernetes/service-account.pem \\
  --service-cluster-ip-range=10.32.0.0/24 \\
  --service-node-port-range=30000-32767 \\
  --tls-cert-file=/var/lib/kubernetes/kubernetes.pem \\
  --tls-private-key-file=/var/lib/kubernetes/kubernetes-key.pem \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  scp -i $KEY_PATH -o "StrictHostKeyChecking no" kube-apiserver.service ubuntu@$IP:~/
  ssh -i $KEY_PATH -o "StrictHostKeyChecking no" ubuntu@$IP "sudo mv kube-apiserver.service /etc/systemd/system/"


  ssh -i $KEY_PATH -o "StrictHostKeyChecking no" ubuntu@$IP "sudo mv kube-controller-manager.kubeconfig /var/lib/kubernetes/"

cat > kube-controller-manager.service <<EOF
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-controller-manager \\
  --address=0.0.0.0 \\
  --cluster-cidr=10.200.0.0/16 \\
  --cluster-name=kubernetes \\
  --cluster-signing-cert-file=/var/lib/kubernetes/ca.pem \\
  --cluster-signing-key-file=/var/lib/kubernetes/ca-key.pem \\
  --kubeconfig=/var/lib/kubernetes/kube-controller-manager.kubeconfig \\
  --leader-elect=true \\
  --root-ca-file=/var/lib/kubernetes/ca.pem \\
  --service-account-private-key-file=/var/lib/kubernetes/service-account-key.pem \\
  --service-cluster-ip-range=10.32.0.0/24 \\
  --use-service-account-credentials=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  scp -i $KEY_PATH -o "StrictHostKeyChecking no" kube-controller-manager.service ubuntu@$IP:~/
  ssh -i $KEY_PATH -o "StrictHostKeyChecking no" ubuntu@$IP "sudo mv kube-controller-manager.service /etc/systemd/system/"


  ssh -i $KEY_PATH -o "StrictHostKeyChecking no" ubuntu@$IP "sudo mv kube-scheduler.kubeconfig /var/lib/kubernetes/"

cat > kube-scheduler.yaml <<EOF 
apiVersion: componentconfig/v1alpha1
kind: KubeSchedulerConfiguration
clientConnection:
  kubeconfig: "/var/lib/kubernetes/kube-scheduler.kubeconfig"
leaderElection:
  leaderElect: true
EOF

  scp -i $KEY_PATH -o "StrictHostKeyChecking no" kube-scheduler.yaml ubuntu@$IP:~/
  ssh -i $KEY_PATH -o "StrictHostKeyChecking no" ubuntu@$IP "sudo mv kube-scheduler.yaml /etc/kubernetes/config/"

  cat > kube-scheduler.service <<EOF
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-scheduler \\
  --config=/etc/kubernetes/config/kube-scheduler.yaml \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  
  scp -i $KEY_PATH -o "StrictHostKeyChecking no" kube-scheduler.service ubuntu@$IP:~/
  ssh -i $KEY_PATH -o "StrictHostKeyChecking no" ubuntu@$IP "sudo mv kube-scheduler.service /etc/systemd/system/"

  ssh -i $KEY_PATH -o "StrictHostKeyChecking no" ubuntu@$IP "sudo systemctl daemon-reload"
  ssh -i $KEY_PATH -o "StrictHostKeyChecking no" ubuntu@$IP "sudo systemctl enable kube-apiserver kube-controller-manager kube-scheduler"
  ssh -i $KEY_PATH -o "StrictHostKeyChecking no" ubuntu@$IP "sudo systemctl start kube-apiserver kube-controller-manager kube-scheduler"

done

## sleep 10 sec to init API server
sleep 10 

i=0
  instance=controller-$i
  IP=$(aws ec2 describe-instances --instance-id ${CONTR_ID[i]} --query 'Reservations[].Instances[].PublicIpAddress'| jq .[0] | sed 's/"//g')

  cat > clusterrole.yaml <<EOF 
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRole
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: system:kube-apiserver-to-kubelet
rules:
  - apiGroups:
      - ""
    resources:
      - nodes/proxy
      - nodes/stats
      - nodes/log
      - nodes/spec
      - nodes/metrics
    verbs:
      - "*"
EOF

cat > clusterrolebinding.yaml <<EOF 
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: system:kube-apiserver
  namespace: ""
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:kube-apiserver-to-kubelet
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: kubernetes
EOF

scp -i $KEY_PATH -o "StrictHostKeyChecking no" clusterrole.yaml clusterrolebinding.yaml ubuntu@$IP:~/
ssh -i $KEY_PATH -o "StrictHostKeyChecking no" ubuntu@$IP "kubectl apply --kubeconfig admin.kubeconfig -f clusterrole.yaml" 
ssh -i $KEY_PATH -o "StrictHostKeyChecking no" ubuntu@$IP "kubectl apply --kubeconfig admin.kubeconfig -f clusterrolebinding.yaml" 


