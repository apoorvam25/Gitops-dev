#!/bin/bash

REPO_DIR="gitops-dev"
mkdir -p "$REPO_DIR"

# Standard 10KB payload string to pad etcd database
PADDING_PLAIN=$(head -c 10240 /dev/zero | tr '\0' 'x')
PADDING_B64=$(echo -n "$PADDING_PLAIN" | base64 | tr -d '\n')

generate_tier() {
    local TIER_NAME=$1
    local NS_COUNT=$2
    local TOTAL_DEPS=$3
    local REPLICAS_PER_DEP=$4
    local CONFIG_COUNT=$5
    
    local TIER_DIR="${REPO_DIR}/${TIER_NAME}"
    mkdir -p "$TIER_DIR"
    
    # Calculate image thresholds (90/10 split)
    local ECHO_THRESHOLD=$(( TOTAL_DEPS * 90 / 100 ))
    
    # Distribute deployments evenly across namespaces
    local DEPS_PER_NS=$(( TOTAL_DEPS / NS_COUNT ))
    local REMAINDER_DEPS=$(( TOTAL_DEPS % NS_COUNT ))
    
    local DEPLOY_IDX=1
    local DEPS_CREATED=0

    for (( NS_ID=1; NS_ID<=NS_COUNT; NS_ID++ )); do
        local NS_NAME="pki-tenant-${TIER_NAME}-${NS_ID}"
        local NS_DIR="${TIER_DIR}/${NS_NAME}"
        mkdir -p "$NS_DIR"

        # 1. Namespace manifest
        cat <<EOF > "${NS_DIR}/00-namespace.yaml"
apiVersion: v1
kind: Namespace
metadata:
  name: ${NS_NAME}
EOF

        # 2. ConfigMaps and Secrets manifest
        local CONFIG_FILE="${NS_DIR}/01-configs.yaml"
        > "$CONFIG_FILE"
        for (( I=1; I<=CONFIG_COUNT; I++ )); do
            cat <<EOF >> "$CONFIG_FILE"
apiVersion: v1
kind: ConfigMap
metadata:
  name: demo-cm-${I}
  namespace: ${NS_NAME}
data:
  payload: "${PADDING_PLAIN}"
---
apiVersion: v1
kind: Secret
metadata:
  name: demo-secret-${I}
  namespace: ${NS_NAME}
type: Opaque
data:
  payload: "${PADDING_B64}"
---
EOF
        done

        # 3. Determine how many deployments go into this specific namespace
        local CURRENT_NS_DEPS=$DEPS_PER_NS
        if [ $NS_ID -le $REMAINDER_DEPS ]; then
            local CURRENT_NS_DEPS=$(( DEPS_PER_NS + 1 ))
        fi

        # 4. Deployments manifest
        local DEPLOY_FILE="${NS_DIR}/02-deployments.yaml"
        > "$DEPLOY_FILE"
        
        for (( D=1; D<=CURRENT_NS_DEPS; D++ )); do
            if [ $DEPS_CREATED -ge $TOTAL_DEPS ]; then break; fi
            
            local DEP_NAME="workload-app-${DEPLOY_IDX}"
            local IMAGE="nginx:latest"
            local ARGS_BLOCK=""
            
            # Switch to http-echo for the last 10% of deployments
            if [ $DEPLOY_IDX -gt $ECHO_THRESHOLD ]; then
                IMAGE="hashicorp/http-echo:latest"
                ARGS_BLOCK="        args: ['-text=hello']"
            fi

            cat <<EOF >> "$DEPLOY_FILE"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${DEP_NAME}
  namespace: ${NS_NAME}
spec:
  replicas: ${REPLICAS_PER_DEP}
  selector:
    matchLabels:
      app: ${DEP_NAME}
  template:
    metadata:
      labels:
        app: ${DEP_NAME}
    spec:
      containers:
      - name: app
        image: ${IMAGE}
$( [ ! -z "$ARGS_BLOCK" ] && echo "$ARGS_BLOCK" )
        envFrom:
        - configMapRef:
            name: demo-cm-1
        - secretRef:
            name: demo-secret-1
        resources:
          limits:
            cpu: "100m"
            memory: "128Mi"
          requests:
            cpu: "50m"
            memory: "64Mi"
---
EOF
            ((DEPLOY_IDX++))
            ((DEPS_CREATED++))
        done
    done
    echo "Generated $TIER_NAME: $NS_COUNT Namespaces, $TOTAL_DEPS Deployments ($(( TOTAL_DEPS * REPLICAS_PER_DEP )) Pods)"
}

# Execute payload generation matching the spreadsheet specifications
echo "Starting matrix payload generation..."
generate_tier "small-tier" 5 25 6 10
generate_tier "medium-tier" 10 72 11 14
generate_tier "large-tier" 25 382 19 30

echo "Finished! Total payload tree structures written directly to ./${REPO_DIR}"