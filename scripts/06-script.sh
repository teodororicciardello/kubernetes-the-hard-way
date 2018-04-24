#! /bin/bash

## variables for key

KEY_PATH="~/default-key.pem"

ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)

cat > encryption-config.yaml <<EOF
kind: EncryptionConfig
apiVersion: v1
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${ENCRYPTION_KEY}
      - identity: {}
EOF

for i in 0 1 2; do
  instance=controller-$i
  IP=$(aws ec2 describe-instances --instance-id ${CONTR_ID[i]} --query 'Reservations[].Instances[].PublicIpAddress'| jq .[0] | sed 's/"//g')
  scp -i $KEY_PATH -o "StrictHostKeyChecking no"  encryption-config.yaml ubuntu@$IP:~/
done
