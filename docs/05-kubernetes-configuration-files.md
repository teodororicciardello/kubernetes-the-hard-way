# Generating Kubernetes Configuration Files for Authentication

In this lab you will generate [Kubernetes configuration files](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/), also known as kubeconfigs, which enable Kubernetes clients to locate and authenticate to the Kubernetes API Servers.

## Client Authentication Configs

In this section you will generate kubeconfig files for the `kubelet` and `kube-proxy` clients.

> The `scheduler` and `controller manager` access the Kubernetes API Server locally over an insecure API port which does not require authentication. The Kubernetes API Server's insecure port is only enabled for local access.

### Kubernetes Public Address

Each kubeconfig requires a Kubernetes API Server to connect to. To support high availability the address assigned to the external load balancer fronting the Kubernetes API Servers will be used.

### The kubelet Kubernetes Configuration File

When generating kubeconfig files for Kubelets the client certificate matching the Kubelet's node name must be used. This will ensure Kubelets are properly authorized by the Kubernetes [Node Authorizer](https://kubernetes.io/docs/admin/authorization/node/).

Generate a kubeconfig file for each worker node:

```
for i in 0 1 2; do
  instance=ip-10-240-0-2$i
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server=https://${KUBERNETES_PUBLIC_ADDRESS}:6443 \
    --kubeconfig=${instance}.kubeconfig

  kubectl config set-credentials system:node:${instance} \
    --client-certificate=${instance}.pem \
    --client-key=${instance}-key.pem \
    --embed-certs=true \
    --kubeconfig=${instance}.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:node:${instance} \
    --kubeconfig=${instance}.kubeconfig

  kubectl config use-context default --kubeconfig=${instance}.kubeconfig
done
```

Results:

```
ip-10-240-0-20.kubeconfig
ip-10-240-0-21.kubeconfig
ip-10-240-0-22.kubeconfig
```

### The kube-proxy Kubernetes Configuration File

Generate a kubeconfig file for the `kube-proxy` service:

```
kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=ca.pem \
  --embed-certs=true \
  --server=https://${KUBERNETES_PUBLIC_ADDRESS}:6443 \
  --kubeconfig=kube-proxy.kubeconfig
```

```
kubectl config set-credentials kube-proxy \
  --client-certificate=kube-proxy.pem \
  --client-key=kube-proxy-key.pem \
  --embed-certs=true \
  --kubeconfig=kube-proxy.kubeconfig
```

```
kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=kube-proxy \
  --kubeconfig=kube-proxy.kubeconfig
```

```
kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig
```

## Distribute the Kubernetes Configuration Files

Copy the appropriate `kubelet` and `kube-proxy` kubeconfig files to each worker instance:

```
for instance in 0 1 2; do
  instance=ip-10-240-0-2$i
  IP=$(aws ec2 describe-instances --instance-id ${WORK_ID[i]} \
    --query 'Reservations[].Instances[].PublicIpAddress'\
    | jq .[0] | sed 's/"//g')
  scp -i $KEY_PATH -o "StrictHostKeyChecking no" ${instance}.kubeconfig kube-proxy.kubeconfig ubuntu@$IP:~/
done
```

Next: [Generating the Data Encryption Config and Key](06-data-encryption-keys.md)
