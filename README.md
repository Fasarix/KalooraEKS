# Guida Operativa Passo-Passo: KalooraEKS (Managed Kubernetes Cluster con AWS EKS)

## 1. Obiettivo dell'Infrastruttura
Questa guida descrive la procedura operativa per effettuare il provisioning completo, la configurazione e il rilascio dell'applicazione Kaloora sull'infrastruttura **`KalooraEKS`**.
In questa variante, il Control Plane di Kubernetes è interamente gestito da AWS tramite **Amazon Elastic Kubernetes Service (EKS)** con alta disponibilità multi-AZ garantita, nodi di calcolo in Managed Node Groups, networking pod nativo via AWS VPC CNI e federazione delle identità IAM tramite IRSA (IAM Roles for Service Accounts).

---

## 2. Prerequisiti di Sistema
Prima di avviare il deployment, verificare la presenza dei seguenti requisiti sulla macchina locale:

1. **AWS CLI v2**: configurata con permessi amministrativi per la creazione di cluster EKS, ruoli IAM, VPC e risorse correlate:
   ```bash
   aws configure
   ```
2. **Terraform** ($\ge 1.5.0$): per il provisioning dell'infrastruttura EKS e dei servizi collegati.
3. **kubectl** ($\ge 1.30$): per l'interazione con il cluster Kubernetes.
4. **Docker**: attivo localmente per la compilazione e il push delle immagini su Amazon ECR.

---

## 3. Fase 1: Provisioning del Cluster EKS con Terraform

1. Entrare nella cartella Terraform del repository `KalooraEKS`:
   ```bash
   cd KalooraEKS/terraform
   ```

2. Inizializzare Terraform:
   ```bash
   terraform init
   ```

3. Eseguire l'applicazione del piano di provisioning:
   ```bash
   terraform apply -auto-approve
   ```

   **Cosa fa questa fase:**
   - Crea la VPC con subnet pubbliche e private distribuite su due Availability Zone.
   - Crea il cluster **Amazon EKS** con endpoint sia pubblici che privati abilitati.
   - Configura il provider OpenID Connect (OIDC) per abilitare le policy IRSA.
   - Crea l'**EKS Managed Node Group** (2 istanze worker distribuite nelle AZ, con Launch Template e conformità IMDSv2).
   - Crea l'Application Load Balancer (ALB) e associa dinamicamente l'Auto Scaling Group dei nodi EKS al Target Group dell'ALB.
   - Istanzia i servizi gestiti AWS (RDS PostgreSQL, DynamoDB On-Demand, SQS + DLQ, ElastiCache).
   - Crea il bucket S3 e la distribuzione CloudFront con Origin Access Control (OAC) e header `X-Origin-Verify`.
   - Genera i repository Amazon ECR per ciascun microservizio.

---

## 4. Fase 2: Configurazione di kubectl per il Cluster EKS

Al termine del comando `terraform apply`, è necessario aggiornare il file di configurazione `~/.kube/config` locale per consentire a `kubectl` di autenticarsi sul cluster EKS:

1. Eseguire il comando AWS CLI per aggiornare la configurazione:
   ```bash
   aws eks update-kubeconfig --region us-east-1 --name kaloora-eks-cluster
   ```

2. Verificare che il cluster risponda e che i nodi worker siano visibili:
   ```bash
   kubectl get nodes
   ```
   *(I nodi passeranno allo stato `Ready` entro 1-2 minuti dall'avvio del cluster).*

---

## 5. Fase 3: Deployment dei Microservizi e Frontend

1. Tornare nella cartella principale di `KalooraEKS`:
   ```bash
   cd ..
   ```

2. Eseguire lo script di deployment:
   ```bash
   ./deploy-aws.sh
   ```

   **Sequenza di operazioni eseguite dallo script:**
   1. **Estrazione Parametri**: Recupera automaticamente il nome del cluster, la regione, i bucket S3 e gli URL dei registri ECR da Terraform.
   2. **Configurazione kubectl**: Riconferma l'aggancio a EKS tramite `aws eks update-kubeconfig`.
   3. **Deploy Frontend su S3 & CloudFront**: Sincronizza i file statici sul bucket S3 e richiede l'invalidazione della cache globale della CDN.
   4. **Build & Push Immagini Docker**: Compila le immagini per piattaforma `linux/amd64`, effettua il login al registry ECR ed esegue il push di `user-service`, `diary-service` e `analytics-service`.
   5. **Applicazione Manifesti Kubernetes**:
      - Attende che almeno 2 nodi worker siano in stato `Ready`.
      - Crea il namespace `kaloora` e applica i segreti generati da Terraform.
      - Applica il CronJob per il rinnovo periodico del token ECR.
      - Distribuisce i microservizi con i rispettivi Service e PodDisruptionBudget.
      - Installa il controller Ingress Nginx e configura la risorsa Ingress (in ascolto su NodePort 30080 per ricevere il traffico proveniente dall'ALB).
      - Esegue il seeding iniziale degli alimenti e delle ricette nel database DynamoDB.

---

## 6. Fase 4: Validazione Funzionale e Test degli Endpoint

Al termine dello script di deploy, verrà mostrato l'URL pubblico di CloudFront (es. `https://d2xxxxxxxxxxxx.cloudfront.net`).

1. **Test di Connettività e Health Check:**
   ```bash
   curl -I https://<CLOUDFRONT_DOMAIN>/healthz
   # Risposta attesa: HTTP/2 200 OK
   ```

2. **Accesso all'Applicazione via Browser:**
   - Navigare all'indirizzo `https://<CLOUDFRONT_DOMAIN>`.
   - Registrare un nuovo utente, accedere alla dashboard e inserire un pasto nel diario.
   - Verificare che il calcolo metabolico e le aggregazioni nutrizionali vengano calcolati e aggiornati istantaneamente.

3. **Verifica dello Stato dei Pod nel Cluster:**
   ```bash
   kubectl get pods -n kaloora -o wide
   kubectl get ingress -n kaloora
   ```

---

## 7. Fase 5: Procedura di Teardown Completo

Per disallocare tutte le risorse ed eliminare qualsiasi costo di mantenimento del cluster EKS e dei servizi gestiti:

1. Posizionarsi nella cartella Terraform:
   ```bash
   cd KalooraEKS/terraform
   ```

2. Eseguire la distruzione automatizzata:
   ```bash
   terraform destroy -auto-approve
   ```
