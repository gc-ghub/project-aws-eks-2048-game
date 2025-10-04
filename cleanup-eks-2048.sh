#!/bin/bash

# ------------------------------
# Cleanup script for 2048 EKS game
# ------------------------------

CLUSTER_NAME="eks-cluster-for-gameboy"
REGION="ap-south-1"
NAMESPACE="game-2048"
IAM_ROLE_NAME="AmazonEKSLoadBalancerControllerRole"
IAM_POLICY_ARN="arn:aws:iam::<YOUR_AWS_ACCOUNT_ID>:policy/AWSLoadBalancerControllerIAMPolicy"

echo "Step 1: Deleting all ingresses in namespace $NAMESPACE..."
kubectl delete ingress --all -n $NAMESPACE

echo "Step 2: Deleting all services in namespace $NAMESPACE..."
kubectl delete svc --all -n $NAMESPACE

echo "Step 3: Waiting for ALBs to be deleted..."
sleep 30  # initial wait

# Optional: check ALB deletion in a loop
ALB_COUNT=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?contains(LoadBalancerName, 'k8s')].LoadBalancerName" --region $REGION --output text)
while [ -n "$ALB_COUNT" ]; do
    echo "Waiting for ALBs to be deleted..."
    sleep 20
    ALB_COUNT=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?contains(LoadBalancerName, 'k8s')].LoadBalancerName" --region $REGION --output text)
done
echo "All ALBs are deleted."

echo "Step 4: Deleting the EKS cluster $CLUSTER_NAME..."
eksctl delete cluster --name $CLUSTER_NAME --region $REGION

echo "Step 5: Deleting IAM Role and Policy (optional)..."
aws iam delete-role --role-name $IAM_ROLE_NAME
aws iam delete-policy --policy-arn $IAM_POLICY_ARN

echo "Cleanup complete! 🎉"
