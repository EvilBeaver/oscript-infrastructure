FROM evilbeaver/onescript:1.0.21

COPY . /app
WORKDIR /app
RUN opm install -l

FROM evilbeaver/oscript-web:0.6.0

COPY --from=0 /app .
