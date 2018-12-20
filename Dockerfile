FROM alpine:3.6
RUN apk add --no-cache python3 ca-certificates
ADD docker-registry-cleanup.py /docker-registry-cleanup.py
ADD requirements.txt /requirements.txt
RUN pip3 install -r requirements.txt && chmod +x /docker-registry-cleanup.py
CMD python3 /docker-registry-cleanup.py
