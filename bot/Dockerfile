FROM evilbeaver/onescript:1.3.0

COPY . /app
WORKDIR /app
RUN opm install -l

FROM evilbeaver/oscript-web:0.6.0

COPY --from=0 /app .