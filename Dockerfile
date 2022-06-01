FROM golang:alpine3.13 as build
RUN apk add --no-cache gcc libc-dev ca-certificates && update-ca-certificates
WORKDIR /app

ENV CGO_ENABLED=0
ENV GO111MODULE=on

COPY . .
RUN go get
RUN go mod vendor

RUN go build -o /app/main .

FROM scratch AS final

COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=build /app/main /

CMD [ "./main" ]