FROM ubuntu:xenial
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
ADD docker-registry-cleanup.sh /docker-registry-cleanup.sh
CMD /docker-registry-cleanup.sh
