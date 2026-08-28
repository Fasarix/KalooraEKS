#!/bin/bash
set -e

# Change directory to script location
cd "$(dirname "$0")"

echo "=========================================================================="
echo "   [Kaloora EKS] Deploy su Cluster AWS EKS, S3 e CloudFront CDN"
echo "=========================================================================="

# ── FASE 1: Recupero informazioni da Terraform ────────────────────────────────
echo "=== [1/5] Recupero parametri e credenziali da Terraform ==="
cd terraform

CLUSTER_NAME=$(TF_CLI_CONFIG_FILE=/dev/null terraform output -raw eks_cluster_name 2>/dev/null || echo "kaloora-eks-cluster")
AWS_REGION=$(TF_CLI_CONFIG_FILE=/dev/null terraform output -raw aws_region 2>/dev/null || echo "us-east-1")
S3_BUCKET=$(TF_CLI_CONFIG_FILE=/dev/null terraform output -raw s3_frontend_bucket 2>/dev/null || true)
CLOUDFRONT_URL=$(TF_CLI_CONFIG_FILE=/dev/null terraform output -raw cloudfront_domain_name 2>/dev/null || true)
CLOUDFRONT_DIST_ID=$(TF_CLI_CONFIG_FILE=/dev/null terraform output -raw cloudfront_distribution_id 2>/dev/null || true)

USER_ECR=$(TF_CLI_CONFIG_FILE=/dev/null terraform output -json ecr_repository_urls 2>/dev/null | grep -o '"user-service": "[^"]*' | cut -d'"' -f4 || true)
DIARY_ECR=$(TF_CLI_CONFIG_FILE=/dev/null terraform output -json ecr_repository_urls 2>/dev/null | grep -o '"diary-service": "[^"]*' | cut -d'"' -f4 || true)
ANALYTICS_ECR=$(TF_CLI_CONFIG_FILE=/dev/null terraform output -json ecr_repository_urls 2>/dev/null | grep -o '"analytics-service": "[^"]*' | cut -d'"' -f4 || true)

cd ..

# Fallback automatico via AWS CLI se i parametri non sono nel tfstate locale
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text 2>/dev/null || true)
if [ -z "$S3_BUCKET" ] && [ -n "$AWS_ACCOUNT_ID" ]; then
  S3_BUCKET=$(aws s3api list-buckets --query "Buckets[?starts_with(Name, 'kaloora-eks-frontend') || starts_with(Name, 'kaloora-frontend')].Name" --output text 2>/dev/null | awk '{print $1}')
fi
if [ -z "$USER_ECR" ] && [ -n "$AWS_ACCOUNT_ID" ]; then
  USER_ECR="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/kaloora-eks/user-service"
  DIARY_ECR="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/kaloora-eks/diary-service"
  ANALYTICS_ECR="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/kaloora-eks/analytics-service"
fi

echo "  -> EKS Cluster Name: ${CLUSTER_NAME}"
echo "  -> AWS Region: ${AWS_REGION}"
echo "  -> S3 Frontend Bucket: ${S3_BUCKET}"
echo "  -> CloudFront URL: ${CLOUDFRONT_URL}"
echo "  -> CloudFront Dist ID: ${CLOUDFRONT_DIST_ID}"
echo "  -> ECR User Service: ${USER_ECR}"

# ── FASE 2: Configurazione di kubectl per il cluster EKS ──────────────────────
echo ""
echo "=== [2/5] Configurazione credenziali kubectl per Amazon EKS ==="
echo "  -> Aggiornamento kubeconfig per il cluster ${CLUSTER_NAME} in ${AWS_REGION}..."
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"

# ── FASE 3: Deploy Frontend su AWS S3 & CloudFront ────────────────────────────
echo ""
echo "=== [3/5] Deploy del Frontend su S3 e invalidazione CDN ==="
if [ -n "$S3_BUCKET" ]; then
  echo "  -> Sincronizzazione file statici su s3://${S3_BUCKET}..."
  aws s3 sync frontend/ "s3://${S3_BUCKET}/" --exclude "Dockerfile" --exclude "nginx.conf" --delete
  echo "  ✅ Frontend caricato con successo su S3."

  if [ -n "$CLOUDFRONT_DIST_ID" ]; then
    echo "  -> Invalidazione cache CloudFront per la distribuzione ${CLOUDFRONT_DIST_ID}..."
    aws cloudfront create-invalidation --distribution-id "$CLOUDFRONT_DIST_ID" --paths "/*" >/dev/null 2>&1 || true
    echo "  ✅ Invalidazione cache CloudFront richiesta."
  fi
else
  echo "  ⚠️ S3 bucket non configurato, salto deploy frontend."
fi

# ── FASE 4: Build & Push Immagini Docker su ECR (se Docker è presente) ────────
if command -v docker &>/dev/null && [ -n "$USER_ECR" ]; then
  echo ""
  echo "=== [4/5] Build & Push immagini Docker su Amazon ECR ==="
  REGISTRY=$(echo "$USER_ECR" | cut -d'/' -f1)
  echo "  -> Autenticazione con Amazon ECR ($REGISTRY)..."
  aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$REGISTRY" >/dev/null 2>&1 || true
  
  echo "  -> Compilazione & caricamento user-service..."
  docker build --platform linux/amd64 -q -t "${USER_ECR}:v1.0.0" services/user-service/
  docker push -q "${USER_ECR}:v1.0.0"
  
  echo "  -> Compilazione & caricamento diary-service..."
  docker build --platform linux/amd64 -q -t "${DIARY_ECR}:v1.0.0" services/diary-service/
  docker push -q "${DIARY_ECR}:v1.0.0"
  
  echo "  -> Compilazione & caricamento analytics-service..."
  docker build --platform linux/amd64 -q -t "${ANALYTICS_ECR}:v1.0.0" services/analytics-service/
  docker push -q "${ANALYTICS_ECR}:v1.0.0"
  echo "  ✅ Tutte le immagini sono caricate su Amazon ECR."
