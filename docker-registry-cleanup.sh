#!/bin/bash

: ${REGISTRY_URL}
: ${REGISTRY_DIR:=/registry}

REPO_DIR=${REGISTRY_DIR}/docker/registry/v2/repositories

if [ "${DRY_RUN}" == "true" ]; then
	echo "Running in dry-run mode. Will not make any changes"
fi

#verify registry dir
if [ ! -d ${REPO_DIR} ]; then
	echo "REPO_DIR doesn't exist. REPODIR=${REPO_DIR}"
	exit 1
fi

#correct registry url (remove trailing slash)
if [[ ${REGISTRY_URL} =~ .*\/ ]]; then
	REGISTRY_URL=${REGISTRY_URL%/}
fi

#run curl with --insecure?
if [ "$CURL_INSECURE" == "true" ]; then
	CURL_INSECURE_ARG=--insecure
fi

#verify registry url
curl $CURL_INSECURE_ARG -fsSm 3 ${REGISTRY_URL}/v2/ > /dev/null
REGISTRY_URL_EXIT_CODE=$?
if [ ! ${REGISTRY_URL_EXIT_CODE} -eq 0 ]; then
	echo "Could not contact registry at ${REGISTRY_URL} - quitting"
	exit 1
fi

cd ${REPO_DIR}


MANIFESTS_WITHOUT_TAGS=$(comm -23 <(find . -type f -name "link" | grep "_manifests/revisions/sha256" | grep -v "\/signatures\/sha256\/" | awk -F/ '{print $(NF-1)}' | sort) <(for f in $(find . -type f -name "link" | grep "_manifests/tags/.*/current/link"); do cat ${f} | sed 's/^sha256://g'; echo; done | sort))

CURRENT_COUNT=0
FAILED_COUNT=0
TOTAL_COUNT=$(echo ${MANIFESTS_WITHOUT_TAGS} | wc -w | tr -d ' ')

if [ ${TOTAL_COUNT} -gt 0 ]; then
	DF_BEFORE=$(df -Ph . | awk 'END{print}')

	echo -n "Found ${TOTAL_COUNT} manifests. Starting to clean up"

	if [ ${DRY_RUN} ]; then
		echo " ..not really, because dry-run."
	else
		echo
	fi

	for manifest in ${MANIFESTS_WITHOUT_TAGS}; do
		repo=$(find . | grep "_manifests/revisions/sha256/${manifest}/link" | awk -F "_manifest"  '{print $(NF-1)}' | sed 's#^./\(.*\)/#\1#')
		
		if [ ${DRY_RUN} ]; then
			echo "Would have run curl -fsS ${CURL_INSECURE_ARG} -X DELETE ${REGISTRY_URL}/v2/${repo}/manifests/sha256:${manifest} > /dev/null"
		else
			curl -fsS ${CURL_INSECURE_ARG} -X DELETE ${REGISTRY_URL}/v2/${repo}/manifests/sha256:${manifest} > /dev/null
			exit_code=$?

			if [ ${exit_code} -eq 0 ]; then
				((CURRENT_COUNT++))
			else
				((FAILED_COUNT++))
			fi
		fi
	done
	
	DF_AFTER=$(df -Ph . | awk 'END{print}')
	
	if [ ${DRY_RUN} ]; then
		echo "DRY_RUN over"
	else
		echo "Job done, Cleaned ${CURRENT_COUNT} of ${TOTAL_COUNT} manifests."

		if [ ${FAILED_COUNT} -gt 0 ]; then
			echo "${FAILED_COUNT} manifests failed. Check for curl errors in the output above."
		fi

		echo "Disk usage before and after:"
		echo "${DF_BEFORE}"
		echo
		echo "${DF_AFTER}"
	fi
else
	echo "No manifests without tags found. Nothing to do."
fi
