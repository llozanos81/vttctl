ARG ALPINE_VER
FROM alpine:$ALPINE_VER AS build
ARG BUILD_VER
WORKDIR /home/foundry/vtt
COPY ./$BUILD_VER/ .
RUN set -xe \
    && apk add --no-cache --update npm python3 make g++ \
    && cd resources/app/ \
    && npm install classic-level --build-from-source

FROM alpine:$ALPINE_VER
WORKDIR /home/foundry/vtt
COPY --from=build /home/foundry/vtt ./
RUN set -xe \
    && export \
    && apk add --no-cache --update shadow \
    && addgroup -g 3000 -S foundry \
    && adduser -g 3000 -S foundry -G foundry \
    && usermod -u 3000 foundry \
    && usermod -g 3000 foundry \
    && apk add --no-cache --update nodejs icu-data-full npm tzdata \
    && npm install pm2 -g \
    && apk del --no-cache npm shadow \
    && chown foundry:foundry -R /home/foundry/vtt \
    && chmod +x /home/foundry/vtt/docker-entrypoint.sh \
    && mkdir -p /home/foundry/userdata \
    && cp /usr/share/zoneinfo/America/Monterrey /etc/localtime \
    && chown foundry:foundry -R /home/foundry/userdata

USER foundry
EXPOSE 30000
ENTRYPOINT [ "/home/foundry/vtt/docker-entrypoint.sh" ]