FROM alpine:latest

RUN apk add --no-cache \
    ca-certificates \
    unzip \
    wget

RUN wget https://github.com/pocketbase/pocketbase/releases/download/v0.22.0/pocketbase_0.22.0_linux_amd64.zip \
    && unzip pocketbase_0.22.0_linux_amd64.zip \
    && rm pocketbase_0.22.0_linux_amd64.zip

COPY pb_schema.json /pb_schema.json

EXPOSE 8080

CMD ["/pocketbase", "serve", "--http=0.0.0.0:8080"]
