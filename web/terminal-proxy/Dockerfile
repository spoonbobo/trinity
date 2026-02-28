FROM node:20-alpine

WORKDIR /app

# Install Docker CLI for command execution
RUN apk add --no-cache docker-cli

COPY package.json ./
RUN npm install --production

COPY server.js ./

EXPOSE 18790

CMD ["node", "server.js"]
