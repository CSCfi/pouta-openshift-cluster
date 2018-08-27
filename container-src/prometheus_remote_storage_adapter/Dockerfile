FROM golang:1.10-alpine

ENV remote_storage_adapter_url=github.com/prometheus/prometheus/documentation/examples/remote_storage/remote_storage_adapter

RUN apk update && apk add git

RUN go get $remote_storage_adapter_url && go build $remote_storage_adapter_url

EXPOSE 9201

CMD ["remote_storage_adapter", "-h"]
