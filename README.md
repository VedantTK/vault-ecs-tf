# Terraform config for ECS Fargate infra + Vault IAM user + Deploy role + vault vm

    terrform fmt
    terraform plan
    terraform apply
    terraform destroy

# Vault configuration

    export VAULT_ADDR="http://34.42.214.187:8200"
    export VAULT_TOKEN="<YOUR_VAULT_SETUP_TOKEN>"   # root or equivalent

    # (A) Enable JWT auth for GitHub Actions OIDC
    vault auth enable jwt
    
    vault write auth/jwt/config \
      oidc_discovery_url="https://token.actions.githubusercontent.com" \
      bound_issuer="https://token.actions.githubusercontent.com"
    
    # Policy allowing ONLY read of the AWS dynamic creds path
    cat > gha-aws-read.hcl <<'EOF'
    path "aws/creds/gha-ecr-ecs" {
      capabilities = ["read"]
    }
    EOF
    
    vault policy write gha-aws-read gha-aws-read.hcl

    vault write auth/jwt/role/github-actions -<<EOF
    {
      "role_type": "jwt",
      "user_claim": "actor",
      "bound_audiences": "vault",
      "bound_claims": {
        "repository": "VedantTK/2048"
      },
      "policies": ["gha-aws-read"],
      "ttl": "15m",
      "max_ttl": "1h"
    }
    EOF

# Configure AWS secrets engine in Vault

    vault secrets enable -path=aws aws

    vault write aws/config/root \
    access_key=$VAULT_AWS_ACCESS_KEY_ID \
    secret_key=$VAULT_AWS_SECRET_ACCESS_KEY \
    region=us-west-2

    vault read aws/config/root

# Create Vault AWS roles (for ECS deploy)

    vault write aws/roles/ecs-deploy-role \
    credential_type=assumed_role \
    role_arns=arn:aws:iam::293088445135:role/vault-cicd-2048-dev-ECR_ECS_DeployRole

    vault read aws/creds/ecs-deploy-role

    # Attach a Vault policy
    cat > ecs-deploy-policy.hcl <<'EOF'
    path "aws/creds/ecs-deploy-role" {
    capabilities = ["read"]
    }
    vault policy write ecs-deploy-policy ecs-deploy-policy.hcl

    vault write auth/jwt/role/github-ecs-deployer \
    role_type=jwt \
    bound_subject="repo:VedantTK/2048:ref:refs/heads/main" \
    bound_audiences="https://vault" \
    user_claim="sub" \
    policies="ecs-deploy" \
    ttl=1h

    vault read auth/jwt/role/github-ecs-deployer





