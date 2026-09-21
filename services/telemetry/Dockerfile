FROM node:22-alpine
WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev --no-audit --no-fund
# Every module, not a hand-listed few: guide.mjs was added and silently
# left out of the image, which crash-looped the revision on import.
COPY *.mjs ./
COPY migrations ./migrations
ENV PORT=8080
EXPOSE 8080
CMD ["node", "server.mjs"]
