# Random ID for unique resource naming
resource "random_string" "scenario_id" {
  length  = 8
  special = false
  upper   = false
}

locals {
  scenario_id   = random_string.scenario_id.result
  scenario_name = "gnawlab-secrets"

  # Resource naming convention: {scenario_name}-{resource}-{scenario_id}
  vpc_name         = "${local.scenario_name}-vpc-${local.scenario_id}"
  alb_name         = "${local.scenario_name}-alb-${local.scenario_id}"
  ecs_cluster_name = "${local.scenario_name}-cluster-${local.scenario_id}"
  ecs_service_name = "${local.scenario_name}-service-${local.scenario_id}"
  task_role_name   = "${local.scenario_name}-task-role-${local.scenario_id}"
  exec_role_name   = "${local.scenario_name}-exec-role-${local.scenario_id}"
  secret_name      = "${local.scenario_name}-flag-${local.scenario_id}"
  kms_alias        = "alias/${local.scenario_name}-key-${local.scenario_id}"

  # IP whitelist: auto-detect or manual
  whitelist_cidr = var.whitelist_ip != "" ? var.whitelist_ip : "${chomp(data.http.my_ip.response_body)}/32"

  # Flask application code (vulnerable to command injection)
  flask_app_code = <<-PYTHON
from flask import Flask, request, render_template_string, send_file
import subprocess
import os
import uuid

app = Flask(__name__)
UPLOAD_FOLDER = '/tmp/uploads'
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

HTML_TEMPLATE = '''
<!DOCTYPE html>
<html>
<head>
    <title>ResizeCloud - Professional Image Resizing</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Segoe UI', Arial, sans-serif; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); min-height: 100vh; }
        .header { background: rgba(255,255,255,0.95); padding: 20px 50px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); display: flex; justify-content: space-between; align-items: center; }
        .logo { font-size: 28px; font-weight: bold; color: #667eea; }
        .logo span { color: #764ba2; }
        .nav a { color: #666; text-decoration: none; margin-left: 30px; }
        .container { max-width: 800px; margin: 50px auto; padding: 40px; background: white; border-radius: 20px; box-shadow: 0 20px 60px rgba(0,0,0,0.3); }
        h1 { color: #333; margin-bottom: 10px; font-size: 32px; }
        .subtitle { color: #666; margin-bottom: 30px; font-size: 16px; }
        .upload-form { background: #f8f9fa; padding: 30px; border-radius: 10px; border: 2px dashed #667eea; }
        .form-group { margin-bottom: 20px; }
        input[type="file"] { margin: 10px 0; padding: 10px; width: 100%; }
        label { display: block; margin-bottom: 8px; color: #333; font-weight: 500; }
        input[type="text"] { width: 100%; padding: 12px; border: 1px solid #ddd; border-radius: 8px; font-size: 16px; transition: border-color 0.3s; }
        input[type="text"]:focus { outline: none; border-color: #667eea; }
        button { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 15px 40px; border: none; border-radius: 8px; font-size: 18px; cursor: pointer; width: 100%; transition: transform 0.2s, box-shadow 0.2s; }
        button:hover { transform: translateY(-2px); box-shadow: 0 5px 20px rgba(102,126,234,0.4); }
        .features { display: flex; justify-content: space-around; margin-top: 40px; padding-top: 30px; border-top: 1px solid #eee; }
        .feature { text-align: center; flex: 1; }
        .feature-icon { font-size: 40px; margin-bottom: 10px; }
        .feature h3 { color: #333; margin-bottom: 5px; }
        .feature p { color: #666; font-size: 14px; }
        .error { background: #fee2e2; color: #dc2626; padding: 15px; border-radius: 8px; margin: 20px 0; border: 1px solid #fecaca; }
        .success { background: #dcfce7; color: #16a34a; padding: 15px; border-radius: 8px; margin: 20px 0; border: 1px solid #bbf7d0; }
        .footer { text-align: center; padding: 30px; color: rgba(255,255,255,0.8); }
        .footer a { color: white; }
        .info-box { background: #e0e7ff; padding: 15px; border-radius: 8px; margin-bottom: 20px; font-size: 14px; color: #4338ca; }
        .stats { display: flex; justify-content: center; gap: 40px; margin: 30px 0; }
        .stat { text-align: center; }
        .stat-number { font-size: 36px; font-weight: bold; color: #667eea; }
        .stat-label { color: #666; font-size: 14px; }
    </style>
</head>
<body>
    <div class="header">
        <div class="logo">Resize<span>Cloud</span></div>
        <nav class="nav">
            <a href="/">Home</a>
            <a href="#">Pricing</a>
            <a href="#">API Docs</a>
            <a href="#">Contact</a>
        </nav>
    </div>
    <div class="container">
        <h1>Image Resizing Service</h1>
        <p class="subtitle">Professional-grade image processing powered by ImageMagick</p>

        <div class="stats">
            <div class="stat">
                <div class="stat-number">10M+</div>
                <div class="stat-label">Images Processed</div>
            </div>
            <div class="stat">
                <div class="stat-number">99.9%</div>
                <div class="stat-label">Uptime</div>
            </div>
            <div class="stat">
                <div class="stat-number">50ms</div>
                <div class="stat-label">Avg Response</div>
            </div>
        </div>

        {% if error %}<div class="error">{{ error }}</div>{% endif %}
        {% if success %}<div class="success">{{ success }}</div>{% endif %}

        <div class="upload-form">
            <div class="info-box">
                Supported formats: PNG, JPG, GIF, WebP. Max file size: 10MB
            </div>
            <form method="POST" action="/resize" enctype="multipart/form-data">
                <div class="form-group">
                    <label>Upload Image</label>
                    <input type="file" name="image" accept="image/*" required>
                </div>

                <div class="form-group">
                    <label>Output Dimensions</label>
                    <input type="text" name="dimensions" placeholder="e.g., 800x600, 50%, 1920x1080" required>
                </div>

                <button type="submit">Resize Image</button>
            </form>
        </div>

        <div class="features">
            <div class="feature">
                <div class="feature-icon">🚀</div>
                <h3>Lightning Fast</h3>
                <p>Process images in milliseconds</p>
            </div>
            <div class="feature">
                <div class="feature-icon">🔒</div>
                <h3>Enterprise Security</h3>
                <p>SOC2 compliant infrastructure</p>
            </div>
            <div class="feature">
                <div class="feature-icon">☁️</div>
                <h3>Cloud Native</h3>
                <p>Auto-scaling on AWS</p>
            </div>
        </div>
    </div>
    <div class="footer">
        <p>&copy; 2024 ResizeCloud Inc. | Enterprise Image Processing</p>
        <p style="margin-top: 10px; font-size: 12px;">Powered by ImageMagick | Running on AWS ECS</p>
    </div>
</body>
</html>
'''

@app.route('/')
def index():
    return render_template_string(HTML_TEMPLATE)

@app.route('/health')
def health():
    return 'OK', 200

@app.route('/resize', methods=['POST'])
def resize():
    error = None
    success = None

    if 'image' not in request.files:
        return render_template_string(HTML_TEMPLATE, error='No image uploaded')

    file = request.files['image']
    dimensions = request.form.get('dimensions', '800x600')

    if file.filename == '':
        return render_template_string(HTML_TEMPLATE, error='No image selected')

    file_id = str(uuid.uuid4())
    input_path = os.path.join(UPLOAD_FOLDER, f'{file_id}_input')
    output_path = os.path.join(UPLOAD_FOLDER, f'{file_id}_output.png')
    file.save(input_path)

    try:
        # VULNERABLE: Command injection via dimensions parameter
        cmd = f'convert {input_path} -resize {dimensions} {output_path}'
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=30)

        if result.returncode == 0 and os.path.exists(output_path):
            return send_file(output_path, mimetype='image/png', as_attachment=True, download_name='resized.png')
        else:
            error = f'Processing failed: {result.stderr}'
    except subprocess.TimeoutExpired:
        error = 'Processing timeout'
    except Exception as e:
        error = f'Error: {str(e)}'
    finally:
        for f in [input_path, output_path]:
            if os.path.exists(f):
                os.remove(f)

    return render_template_string(HTML_TEMPLATE, error=error)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
PYTHON
}
