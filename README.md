# 🥗 Kaloora — Cloud-Native Nutrition & Fitness Tracker su AWS EKS

**Kaloora** è una piattaforma web distribuita per il tracciamento calorico, nutrizionale e delle attività fisiche. L'architettura è interamente distribuita e ottimizzata per **Amazon Elastic Kubernetes Service (AWS EKS)** seguendo i moderni paradigmi di **Microservizi Disaccoppiati**, **Event-Driven Architecture (EDA)**, **Managed/Serverless Services**, **Infrastructure as Code (Terraform)** e **DevSecOps (CI/CD)**.

---

## 📸 Schemi Architetturali

```
[ Utente / Browser ]
        │
        ▼
[ Amazon CloudFront CDN ] (PriceClass_100, OAC, Security Headers)
   ├── /*         ──► [ Amazon S3 Bucket ] (Frontend SPA Statico: HTML5/CSS3/Vanilla JS)
   └── /api/*     ──► [ AWS Application Load Balancer (ALB) ]
                            │ (Port 80 -> NodePort 30080)
                            ▼
            [ Amazon EKS Managed Cluster (Control Plane Multi-AZ SLA 99.95%) ]
            ┌─────────────────────────────────────────────────────────┐
            │  • EKS Managed Node Group (Auto-Scaling AL2023 Workers) │
            │  • Ingress Nginx Controller (NodePort: 30080)           │
            │  • User Service (Node.js/Express, 2 Repliche, HPA)      │
            │  • Diary Service (Python/Flask/Gunicorn, 2 Repliche, HPA)│
            │  • Analytics Service (Node.js/Express, 2 Repliche, HPA) │
            │  • AWS VPC CNI (IP nativi VPC assegnati ai Pod)         │
            └─────────────────────────────────────────────────────────┘
                    │                │                     │
                    ▼                ▼                     ▼
             [ Amazon RDS ]   [ Amazon DynamoDB ]   [ Amazon SQS + DLQ ]
             (PostgreSQL 15)  (Pay-Per-Request)      (Event-Driven Bus)
             (Encrypted gp3)  (Diari & Alimenti)           │
                                                           ▼
                                                 [ Amazon ElastiCache ]
                                                 (Redis 7 In-Memory Cache)
```

---

## 🏛️ Architettura dei Componenti & Servizi AWS

| Modulo / Servizio | Tecnologia | Servizio AWS / Hosting | Responsabilità & Dettagli |
| :--- | :--- | :--- | :--- |
| **Frontend SPA** | HTML5, CSS3 Glassmorphism, JS ES6+ | **Amazon S3 + CloudFront CDN** | Hosting statico privato con OAC, fallback SPA su `/index.html`, HTTP Security Headers, caching edge a bassa latenza. |
| **Reverse Proxy / Gateway** | AWS ALB + Ingress Nginx | **Application Load Balancer** | Instradamento centralizzato del traffico `/api/*` verso il target group dei worker EKS sulla NodePort `30080`. |
| **Kubernetes Control Plane** | Kubernetes v1.36 | **Amazon EKS Managed Control Plane** | Control Plane gestito da AWS con SLA 99.95% Multi-AZ, backup automatici di etcd e patching senza disservizi. |
| **Kubernetes Data Plane** | AL2023 / containerd | **EKS Managed Node Groups** | Nodi worker gestiti con Auto Scaling Group integrato nell'ALB, aggiornamenti controllati e IAM least privilege. |
| **User Service** | Node.js 20, Express, pg | **Amazon EKS + Amazon RDS** | Autenticazione JWT, profilo utente, calcolo BMR/TDEE con formula Mifflin-St Jeor; persistenza su **PostgreSQL 15 (RDS)** con encryption at-rest (KMS) e in-transit forzata (`rds.force_ssl=1`). |
| **Diary Service** | Python 3.11, Flask, boto3 | **Amazon EKS + Amazon DynamoDB** | Gestione diario giornaliero, pasti, idratazione, ricette e alimenti con validazione input; persistenza NoSQL su **DynamoDB** (Pay-Per-Request + PITR) e pubblicazione eventi su **Amazon SQS**. |
| **Analytics Service** | Node.js 20, Express, @aws-sdk | **Amazon EKS + ElastiCache** | Consumer SQS con long polling ed exponential backoff, calcolo trend nutrizionali settimanali/mensili e caching protetto su **ElastiCache Redis 7 Replication Group** (TLS in-transit + KMS at-rest). |
| **Event Bus & DLQ** | AWS SQS | **Amazon SQS + Dead Letter Queue** | Disaccoppiamento asincrono affidabile degli eventi applicativi con crittografia at-rest gestita (SSE-SQS). |
| **Secrets & Config** | SSM Parameter Store | **AWS Systems Manager** | Archiviazione cifrata dei segreti applicativi (`SecureString`) e generazione dinamica del secret K8s. |
| **Container Registry** | Docker Multi-Stage | **Amazon ECR** | Repository con scansione automatica delle vulnerabilità e **Lifecycle Policy** (conservazione max 10 immagini / scadenza untagged). |
| **Monitoring & Alarms** | CloudWatch Metrics | **Amazon CloudWatch** | Monitoraggio proattivo e allarmi su CPU EKS Node Group, metriche RDS e codici 5XX sull'ALB. |

