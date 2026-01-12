#!/bin/bash
set -e

API_URL="http://localhost:8000"
USERNAME="admin"
PASSWORD="testpass"

echo "Creating Vault EDA activation in EDA Server..."

# Step 0: Create organization if needed
echo "0. Checking for organization..."
ORG_RESPONSE=$(curl -s -u ${USERNAME}:${PASSWORD} "${API_URL}/api/eda/v1/organizations/")
ORG_ID=$(echo ${ORG_RESPONSE} | python3 -c "import sys, json; results = json.load(sys.stdin).get('results', []); print(results[0]['id'] if results else '')" 2>/dev/null || echo "")

if [ -z "$ORG_ID" ]; then
  echo "   Creating default organization..."
  ORG_CREATE=$(curl -s -u ${USERNAME}:${PASSWORD} \
    -X POST "${API_URL}/api/eda/v1/organizations/" \
    -H "Content-Type: application/json" \
    -d '{
      "name": "Default",
      "description": "Default organization"
    }')
  ORG_ID=$(echo ${ORG_CREATE} | python3 -c "import sys, json; print(json.load(sys.stdin).get('id', ''))" 2>/dev/null || echo "")
  
  if [ -z "$ORG_ID" ]; then
    echo "Error creating organization. Response:"
    echo ${ORG_CREATE} | python3 -m json.tool
    exit 1
  fi
fi

echo "   Organization ID: ${ORG_ID}"

# Step 1: Check for existing project or create one
echo "1. Checking for existing project..."
PROJECT_LIST=$(curl -s -u ${USERNAME}:${PASSWORD} "${API_URL}/api/eda/v1/projects/?name=Vault+EDA+Delivery")
PROJECT_ID=$(echo ${PROJECT_LIST} | python3 -c "import sys, json; results = json.load(sys.stdin).get('results', []); print(results[0]['id'] if results else '')" 2>/dev/null || echo "")

if [ -z "$PROJECT_ID" ]; then
  echo "   Creating project..."
  PROJECT_RESPONSE=$(curl -s -u ${USERNAME}:${PASSWORD} \
    -X POST "${API_URL}/api/eda/v1/projects/" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"Vault EDA Delivery\",
      \"description\": \"HashiCorp Vault event-driven automation\",
      \"url\": \"https://github.com/gitrgoliveira/vault-eda-delivery.git\",
      \"scm_type\": \"git\",
      \"organization_id\": ${ORG_ID}
    }")

  PROJECT_ID=$(echo ${PROJECT_RESPONSE} | python3 -c "import sys, json; print(json.load(sys.stdin).get('id', ''))" 2>/dev/null || echo "")

  if [ -z "$PROJECT_ID" ]; then
    echo "Error creating project. Response:"
    echo ${PROJECT_RESPONSE} | python3 -m json.tool
    exit 1
  fi
  echo "   Project created with ID: ${PROJECT_ID}"
else
  echo "   Using existing project with ID: ${PROJECT_ID}"
fi

# Wait for project sync
echo "2. Waiting for project to sync..."
sleep 5

# Get rulebook from project
echo "   Getting rulebooks from project..."
RULEBOOK_RESPONSE=$(curl -s -u ${USERNAME}:${PASSWORD} "${API_URL}/api/eda/v1/rulebooks/?project_id=${PROJECT_ID}")
RULEBOOK_ID=$(echo ${RULEBOOK_RESPONSE} | python3 -c "import sys, json; results = json.load(sys.stdin).get('results', []); print(next((r['id'] for r in results if 'vault-eda-rulebook' in r.get('name', '').lower()), ''))" 2>/dev/null || echo "")

if [ -z "$RULEBOOK_ID" ]; then
  echo "   Error: Could not find vault-eda-rulebook.yaml in project."
  echo "   Available rulebooks:"
  echo ${RULEBOOK_RESPONSE} | python3 -c "import sys, json; results = json.load(sys.stdin).get('results', []); [print(f\"     - {r['name']} (id: {r['id']})\") for r in results]" 2>/dev/null || echo "     None found"
  echo ""
  echo "   The project may still be syncing. Wait a moment and try again."
  exit 1
