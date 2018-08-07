#!/bin/bash

: ${REGISTRY_URL}
: ${REGISTRY_DIR:=/registry}

REPO_DIR=${REGISTRY_DIR}/docker/registry/v2/repositories
BLOB_DIR=${REGISTRY_DIR}/docker/registry/v2/blobs

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

ALL_MANIFESTS=$(find ${repo_dir} -type f -name "link" | grep "_manifests/revisions/sha256" | \
                                                grep -v "\/signatures\/sha256\/" | \
                                                awk -F/ '{print $(NF-1)}' | sort | uniq)
LINKED_MANIFESTS=$(for f in $(find ${repo_dir} -type f -name "link" | \
                                grep "_manifests/tags/.*/current/link"); do\
                                cat ${f} | sed 's/^sha256://g'; echo; \
                   done | sort | uniq)
LIST_MANIFESTS=""

for manifest in ${LINKED_MANIFESTS}; do
    # check if manifest is a manifest list and add references to real manifest
    manifest_data=$(cat ${BLOB_DIR}/sha256/${manifest:0:2}/${manifest}/data)
    manifest_media_type=$(echo ${manifest_data} | jq -r '.mediaType')
    if [ "${manifest_media_type}" == "application/vnd.docker.distribution.manifest.list.v2+json" ] ; then
        # we have a manifest list and fetch the referenced manifests
        additional_manifests=$(echo ${manifest_data} | jq -r '.["manifests"] | .[].digest' | cut -d: -f2)
        LIST_MANIFESTS=$(printf "%s\n%s\n" ${LIST_MANIFESTS} ${additional_manifests})
    fi
done

LIST_MANIFESTS=$(echo "$LIST_MANIFESTS" | sort | uniq)

LINKED_MANIFESTS=$(printf "%s\n%s" "${LINKED_MANIFESTS}" "${LIST_MANIFESTS}")

MANIFESTS_WITHOUT_TAGS=$(comm -23 <(echo "${ALL_MANIFESTS}") <(echo "${LINKED_MANIFESTS}"))

CURRENT_COUNT=0
FAILED_COUNT=0
TOTAL_COUNT=$(echo ${MANIFESTS_WITHOUT_TAGS} | wc -w | tr -d ' ')
COUNTER=0

if [ ${TOTAL_COUNT} -gt 0 ]; then
	DF_BEFORE=$(df -Ph . | awk 'END{print}')

	echo -n "Found ${TOTAL_COUNT} manifests. Starting to clean up"

	if [ ${DRY_RUN} ]; then
		echo " ..not really, because dry-run."
	else
		echo
	fi

	# Caching find result
	find . > /tmp/find_result.txt
	for manifest in ${MANIFESTS_WITHOUT_TAGS}; do
		((COUNTER++))
		echo "## Doing $COUNTER / ${TOTAL_COUNT}"
		repos=$(grep "_manifests/revisions/sha256/${manifest}/link" /tmp/find_result.txt | awk -F "_manifest"  '{print $(NF-1)}' | sed 's#^./\(.*\)/#\1#')

		for repo in $repos; do
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
	done
	rm -f /tmp/find_result.txt

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