---

## 📂 Struttura del Repository

```
KalooraEKS/
├── .github/workflows/        # Pipeline CI/CD GitHub Actions (DevSecOps + Build + Deploy su EKS)
│   └── deploy.yml            # Workflow con scansioni SAST (Gitleaks, Semgrep, Checkov)
├── docs/                     # Documentazione tecnica
│   ├── eks_vs_ec2_comparison.md # Analisi comparativa EKS vs EC2 Self-Managed
│   └── openapi.yaml          # Specifica OpenAPI 3.0 dei microservizi REST
├── frontend/                 # Single Page Application Frontend
│   ├── css/                  # Design System Glassmorphism e Dark Mode
│   ├── js/                   # Logica applicativa, client API, routing
│   └── index.html            # Entrypoint WebApp
├── k8s/                      # Manifesti Kubernetes Cloud-Native
│   ├── namespace.yaml        # Namespace 'kaloora', LimitRange e ResourceQuota
│   ├── secret.yaml.example   # Template dei segreti di connessione
│   ├── ecr-cronjob.yaml      # CronJob di rinnovo automatico del token ECR (ogni 6 ore)
│   ├── ingress-nginx.yaml    # Ingress Nginx Controller v1.10.0 con NodePort 30080 dichiarativo
│   ├── network-policy.yaml   # Politiche di isolamento della rete
│   ├── user-service.yaml     # Deployment & Service (NodePort/ClusterIP)
│   ├── diary-service.yaml    # Deployment & Service (NodePort/ClusterIP)
│   ├── analytics-service.yaml# Deployment & Service (NodePort/ClusterIP)
│   ├── hpa-pdb.yaml          # Horizontal Pod Autoscaler & PodDisruptionBudget
│   └── ingress.yaml          # Regole di routing Ingress Nginx per l'ALB
├── services/                 # Microservizi Backend
│   ├── analytics-service/    # Analytics & SQS Consumer (Node.js/Express)
│   ├── diary-service/        # Diario, Ricette con GSI/Redis & DynamoDB/SQS (Python/Flask)
│   └── user-service/         # Autenticazione & RDS PostgreSQL (Node.js/Express)
├── terraform/                # Infrastruttura come Codice (AWS Provider)
│   ├── main.tf               # Providers, Data sources e Local State (Test Environment)
│   ├── vpc.tf                # VPC, Subnet pubbliche e private (Multi-AZ) con tag EKS e Gateway Endpoints
│   ├── security_groups.tf    # Security Groups con regole restrittive (EKS, ALB, Nodi, RDS, Redis)
│   ├── eks.tf                # EKS Cluster, Managed Node Groups, EKS Addons, OIDC Provider
│   ├── iam.tf                # IAM Roles per EKS Cluster e Node Group (Least Privilege)
│   ├── load_balancer.tf      # Application Load Balancer & Target Group (NodePort 30080)
│   ├── managed_services.tf   # RDS Postgres, DynamoDB (con GSI), SQS, ElastiCache, ECR, SSM
│   ├── frontend_cdn.tf       # Bucket S3, CloudFront OAC e Security Headers
│   ├── cloudwatch.tf         # Allarmi CloudWatch per EKS Node Group, RDS e ALB
│   ├── variables.tf          # Parametrizzazione ambiente e credenziali
│   ├── outputs.tf            # Endpoint EKS, comandi kubectl, URI e credenziali
│   └── terraform.tfvars      # Variabili di configurazione
├── deploy-aws.sh             # Script di deploy applicativo end-to-end su AWS EKS
├── LICENSE                   # Licenza MIT
└── README.md                 # Documentazione del progetto
```

---

## 🛠️ Prerequisiti

- **AWS CLI v2** configurata con credenziali dotate di permessi IAM adeguati (`aws configure`).
- **Terraform** (>= 1.5.0).
- **kubectl** (>= 1.28).
- **Docker** installato localmente per la compilazione delle immagini container (opzionale se delegate alla CI/CD).

---

## 🚀 Guida al Deployment su AWS (IaC & Automazione)

Il deployment dell'infrastruttura e dei microservizi si articola in **2 fasi automatizzate**:

```
┌─────────────────────────┐              ┌─────────────────────────┐
│      1. TERRAFORM       │ ───────────► │      2. DEPLOY-AWS      │
│ (Provisioning EKS &     │              │ (Deploy Frontend, ECR & │
│  Managed Services AWS)  │              │  Microservizi via K8s)  │
└─────────────────────────┘              └─────────────────────────┘
```