fi

echo "   Rulebook ID: ${RULEBOOK_ID}"

# Step 1.5: Create Vault Event Stream credential type
echo "2.5. Checking for Vault Event Stream credential type..."
CRED_TYPE_LIST=$(curl -s -u ${USERNAME}:${PASSWORD} "${API_URL}/api/eda/v1/credential-types/?name=HashiCorp+Vault+Event+Stream+Credential")
CRED_TYPE_ID=$(echo ${CRED_TYPE_LIST} | python3 -c "import sys, json; results = json.load(sys.stdin).get('results', []); print(results[0]['id'] if results else '')" 2>/dev/null || echo "")

if [ -z "$CRED_TYPE_ID" ]; then
  echo "   Creating Vault Event Stream credential type..."
  CRED_TYPE_CREATE=$(curl -s -u ${USERNAME}:${PASSWORD} \
    -X POST "${API_URL}/api/eda/v1/credential-types/" \
    -H "Content-Type: application/json" \
    -d '{
      "name": "HashiCorp Vault Event Stream Credential",
      "description": "Credential type for connecting to HashiCorp Vault event streams. Provides VAULT_ADDR and VAULT_TOKEN environment variables for vault_events source plugin.",
      "inputs": {
        "fields": [
          {
            "id": "vault_addr",
            "label": "Vault Address",
            "type": "string",
            "help_text": "The URL of the Vault server (e.g., http://127.0.0.1:8200)"
          },
          {
            "id": "vault_token",
            "label": "Vault Token",
            "type": "string",
            "secret": true,
            "help_text": "Authentication token for Vault with permissions to subscribe to events"
          }
        ],
        "required": ["vault_addr", "vault_token"]
      },
      "injectors": {
        "env": {
          "VAULT_ADDR": "{{ vault_addr }}",
          "VAULT_TOKEN": "{{ vault_token }}"
        }
      }
    }')
  CRED_TYPE_ID=$(echo ${CRED_TYPE_CREATE} | python3 -c "import sys, json; print(json.load(sys.stdin).get('id', ''))" 2>/dev/null || echo "")
  
  if [ -z "$CRED_TYPE_ID" ]; then
    echo "   Note: Could not create credential type. Response:"
    echo ${CRED_TYPE_CREATE} | python3 -m json.tool 2>/dev/null || echo ${CRED_TYPE_CREATE}
  else
    echo "   Credential type created with ID: ${CRED_TYPE_ID}"
  fi
else
  echo "   Using existing credential type with ID: ${CRED_TYPE_ID}"
fi

# Step 1.6: Create Vault Event Stream credential using the credential type
if [ ! -z "$CRED_TYPE_ID" ]; then
  echo "2.6. Checking for Vault Event Stream credential..."
  CRED_LIST=$(curl -s -u ${USERNAME}:${PASSWORD} "${API_URL}/api/eda/v1/eda-credentials/?name=Vault+Event+Stream+Credentials")
  CRED_ID=$(echo ${CRED_LIST} | python3 -c "import sys, json; results = json.load(sys.stdin).get('results', []); print(results[0]['id'] if results else '')" 2>/dev/null || echo "")

  if [ -z "$CRED_ID" ]; then
    echo "   Creating Vault Event Stream credential..."
    CRED_CREATE=$(curl -s -u ${USERNAME}:${PASSWORD} \
      -X POST "${API_URL}/api/eda/v1/eda-credentials/" \
      -H "Content-Type: application/json" \
      -d "{
        \"name\": \"Vault Event Stream Credentials\",
        \"description\": \"Credentials for Vault event stream connection\",
        \"credential_type_id\": ${CRED_TYPE_ID},
        \"organization_id\": ${ORG_ID},
        \"inputs\": {
          \"vault_addr\": \"${VAULT_ADDR:-http://host.docker.internal:8200}\",
          \"vault_token\": \"${VAULT_TOKEN:-myroot}\"
        }
      }")
    CRED_ID=$(echo ${CRED_CREATE} | python3 -c "import sys, json; print(json.load(sys.stdin).get('id', ''))" 2>/dev/null || echo "")
    
    if [ -z "$CRED_ID" ]; then
      echo "   Note: Could not create credential. Response:"
      echo ${CRED_CREATE} | python3 -m json.tool 2>/dev/null || echo ${CRED_CREATE}
    else
      echo "   Credential created with ID: ${CRED_ID}"
    fi
  else
    echo "   Using existing credential with ID: ${CRED_ID}"
  fi
