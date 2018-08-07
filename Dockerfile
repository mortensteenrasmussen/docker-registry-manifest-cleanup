FROM alpine:3.6
RUN apk add --no-cache curl bash jq
ADD docker-registry-cleanup.sh /docker-registry-cleanup.sh
CMD /docker-registry-cleanup.sh
