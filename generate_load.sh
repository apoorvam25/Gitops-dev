#!/bin/bash
#!/bin/bash
# Usage: ./generate_load.sh <scale> <directory>
# Scale options: S, M, L

SCALE=$1
DIR=$2
mkdir -p $DIR

if [ "$SCALE" == "S" ]; then CM=100; SEC=100; DEP=20; fi
if [ "$SCALE" == "M" ]; then CM=1000; SEC=1000; DEP=200; fi
if [ "$SCALE" == "L" ]; then CM=10000; SEC=10000; DEP=2000; fi

echo "Generating $SCALE load: $CM CMs, $SEC Secrets, $DEP Deployments..."

# Generate ConfigMaps
for i in $(seq 1 $CM); do
cat <<EOF > $DIR/cm-$i.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: test-cm-$i
  namespace: load-test-$SCALE
data:
  key: "value-$i"
EOF
done

# Generate Secrets
for i in $(seq 1 $SEC); do
cat <<EOF > $DIR/sec-$i.yaml
apiVersion: v1
kind: Secret
metadata:
  name: test-sec-$i
  namespace: load-test-$SCALE
type: Opaque
stringData:
  key: "value-$i"
EOF
done

# Generate Deployments (0 Replicas)
for i in $(seq 1 $DEP); do
cat <<EOF > $DIR/dep-$i.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-dep-$i
  namespace: load-test-$SCALE
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
        image: k8s.gcr.io/pause:3.2
EOF
done