fi

# Step 2: Get the default decision environment
echo "3. Getting decision environment..."
DE_RESPONSE=$(curl -s -u ${USERNAME}:${PASSWORD} "${API_URL}/api/eda/v1/decision-environments/")
DE_ID=$(echo ${DE_RESPONSE} | python3 -c "import sys, json; results = json.load(sys.stdin).get('results', []); print(results[0]['id'] if results else '')" 2>/dev/null || echo "")

if [ -z "$DE_ID" ]; then
  echo "   No decision environment found, creating one..."
  DE_CREATE=$(curl -s -u ${USERNAME}:${PASSWORD} \
    -X POST "${API_URL}/api/eda/v1/decision-environments/" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"Default Decision Environment\",
      \"image_url\": \"quay.io/ansible/ansible-rulebook:main\",
      \"organization_id\": ${ORG_ID}
    }")
  DE_ID=$(echo ${DE_CREATE} | python3 -c "import sys, json; print(json.load(sys.stdin).get('id', ''))" 2>/dev/null || echo "")
  
  if [ -z "$DE_ID" ]; then
    echo "   Error creating decision environment. Response:"
    echo ${DE_CREATE} | python3 -m json.tool
    exit 1
  fi
fi

echo "   Decision environment ID: ${DE_ID}"

# Step 3: Check for existing activation or create one
echo "4. Checking for existing activation..."
ACTIVATION_LIST=$(curl -s -u ${USERNAME}:${PASSWORD} "${API_URL}/api/eda/v1/activations/?name=Vault+Event+Streaming")
ACTIVATION_ID=$(echo ${ACTIVATION_LIST} | python3 -c "import sys, json; results = json.load(sys.stdin).get('results', []); print(results[0]['id'] if results else '')" 2>/dev/null || echo "")

if [ -z "$ACTIVATION_ID" ]; then
  echo "   Creating rulebook activation..."
  ACTIVATION_RESPONSE=$(curl -s -u ${USERNAME}:${PASSWORD} \
    -X POST "${API_URL}/api/eda/v1/activations/" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"Vault Event Streaming\",
      \"description\": \"Monitors HashiCorp Vault events via WebSocket\",
      \"organization_id\": ${ORG_ID},
      \"rulebook_id\": ${RULEBOOK_ID},
      \"decision_environment_id\": ${DE_ID},
      \"is_enabled\": true,
      \"extra_var\": \"VAULT_ADDR: ${VAULT_ADDR:-http://host.docker.internal:8200}\nVAULT_TOKEN: ${VAULT_TOKEN:-myroot}\"
    }")

  ACTIVATION_ID=$(echo ${ACTIVATION_RESPONSE} | python3 -c "import sys, json; print(json.load(sys.stdin).get('id', ''))" 2>/dev/null || echo "")

  if [ -z "$ACTIVATION_ID" ]; then
    echo "Error creating activation. Response:"
    echo ${ACTIVATION_RESPONSE} | python3 -m json.tool
    exit 1
  fi
  
  echo ""
  echo "✓ Activation created successfully!"
else
  echo "   Using existing activation with ID: ${ACTIVATION_ID}"
  echo ""
  echo "✓ Activation already exists!"
fi

echo "  Activation ID: ${ACTIVATION_ID}"
echo ""
echo "View in UI: https://localhost:8443/rulebook-activations/${ACTIVATION_ID}"
echo ""
echo "Check status:"
echo "  curl -u admin:testpass ${API_URL}/api/eda/v1/activations/${ACTIVATION_ID}/ | python3 -m json.tool"
