
# AWS EKS — 2048 Game Deployment

This repository contains a minimal guide to create an Amazon EKS cluster (Fargate), deploy the 2048 example application, and expose it to the internet using the AWS ALB (Application Load Balancer) Controller.

The document below provides prerequisites, step-by-step commands (PowerShell-friendly), placeholders you must replace, and basic troubleshooting and cleanup commands.

## Prerequisites

- AWS account with appropriate permissions to create EKS clusters, IAM policies/roles, VPC resources and load balancers.
- Install the following tools on your machine and ensure they're in PATH:
  - `aws` (AWS CLI v2)
  - `eksctl`
  - `kubectl`
  - `helm`
  - `curl` (or `Invoke-WebRequest`/`Invoke-RestMethod` on PowerShell)

## Assumptions / placeholders

Replace the variables below before running commands:

- `$CLUSTER_NAME` — e.g. `eks-cluster-for-gameboy`
- `$REGION` — e.g. `ap-south-1`
- `<AWS_ACCOUNT_ID>` — your AWS account id
- `$VPC_ID` — id of the VPC where EKS runs (used by helm install)

Example values used in this README:

- CLUSTER_NAME: `eks-cluster-for-gameboy`
- REGION: `ap-south-1`

## Quick overview

1. Create EKS cluster (Fargate).
2. Create a Fargate profile for the `game-2048` namespace.
3. Deploy the 2048 application manifest (Deployment, Service, Ingress).
4. Associate IAM OIDC provider for the cluster.
5. Install the AWS Load Balancer Controller (create IAM policy/role + helm install).
6. Get the ALB DNS and open the game in your browser.
7. Cleanup: delete the EKS cluster.

## Detailed steps (PowerShell examples)

Set variables you will reuse (PowerShell):

```powershell
$CLUSTER_NAME = "eks-cluster-for-gameboy"
$REGION = "ap-south-1"
$AWS_ACCOUNT_ID = "<your-aws-account-id>"
$VPC_ID = "<your-vpc-id>"
```

### 1. Create EKS cluster (Fargate)

```powershell
eksctl create cluster --name $CLUSTER_NAME --region $REGION --fargate
aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION
```

This creates an EKS control plane and configures your local kubeconfig.

### 2. Create a Fargate profile for the application namespace

```powershell
eksctl create fargateprofile \
  --cluster $CLUSTER_NAME \
  --region $REGION \
  --name alb-sample-app \
  --namespace game-2048
```

### 3. Deploy the 2048 app (Deployment, Service, Ingress)

Apply the example manifest published by the AWS LB controller repo:

```powershell
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.5.4/docs/examples/2048/2048_full.yaml
```

Verify the pods & resources:

```powershell
kubectl get all -n game-2048
kubectl get ingress -n game-2048
```

### 4. Associate IAM OIDC provider

This is required so EKS service accounts can be mapped to IAM roles.
```powershell
eksctl utils associate-iam-oidc-provider --cluster eks-cluster-for-gameboy --approve
```

### 5. Install AWS Load Balancer Controller (ALB Controller)

5.1 Download the IAM policy JSON (version used here: v2.11.0)

```powershell
curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.11.0/docs/install/iam_policy.json
```

If you prefer PowerShell-native download:

```powershell
Invoke-WebRequest -Uri https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.11.0/docs/install/iam_policy.json -OutFile iam_policy.json
```

5.2 Create the IAM policy in AWS

```powershell
aws iam create-policy --policy-name AWSLoadBalancerControllerIAMPolicy --policy-document file://iam_policy.json
```

Copy the returned policy ARN or use the predictable ARN:
`arn:aws:iam::$AWS_ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy`

5.3 Create a Kubernetes service account with the IAM policy attached

```powershell
eksctl create iamserviceaccount \
  --cluster $CLUSTER_NAME \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --attach-policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy \
  --approve
```

5.4 Install the controller via Helm

```powershell
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system `
  --set clusterName=$CLUSTER_NAME `
  --set serviceAccount.create=false `
  --set serviceAccount.name=aws-load-balancer-controller `
  --set region=$REGION `
  --set vpcId=$VPC_ID

kubectl get deployment -n kube-system aws-load-balancer-controller
```

Note: adjust the chart version or values if your environment requires a specific controller version.

### 6. Find the ALB DNS and open the app

After the Ingress is reconciled by the controller, an ALB will be created.

```powershell
kubectl -n game-2048 get ingress
```

The `ADDRESS` or `HOSTS` column will contain the ALB hostname (DNS). Copy that and open in your browser to access the 2048 game.

You can also use the AWS Console (EC2 > Load Balancers) or the AWS CLI to describe load balancers.

### 7. Cleanup

To remove the entire cluster and associated resources (this also removes ALBs and other AWS resources created by EKS):

```powershell
eksctl delete cluster --name $CLUSTER_NAME --region $REGION
```

If you created the IAM policy manually and want to remove it:

```powershell
aws iam delete-policy --policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy
```
OR, use below script to clean-up the entire project-
Save this as cleanup-eks-2048.sh and run in Git Bash:
How to use:

Replace <YOUR_AWS_ACCOUNT_ID> with your actual AWS account ID in IAM_POLICY_ARN.

Make the script executable:
```powershell
chmod +x cleanup-eks-2048.sh

```
Run
```powershell
./cleanup-eks-2048.sh


```
## Troubleshooting

- If the ALB isn't created, check the ALB controller logs:

```powershell
kubectl logs -n kube-system deployment/aws-load-balancer-controller
```

- If you see permission errors, make sure the OIDC provider is associated and the service account has the policy attached.
- If the manifest references an API version incompatible with your controller, try using a manifest that matches your controller version.

## Notes and recommendations

- Keep controller and manifest versions aligned when possible.
- For production, tighten IAM policies, enable team guardrails, and use private subnets with public ALB if needed.

## License

This README is provided under the MIT License.

