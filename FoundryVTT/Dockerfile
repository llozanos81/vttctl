FROM alpine:3.16
WORKDIR /home/foundry/vtt
COPY ./vtt/ .
RUN set -xe \
    && export \
    && addgroup -S foundry \
    && adduser -S foundry -G foundry \
    && apk add --no-cache --update nodejs icu-data-full \
    && mkdir -p /home/foundry/vtt \
    && chown foundry:foundry -R /home/foundry/vtt \
    && chmod +x /home/foundry/vtt/docker-entrypoint.sh \
    && mkdir -p /home/foundry/userdata \
    && chown foundry:foundry -R /home/foundry/userdata 

USER foundry
EXPOSE 30000
ENTRYPOINT [ "/home/foundry/vtt/docker-entrypoint.sh" ]