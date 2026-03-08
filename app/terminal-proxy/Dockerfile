FROM node:20-alpine

WORKDIR /app

RUN apk add --no-cache docker-cli curl python3 make g++ \
    && curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    && chmod +x kubectl \
    && mv kubectl /usr/local/bin/

COPY package.json ./
RUN npm install --production && apk del python3 make g++

COPY server.js ./
COPY rbac-registry.js ./
COPY rbac/ ./rbac/

EXPOSE 18790

CMD ["node", "server.js"]
