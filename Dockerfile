# ---- Builder ----
FROM node:22-alpine AS build

RUN apk add --no-cache build-base gcc autoconf automake zlib-dev libpng-dev vips-dev python3 git

WORKDIR /opt/app

COPY package*.json ./

RUN npm ci --omit=dev

RUN npm rebuild esbuild sharp better-sqlite3 --build-from-source

COPY . .

# Build Strapi admin panel
RUN npm run build

# ---- Runtime ----
FROM node:22-alpine

RUN apk add --no-cache vips-dev postgresql-client

WORKDIR /opt/app

COPY --from=build /opt/app ./

ENV NODE_ENV=production
ENV PATH=/opt/app/node_modules/.bin:$PATH
RUN npm install -g npm@11.6.0

RUN chown -R node:node /opt/app
USER node

EXPOSE 1337
CMD ["npm", "run", "start"]
