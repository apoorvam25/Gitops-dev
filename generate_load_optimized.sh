#!/bin/bash
# Usage: ./generate_load_fixed.sh <scale> <directory>

SCALE=$1
DIR=$2
NS_SUFFIX=$(echo "$SCALE" | tr '[:upper:]' '[:lower:]')
NAMESPACE="load-test-$NS_SUFFIX"

mkdir -p $DIR

# Define counts
if [ "$SCALE" == "S" ]; then CM=100; SEC=100; DEP=20; fi
if [ "$SCALE" == "M" ]; then CM=1000; SEC=1000; DEP=200; fi
if [ "$SCALE" == "L" ]; then CM=10000; SEC=10000; DEP=2000; fi

# Batch Size (How many objects per file)
BATCH_SIZE=100

echo "Generating $SCALE load ($CM CMs, $SEC Secrets, $DEP Deps) in $DIR..."
echo "Batching: $BATCH_SIZE objects per file."

# Helper function to calculate batch file number
get_batch_num() {
  echo $(( ($1 - 1) / $BATCH_SIZE + 1 ))
}

# 1. Generate ConfigMaps
echo "Generating ConfigMaps..."
for i in $(seq 1 $CM); do
  BATCH=$(get_batch_num $i)
  FILE="$DIR/configmaps-batch-$BATCH.yaml"
  
  cat <<EOF >> $FILE
apiVersion: v1
kind: ConfigMap
metadata:
  name: test-cm-$i
  namespace: $NAMESPACE
data:
  key: "value-$i"
---
EOF
done

# 2. Generate Secrets
echo "Generating Secrets..."
for i in $(seq 1 $SEC); do
  BATCH=$(get_batch_num $i)
  FILE="$DIR/secrets-batch-$BATCH.yaml"

  cat <<EOF >> $FILE
apiVersion: v1
kind: Secret
metadata:
  name: test-sec-$i
  namespace: $NAMESPACE
type: Opaque
stringData:
  key: "value-$i"
---
EOF
done

# 3. Generate Deployments
echo "Generating Deployments..."
for i in $(seq 1 $DEP); do
  BATCH=$(get_batch_num $i)
  FILE="$DIR/deployments-batch-$BATCH.yaml"

  cat <<EOF >> $FILE
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-dep-$i
  namespace: $NAMESPACE
spec:
  replicas: 0
  selector:
    matchLabels:
      app: test-$i
  template:
    metadata:
      labels:
        app: test-$i
    spec:
      containers:
      - name: pause
        image: registry.k8s.io/pause:3.9
---
EOF
done

echo "✅ Done! Valid YAML files generated in $DIR"