fi

# ── FASE 5: Applicazione dei Manifesti Kubernetes con kubectl ─────────────────
echo ""
echo "=== [5/5] Applicazione dei manifesti Kubernetes dei Microservizi su EKS ==="

echo "0. Verifica che i nodi Worker dell'EKS Managed Node Group siano connessi e pronti..."
for i in {1..60}; do
  READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready" || echo "0")
  if [ "$READY_NODES" -ge 2 ]; then
    echo "  -> Nodi rilevati in stato Ready: $READY_NODES"
    break
  fi
  echo "  -> In attesa dei nodi Worker EKS... ($READY_NODES/2 pronti, tentativo $i/60)"
  sleep 10
done

echo "1. Applicazione Namespace, LimitRange, Quota e NetworkPolicies..."
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/network-policy.yaml

echo "2. Configurazione credenziali di autenticazione Amazon ECR e CronJob di rinnovo..."
ECR_PASS=$(aws ecr get-login-password --region "$AWS_REGION" 2>/dev/null || echo "")
REGISTRY=$(echo "$USER_ECR" | cut -d'/' -f1)
if [ -n "$ECR_PASS" ] && [ -n "$REGISTRY" ]; then
  kubectl create secret docker-registry ecr-secret -n kaloora \
    --docker-server="$REGISTRY" \
    --docker-username=AWS \
    --docker-password="$ECR_PASS" \
    --dry-run=client -o yaml | kubectl apply -f -
  kubectl patch serviceaccount default -n kaloora -p '{"imagePullSecrets": [{"name": "ecr-secret"}]}' || true
fi
if [ -f k8s/ecr-cronjob.yaml ]; then
  kubectl apply -f k8s/ecr-cronjob.yaml
fi

echo "3. Applicazione Secrets Database, SQS, Redis e parametri AWS..."
if [ -f k8s/secret.yaml ]; then
  kubectl apply -f k8s/secret.yaml
fi

AWS_AK=$(aws configure get aws_access_key_id 2>/dev/null || echo "")
AWS_SK=$(aws configure get aws_secret_access_key 2>/dev/null || echo "")
if [ -n "$AWS_AK" ] && [ -n "$AWS_SK" ]; then
  kubectl set data secret/kaloora-secrets -n kaloora --from-literal=aws-access-key-id="$AWS_AK" --from-literal=aws-secret-access-key="$AWS_SK" || true
fi

if [ -n "$USER_ECR" ]; then
  echo "4. Aggiornamento percorsi immagini ECR nei manifesti..."
  sed -i.bak "s|image: user-service:v1.0.0|image: ${USER_ECR}:v1.0.0|g" k8s/user-service.yaml && rm -f k8s/user-service.yaml.bak || true
  sed -i.bak "s|image: diary-service:v1.0.0|image: ${DIARY_ECR}:v1.0.0|g" k8s/diary-service.yaml && rm -f k8s/diary-service.yaml.bak || true
  sed -i.bak "s|image: analytics-service:v1.0.0|image: ${ANALYTICS_ECR}:v1.0.0|g" k8s/analytics-service.yaml && rm -f k8s/analytics-service.yaml.bak || true
fi

echo "5. Installazione dichiarativa Ingress Nginx Controller (NodePort 30080)..."
kubectl apply -f k8s/ingress-nginx.yaml
kubectl delete ValidatingWebhookConfiguration ingress-nginx-admission --ignore-not-found || true

echo "6. Applicazione Microservizi Backend, HPA/PDB e Ingress..."
kubectl apply -f k8s/user-service.yaml
kubectl apply -f k8s/diary-service.yaml
kubectl apply -f k8s/analytics-service.yaml
kubectl apply -f k8s/hpa-pdb.yaml || true
kubectl apply -f k8s/ingress.yaml

echo "7. Rollout restart per caricare le nuove configurazioni..."
kubectl rollout restart deployment user-service diary-service analytics-service -n kaloora || true
sleep 3

echo "8. Popolamento automatico ricette e alimenti su DynamoDB..."
kubectl rollout status deployment diary-service -n kaloora --timeout=120s || true
POD=$(kubectl get pods -n kaloora -l app=diary-service -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -n "$POD" ]; then
  kubectl exec -n kaloora "$POD" -- env PYTHONPATH=/app python /app/seeds/recipe_seed.py || true
fi

echo "9. Stato dei Pod distribuiti su EKS:"
kubectl get pods -n kaloora -o wide
kubectl get pods -n ingress-nginx

echo ""
echo "=========================================================================="
echo "   ✅ Deployment su Amazon EKS completato con successo!"
echo "   👉 CloudFront URL: ${CLOUDFRONT_URL}"
echo "=========================================================================="
echo ""
