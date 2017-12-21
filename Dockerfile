FROM alpine:3.6
RUN apk add --no-cache curl bash
ADD docker-registry-cleanup.sh /docker-registry-cleanup.sh
RUN curl -L https://github.com/jessfraz/reg/releases/download/v0.8.0/reg-linux-amd64 -o /usr/local/bin/reg
RUN chmod a+x /usr/local/bin/reg
CMD /docker-registry-cleanup.sh
