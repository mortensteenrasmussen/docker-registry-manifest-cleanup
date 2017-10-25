FROM alpine:3.6
RUN apk add --no-cache curl bash
ADD docker-registry-cleanup.sh /docker-registry-cleanup.sh
CMD /docker-registry-cleanup.sh
