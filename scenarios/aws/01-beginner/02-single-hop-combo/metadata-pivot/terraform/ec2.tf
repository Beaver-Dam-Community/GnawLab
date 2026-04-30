#---------------------------------------
# EC2 Instance - Vulnerable Web Application
#---------------------------------------
resource "aws_instance" "web" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  # IMPORTANT: IMDSv1 enabled for SSRF exploitation (intentionally vulnerable)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "optional" # IMDSv1 allowed (vulnerable)
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -e

    # Install dependencies
    dnf install -y python3 python3-pip
    pip3 install flask requests

    # Create vulnerable web application
    cat > /home/ec2-user/app.py << 'PYEOF'
    from flask import Flask, request, render_template_string
    import requests
    import base64

    app = Flask(__name__)

    HTML_TEMPLATE = '''
    <!DOCTYPE html>
    <html>
    <head>
        <title>Beaver Dam Bank - Custom Card Designer</title>
        <style>
            * { margin: 0; padding: 0; box-sizing: border-box; }
            body { font-family: 'Segoe UI', Arial, sans-serif; background: #f7fafc; min-height: 100vh; }

            /* Header */
            .header { background: linear-gradient(135deg, #1a365d 0%, #2c5282 100%); padding: 15px 40px; display: flex; align-items: center; justify-content: space-between; }
            .logo { display: flex; align-items: center; gap: 12px; }
            .logo-icon { width: 40px; height: 40px; background: #c9a227; border-radius: 8px; display: flex; align-items: center; justify-content: center; font-size: 20px; }
            .logo-text { color: white; font-size: 20px; font-weight: 600; }
            .nav { display: flex; gap: 30px; }
            .nav a { color: rgba(255,255,255,0.8); text-decoration: none; font-size: 14px; }
            .nav a:hover { color: white; }

            /* Main Content */
            .container { max-width: 900px; margin: 40px auto; padding: 0 20px; }
            .hero { text-align: center; margin-bottom: 40px; }
            .hero h1 { color: #1a365d; font-size: 32px; margin-bottom: 10px; }
            .hero p { color: #4a5568; font-size: 16px; }

            /* Card Designer */
            .designer { background: white; border-radius: 16px; box-shadow: 0 4px 20px rgba(0,0,0,0.08); padding: 40px; }
            .form-section { margin-bottom: 30px; }
            .form-section label { display: block; color: #2d3748; font-weight: 600; margin-bottom: 8px; font-size: 14px; }
            .form-section input { width: 100%; padding: 14px 16px; border: 2px solid #e2e8f0; border-radius: 8px; font-size: 15px; transition: border-color 0.2s; }
            .form-section input:focus { outline: none; border-color: #3182ce; }
            .form-section .hint { color: #718096; font-size: 12px; margin-top: 6px; }

            .btn { background: linear-gradient(135deg, #c9a227 0%, #d4af37 100%); color: #1a365d; padding: 14px 32px; border: none; border-radius: 8px; font-size: 16px; font-weight: 600; cursor: pointer; transition: transform 0.2s, box-shadow 0.2s; }
            .btn:hover { transform: translateY(-2px); box-shadow: 0 4px 12px rgba(201,162,39,0.4); }

            /* Card Preview */
            .preview-section { margin-top: 40px; }
            .preview-title { color: #2d3748; font-size: 18px; font-weight: 600; margin-bottom: 20px; text-align: center; }
            .card-preview { width: 380px; height: 240px; margin: 0 auto; background: linear-gradient(135deg, #1a365d 0%, #2c5282 50%, #c9a227 100%); border-radius: 16px; padding: 24px; position: relative; box-shadow: 0 10px 40px rgba(26,54,93,0.3); }
            .card-bank { color: rgba(255,255,255,0.9); font-size: 16px; font-weight: 600; letter-spacing: 1px; }
            .card-chip { width: 45px; height: 35px; background: linear-gradient(135deg, #d4af37 0%, #f0d78c 100%); border-radius: 6px; margin-top: 20px; }
            .card-image-area { position: absolute; top: 24px; right: 24px; width: 70px; height: 70px; background: rgba(255,255,255,0.15); border-radius: 8px; display: flex; align-items: center; justify-content: center; overflow: hidden; border: 2px dashed rgba(255,255,255,0.3); }
            .card-image-area img { max-width: 100%; max-height: 100%; object-fit: cover; }
            .card-image-area .placeholder { color: rgba(255,255,255,0.5); font-size: 10px; text-align: center; }
            .card-number { color: white; font-size: 22px; letter-spacing: 3px; margin-top: 30px; font-family: 'Courier New', monospace; }
            .card-details { display: flex; justify-content: space-between; margin-top: 20px; }
            .card-holder, .card-expiry { color: rgba(255,255,255,0.8); }
            .card-label { font-size: 9px; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 4px; }
            .card-value { font-size: 14px; letter-spacing: 1px; }

            /* Error/Result */
            .result { margin-top: 30px; padding: 20px; background: #fff5f5; border: 1px solid #feb2b2; border-radius: 8px; }
            .result-title { color: #c53030; font-weight: 600; margin-bottom: 10px; }
            .result-content { color: #742a2a; font-family: monospace; font-size: 13px; white-space: pre-wrap; word-break: break-all; max-height: 300px; overflow-y: auto; }

            /* Footer */
            .footer { text-align: center; margin-top: 30px; padding: 20px; }
            .footer .beta { background: #fef3c7; color: #92400e; padding: 8px 16px; border-radius: 20px; font-size: 12px; display: inline-block; }
        </style>
    </head>
    <body>
        <div class="header">
            <div class="logo">
                <div class="logo-icon">B</div>
                <span class="logo-text">Beaver Dam Bank</span>
            </div>
            <nav class="nav">
                <a href="#">Accounts</a>
                <a href="#">Cards</a>
                <a href="#">Payments</a>
                <a href="#">Support</a>
            </nav>
        </div>

        <div class="container">
            <div class="hero">
                <h1>Design Your Custom Card</h1>
                <p>Personalize your Beaver Dam Bank card with your own image</p>
            </div>

            <div class="designer">
                <form method="POST">
                    <div class="form-section">
                        <label>Image URL</label>
                        <input type="text" name="image_url" placeholder="https://example.com/your-image.jpg" value="{{ image_url or '' }}">
                        <p class="hint">Enter a URL to your image. Supported formats: JPG, PNG, GIF</p>
                    </div>
                    <button type="submit" class="btn">Preview My Card</button>
                </form>

                <div class="preview-section">
                    <div class="preview-title">Card Preview</div>
                    <div class="card-preview">
                        <div class="card-bank">BEAVER DAM BANK</div>
                        <div class="card-chip"></div>
                        <div class="card-image-area">
                            {% if image_data %}
                            <img src="data:image/png;base64,{{ image_data }}" alt="Custom">
                            {% else %}
                            <span class="placeholder">Your<br>Image</span>
                            {% endif %}
                        </div>
                        <div class="card-number">4532 •••• •••• 7891</div>
                        <div class="card-details">
                            <div class="card-holder">
                                <div class="card-label">Card Holder</div>
                                <div class="card-value">VALUED CUSTOMER</div>
                            </div>
                            <div class="card-expiry">
                                <div class="card-label">Valid Thru</div>
                                <div class="card-value">12/28</div>
                            </div>
                        </div>
                    </div>
                </div>

                {% if error %}
                <div class="result">
                    <div class="result-title">Unable to load image</div>
                    <div class="result-content">{{ error }}</div>
                </div>
                {% endif %}
            </div>

            <div class="footer">
                <span class="beta">Beta Feature - Internal Testing Only</span>
            </div>
        </div>
    </body>
    </html>
    '''

    @app.route('/', methods=['GET', 'POST'])
    def index():
        image_data = None
        image_url = None
        error = None

        if request.method == 'POST':
            image_url = request.form.get('image_url', '')
            if image_url:
                try:
                    # VULNERABLE: No URL validation - allows SSRF
                    resp = requests.get(image_url, timeout=5)
                    content_type = resp.headers.get('Content-Type', '')

                    # Check if response is an image
                    if 'image' in content_type:
                        image_data = base64.b64encode(resp.content).decode('utf-8')
                    else:
                        # VULNERABLE: Exposes response content in error message
                        error = f"The URL did not return a valid image.\\n\\nContent-Type: {content_type}\\n\\nServer Response:\\n{resp.text[:2000]}"
                except requests.exceptions.Timeout:
                    error = "Request timed out. Please check the URL and try again."
                except requests.exceptions.ConnectionError as e:
                    error = f"Could not connect to the server: {str(e)}"
                except Exception as e:
                    error = f"Error fetching image: {str(e)}"

        return render_template_string(HTML_TEMPLATE, image_data=image_data, image_url=image_url, error=error)

    @app.route('/health')
    def health():
        return 'OK'

    if __name__ == '__main__':
        app.run(host='0.0.0.0', port=80)
    PYEOF

    # Create systemd service
    cat > /etc/systemd/system/webapp.service << 'SVCEOF'
    [Unit]
    Description=Vulnerable Web Application
    After=network.target

    [Service]
    Type=simple
    User=root
    WorkingDirectory=/home/ec2-user
    ExecStart=/usr/bin/python3 /home/ec2-user/app.py
    Restart=always
    RestartSec=3

    [Install]
    WantedBy=multi-user.target
    SVCEOF

    # Start service
    systemctl daemon-reload
    systemctl enable webapp
    systemctl start webapp
  EOF
  )

  tags = merge(local.common_tags, {
    Name        = local.ec2_name
    Description = "Vulnerable web application for metadata-pivot scenario"
  })

  depends_on = [
    aws_internet_gateway.main,
    aws_iam_instance_profile.ec2_profile
  ]
}
