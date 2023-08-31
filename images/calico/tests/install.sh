#!/usr/bin/env bash

set -o errexit -o nounset -o errtrace -o pipefail -x

TMP="$(mktemp -d)"
pushd "${TMP}"

# Ever since
# https://github.com/projectcalico/calico/commit/3fb6b37f2c39fdc732d09167d207465d512fe68b,
# calico runs a `mount-bpffs` container on `calico-node` startup that attempts
# to set up a bpfs mount at /sys/fs. Even though it has `-best-effort`, this
# fails in k3d because of the way docker bind mounts inherit the host
# permissions by default. This results with a weird docker in docker only error
# traced back to the way /sys is mounted. To work around this, we simply mark
# the whole /sys mount as rshared. This is the same way kind gets around this
# in their custom entrypoint startup script, but k3d currently support custom
# entrypoint scripts so we hack it in here, until a future time where we can
# bake this in.
#
# Several references for the next poor soul: -
# https://github.com/docker/for-mac/issues/4454 -
# https://github.com/kubernetes-sigs/kind/blob/c13c54b9564aed8bc4f28b90af20a1100da66963/images/base/files/usr/local/bin/entrypoint#L53-L62
for name in $(docker ps --format '{{.Names}}'); do
	if [[ $name =~ k3d-.*-(server|agent)-.* ]]; then
		echo $name
		docker exec $name mount -o remount,ro /sys
		docker exec $name mount --make-rshared /

		# on startup, k3d rewrites /etc/hosts from:
		#
		# ::1 ip6-localhost ip6-loopback localhost
		# 127.0.0.1 localhost
		#
		# to
		#
		# 127.0.0.1 localhost
		# ::1 ip6-localhost ip6-loopback localhost
		#
		# which defaults any 'localhost' resolution to the disabled ::1 address.
		# This means that any service looking to explicitly resolve localhost on
		# the node (like the calico-typha readiness check) will attempt and fail to
		# bind to ::1
		#
		# This simply prepends 127.0.0.1 localhost to /etc/hosts to ensure the ipv4
		# localhost is chosen.
		# TODO: I have no idea why this doesn't affect the upstream image, which
		# k3d also reorders.
		docker exec $name /bin/sh -c '{ echo "127.0.0.1 localhost"; cat /etc/hosts; } > /tmp/hosts_temp && cat /tmp/hosts_temp > /etc/hosts && rm /tmp/hosts_temp'
	fi
done

kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/tigera-operator.yaml

cat <<EOF | kubectl apply -f -
apiVersion: operator.tigera.io/v1
kind: ImageSet
metadata:
  name: calico-v3.26.1
spec:
  images:
    - image: calico/node
      digest: ${NODE_DIGEST}
    - image: calico/cni
      digest: ${CNI_DIGEST}
    - image: calico/kube-controllers
      digest: ${KUBE_CONTROLLERS_DIGEST}
    - image: calico/pod2daemon-flexvol
      digest: ${POD2DAEMON_FLEXVOL_DIGEST}
    - image: calico/csi
      digest: ${CSI_DIGEST}
    - image: calico/typha
      digest: ${TYPHA_DIGEST}
    - image: calico/node-driver-registrar
      digest: ${NODE_DRIVER_REGISTRAR_DIGEST}
    # This isn't used on Linux, it just needs to have a value.
    - image: calico/windows-upgrade
      digest: sha256:0000000000000000000000000000000000000000000000000000000000000000
EOF

cat <<EOF | kubectl apply -f -
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  variant: Calico
  registry: ${REGISTRY}
  imagePath: ${REPOSITORY}
  imagePrefix: calico-
EOF

kubectl rollout status deployment tigera-operator -n tigera-operator --timeout 180s
kubectl wait --for condition=ready installation.operator.tigera.io/default --timeout 180s

kubectl rollout status daemonset calico-node -n calico-system --timeout 120s
kubectl rollout status deployment calico-kube-controllers -n calico-system --timeout 60s
kubectl rollout status deployment calico-typha -n calico-system --timeout 60s
kubectl rollout status daemonset csi-node-driver -n calico-system --timeout 60s
