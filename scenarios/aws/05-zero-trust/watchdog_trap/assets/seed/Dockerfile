FROM public.ecr.aws/docker/library/node:18-alpine
RUN apk add --no-cache bash
WORKDIR /app
RUN echo 'const http=require("http");http.createServer((req,res)=>{res.end("OK")}).listen(3000)' > server.js
RUN mkdir -p /run/secrets
EXPOSE 3000
CMD ["sh", "-c", "echo \"$FLAG\" > /run/secrets/flag && node server.js"]