---

### Passo 1: Provisioning dell'Infrastruttura con Terraform

1. Spostati nella cartella `terraform/`:
   ```bash
   cd terraform
   terraform init
   ```

2. Esegui il deployment delle risorse su AWS:
   ```bash
   terraform apply -auto-approve
   ```

*Terraform creerà la VPC, le subnet Multi-AZ con tag EKS, i Security Group, il Control Plane Amazon EKS, l'EKS Managed Node Group per i Worker, i ruoli IAM, l'ALB, RDS PostgreSQL cifrato, DynamoDB on-demand, SQS con DLQ, ElastiCache Redis, S3, CloudFront OAC e genererà automaticamente `k8s/secret.yaml`.*

---

### Passo 2: Deployment dei Microservizi e Frontend (`deploy-aws.sh`)

Dalla radice del progetto, esegui lo script orchestratore:

```bash
./deploy-aws.sh
```

#### Fasi eseguite dallo script:
1. **Recupero Parametri**: Estrae gli output da Terraform (Nome cluster EKS, Bucket S3, CloudFront URL/DistID, URI ECR).
2. **Configurazione `kubectl`**: Aggiorna il kubeconfig locale (`aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME`).
3. **Deploy Frontend**: Sincronizza i file statici su S3 e richiede l'invalidazione della cache CloudFront.
4. **Build & Push ECR**: Compila e carica le immagini Docker su Amazon ECR.
5. **Deploy K8s**: Applica direttamente al cluster EKS Namespace, Secrets, NetworkPolicies, Ingress Nginx (su NodePort `30080`), User Service, Diary Service, Analytics Service, regole HPA/PDB e popola il database DynamoDB.

Al termine del deployment, l'applicazione sarà accessibile all'URL pubblico di CloudFront:
```
👉 https://dxxxxxxxxxxxx.cloudfront.net
```

---

## 🛡️ Sicurezza & Conformità DevSecOps

- **Amazon EKS Managed Security**:
  - Control Plane gestito da AWS con accesso API privato/pubblico e IAM Authenticator integrato.
  - OIDC Provider configurato per abilitare IAM Roles for Service Accounts (IRSA).
  - Managed Node Group su AMI Amazon Linux 2023 con patching di sicurezza gestito da AWS.
- **Crittografia Completa (At-Rest & In-Transit)**:
  - **RDS PostgreSQL**: Storage cifrato via AWS KMS (`gp3 20GB`), in-transit forzato tramite Parameter Group (`rds.force_ssl = 1`) e connessione pool `pg` con SSL/TLS.
  - **ElastiCache Redis**: Gestito tramite Replication Group con crittografia at-rest KMS, crittografia in-transit (TLSv1.2), autenticazione Redis AUTH (`auth_token`) e connessioni Node.js con `socket: { tls: true }`.
  - **Amazon S3**: Crittografia server-side SSE-S3 (`AES256`), blocco accessi pubblici, policy che nega richieste non-HTTPS (`aws:SecureTransport: "false"`) e accesso riservato a CloudFront OAC con SigV4.
  - **Amazon SQS + DLQ**: Crittografia at-rest abilitata (SSE-SQS) e trasporto su HTTPS.
  - **Amazon EBS**: Crittografia abilitata su tutti i volumi dei nodi EKS.
  - **CloudFront CDN**: Forzatura HTTPS (`redirect-to-https`) su tutti i path, policy Security Headers completa (CSP, HSTS, X-Frame-Options DENY, X-Content-Type-Options nosniff) e header di verifica `X-Origin-Verify` verso l'ALB.
- **Isolamento di Rete & VPC Endpoints**:
  - RDS ed ElastiCache risiedono in Subnet Private Multi-AZ non accessibili da Internet.
  - **Gateway VPC Endpoints** per S3 e DynamoDB per instradamento interno a costo zero.
  - Security Group EKS: porte NodePort `30000-32767` accessibili unicamente dall'ALB Security Group.
- **Hardening dei Container**:
  - Container eseguiti come utente non-root (`UID/GID 10001`).
  - `readOnlyRootFilesystem: true`, `allowPrivilegeEscalation: false` e drop di tutte le Linux capabilities (`drop: ALL`).
- **Pipeline CI/CD DevSecOps**:
  - Scansione secret con **Gitleaks** (bloccante).
  - Scansione statica del codice (SAST) con **Semgrep**.
  - Scansione IaC di Terraform e manifesti Kubernetes con **Checkov**.

---

## 🧹 Teardown dell'Infrastruttura

Per distruggere tutte le risorse allocate su AWS ed azzerare i costi:

```bash
cd terraform
terraform destroy -auto-approve
```

---

## 📄 Licenza

Questo progetto è distribuito sotto licenza **MIT**. Consulta il file [LICENSE](LICENSE) per ulteriori dettagli.