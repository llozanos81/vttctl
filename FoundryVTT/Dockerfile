ARG ALPINE_VER
FROM alpine:${ALPINE_VER} AS build
ARG BUILD_VER
WORKDIR /home/foundry/vtt
COPY ./${BUILD_VER}/ .
RUN set -xe \
    && apk add --no-cache --update npm nodejs python3 make g++ \
    && cd resources/app/ \
    && npm install classic-level --build-from-source

FROM alpine:${ALPINE_VER}
ARG TIMEZONE
WORKDIR /home/foundry/vtt
COPY --from=build /home/foundry/vtt ./
RUN set -xe \
    && export \
    && apk add --no-cache --update shadow nodejs icu-data-full npm tzdata \
    && addgroup -g 3000 -S foundry \
    && adduser -g 3000 -S foundry -G foundry \
    && usermod -u 3000 foundry \
    && npm install uuid@latest -g \
    && npm install pm2 -g \
    && apk del --no-cache npm shadow \
    && mkdir -p /home/foundry/userdata \
    && chown foundry:foundry -R /home/foundry/ \
    && chmod +x /home/foundry/vtt/docker-entrypoint.sh


ENV TZ=${TIMEZONE}
USER foundry
EXPOSE 30000
ENTRYPOINT [ "/home/foundry/vtt/docker-entrypoint.sh" ]