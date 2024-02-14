#!/usr/bin/env bash

set -o errexit -o nounset -o errtrace -o pipefail

declare -A providerDigests=(
  # NOTE: The providers below are all packaged the same way, with significant
  # redundancy, and unpacked with each installation. The redundancy with each
  # provider means on smaller machines (like presubmit), we very quickly run
  # out of disk space waiting for each provider to install and unpack the
  # **same** /usr/bin/provider binary (>400Mb). The only "important" non-unique
  # thing in the provider images is the package.yaml, which isn't simply copied
  # into the apk, and tested at melange test time.
  #
  # All that to say, for this test, we're going to pick one of the providers
  # and install only that, but leave the logic for others in place in case the
  # future brings leaner installation methods.

	# [cloudfront]=${CLOUDFRONT_DIGEST}
	# [cloudwatchlogs]=${CLOUDWATCHLOGS_DIGEST}
	# [dynamodb]=${DYNAMODB_DIGEST}
	[ec2]=${EC2_DIGEST}
	# [eks]=${EKS_DIGEST}
	# [firehose]=${FIREHOSE_DIGEST}
	# [iam]=${IAM_DIGEST}
	# [kms]=${KMS_DIGEST}
	# [lambda]=${LAMBDA_DIGEST}
	# [rds]=${RDS_DIGEST}
	# [s3]=${S3_DIGEST}
	# [sns]=${SNS_DIGEST}
	# [sqs]=${SQS_DIGEST}
)

cat <<EOF | kubectl apply -f -
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: upbound-provider-family-aws
spec:
  package: ${AWS_DIGEST}
  revisionHistoryLimit: 0
  ignoreCrossplaneConstraints: true
  packagePullSecrets:
  - name: regcred
EOF

kubectl wait --for=condition=Installed provider upbound-provider-family-aws --timeout=3m
kubectl wait --for=condition=Healthy provider upbound-provider-family-aws --timeout=5m

for provider in "${!providerDigests[@]}"; do
	digest="${providerDigests[$provider]}"

	cat <<EOF | kubectl apply -f -
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-aws-${provider}
spec:
  package: ${digest}
  # The providers seem to hardcode their dependency on the upstream
  # upbound-provider-family-aws reference. Since we're using our own, we
  # disable this check.
  skipDependencyResolution: true
  # Delete the revision history to save space
  revisionHistoryLimit: 0
  # We use psuedo_tags for the provider images, so we need to ignore the semver
  # checks.
  ignoreCrossplaneConstraints: true
  # When applicable, use the regcred secret to pull the provider images.
  packagePullSecrets:
  - name: regcred
EOF

done

for provider in "${!providerDigests[@]}"; do
	kubectl wait --for=condition=Installed "provider/provider-aws-${provider}" --timeout=3m
	kubectl wait --for=condition=Healthy "provider/provider-aws-${provider}" --timeout=5m
done
