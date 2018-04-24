#! /bin/bash

##variables for key

KEY_PATH="~/default-key.pem"


## moved up from kthw original 

cat > kubernetes-csr.json <<EOF
{
  "CN": "kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "Kubernetes",
      "OU": "Kubernetes The Hard Way",
      "ST": "Oregon"
    }
  ]
}
EOF

## workaround for missing load balancer (TODO)
KUBERNETES_PUBLIC_ADDRESS=$(aws ec2 describe-instances --instance-id ${CONTR_ID[0]} --query 'Reservations[].Instances[].PublicIpAddress'| jq .[0] | sed 's/"//g')

cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -hostname=10.32.0.1,10.240.0.10,10.240.0.11,10.240.0.12,${KUBERNETES_PUBLIC_ADDRESS},127.0.0.1,kubernetes.default \
  -profile=kubernetes \
  kubernetes-csr.json | cfssljson -bare kubernetes

## EXECUTE AFTER VMs CREATED
### modified to support aws 
for i in 0 1 2; do
instance=ip-10-240-0-2$i
cat > ${instance}-csr.json <<EOF
{
  "CN": "system:node:${instance}",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "system:nodes",
      "OU": "Kubernetes The Hard Way",
      "ST": "Oregon"
    }
  ]
}
EOF
# get ip for ec-2 instance 
EXTERNAL_IP=$(aws ec2 describe-instances --instance-id ${WORK_ID[i]} --query 'Reservations[].Instances[].PublicIpAddress'| jq .[0])

# get ip for ec-2 instance
INTERNAL_IP=$(aws ec2 describe-instances --instance-id ${WORK_ID[i]} --query 'Reservations[].Instances[].PrivateIpAddress' | jq .[0])

cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -hostname=${instance},${EXTERNAL_IP},${INTERNAL_IP} \
  -profile=kubernetes \
  ${instance}-csr.json | cfssljson -bare ${instance}
done

### modified to support aws 
for i in 0 1 2; do
instance=ip-10-240-0-2$i
  IP=$(aws ec2 describe-instances --instance-id ${WORK_ID[i]} --query 'Reservations[].Instances[].PublicIpAddress'| jq .[0] | sed 's/"//g')
  scp -i $KEY_PATH -o "StrictHostKeyChecking no" ca.pem ${instance}-key.pem ${instance}.pem ubuntu@$IP:~/
done

for i in 0 1 2; do
  instance=controller-$i
  IP=$(aws ec2 describe-instances --instance-id ${CONTR_ID[i]} --query 'Reservations[].Instances[].PublicIpAddress'| jq .[0] | sed 's/"//g')
  scp -i $KEY_PATH -o "StrictHostKeyChecking no" ca.pem ca-key.pem kubernetes-key.pem kubernetes.pem ubuntu@$IP:~/
done


  
