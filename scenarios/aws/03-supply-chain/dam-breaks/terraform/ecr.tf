resource "aws_ecr_repository" "webapp_ecr" {
  name = "${local.name}-beaverpay-webapp-${local.suffix}"

  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  force_delete = true

  tags = {
    Name = "${local.name}-beaverpay-webapp-${local.suffix}"
    Role = "webapp-image-registry"
  }
}

resource "null_resource" "push_dummy_image" {
  depends_on = [aws_ecr_repository.webapp_ecr]

  triggers = {
    ecr_repo_url = aws_ecr_repository.webapp_ecr.repository_url
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      aws ecr get-login-password --region ${var.region} | \
        docker login --username AWS --password-stdin ${aws_ecr_repository.webapp_ecr.repository_url} && \
      mkdir -p /tmp/beaverpay-dummy && \
      cat > /tmp/beaverpay-dummy/Dockerfile << 'DOCKERFILE'
FROM public.ecr.aws/docker/library/node:18-alpine
WORKDIR /app
RUN echo '{"name":"beaverpay-webapp"}' > package.json
RUN echo 'const http=require("http");http.createServer((q,r)=>{r.writeHead(200);r.end("BeaverPay");}).listen(3000);' > index.js
EXPOSE 3000
CMD ["node","index.js"]
DOCKERFILE
      docker build -t ${aws_ecr_repository.webapp_ecr.repository_url}:latest /tmp/beaverpay-dummy/ && \
      docker push ${aws_ecr_repository.webapp_ecr.repository_url}:latest && \
      rm -rf /tmp/beaverpay-dummy
    EOT
  }
}
