FROM node:22-alpine
WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev --no-audit --no-fund
COPY server.mjs dashboard.mjs ./
COPY migrations ./migrations
ENV PORT=8080
EXPOSE 8080
CMD ["node", "server.mjs"]
