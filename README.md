# RapidAPI + Azure Function Setup — Per API Checklist

## RapidAPI (do this first)

1. Go to <https://rapidapi.com/studio> and click **Add API Project**.
2. Give it a name matching your Azure Function e.g. `profanity-filter` and a description.
3. Select Category and choose "Do not import"
4. Get Claude to create a png logo, save it in new folder (assets in the function), upload on RapidAPI
5. Enter <https://rapidapi.com/user/ondiekowaga> as the website
6. Enter terms of use (ask claude to modify existing ToU in the root)
7. Set healthcheck endpoint to </health>
8. Click on **Definitions** tab and create an endpoint for the function and one for /health check (no parameters)
9. Go to **Gateway** tab copy the **X-RapidAPI-Proxy-Secret** to the .env file
0. Set the Base URL to your Azure Function URL e.g. `https://fn-rapidapi-profanity-filter.azurewebsites.net/api`. (You'll get after depploy)

## Local setup

5. Paste the proxy secret into `<api-name>/.env` as `RAPIDAPI_PROXY_SECRET=`.
2. Run `npm install && npm run build` inside the api folder.

## Azure Deploy

7. Run `./deploy.sh <api-name>` from the repo root.
2. Go to Azure Portal → Function App → **Environment Variables** and add `RAPIDAPI_PROXY_SECRET` with the same value.

## RapidAPI (finish wiring)

9. Go to **Endpoints** tab on RapidAPI and add your endpoints with the correct paths.
2. Set your pricing plan under the **Plans** tab and hit **Publish**.
