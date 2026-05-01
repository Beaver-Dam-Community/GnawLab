from flask import Flask, request, jsonify, send_from_directory, Response
import json
import os
import requests
import socket

app = Flask(__name__)

SERVICE_NAME    = "Prime Financial Customer Portal"
VERSION         = "5.0.0"
SHADOW_API_HOST = os.environ.get("SHADOW_API_HOST", "127.0.0.1")
MEDIA_DATA_PATH = os.environ.get("MEDIA_DATA_PATH", "media_files.json")
STATIC_DIR      = os.environ.get("STATIC_DIR", "static")

with open(MEDIA_DATA_PATH, "r") as f:
    _MEDIA = {str(rec["file_id"]): rec for rec in json.load(f)}


@app.route("/")
def index():
    return send_from_directory(STATIC_DIR, "index.html")


@app.route("/api/v5/status")
def status():
    return jsonify({
        "service":  SERVICE_NAME,
        "version":  VERSION,
        "status":   "healthy",
        "hostname": socket.gethostname(),
    })


@app.route("/api/v5/legacy/media-info")
def media_info():
    file_id = request.args.get("file_id")
    if not file_id:
        return jsonify({"error": "missing parameter", "detail": "file_id is required"}), 400

    record = _MEDIA.get(str(file_id))
    if record is None:
        return jsonify({"error": "not_found", "file_id": file_id}), 404

    source_override = request.args.get("source")
    if source_override:
        v1_source = source_override
    else:
        v1_source = "http://internal-media-cdn.legacy/" + record["file_path"]

    v1_url = "http://{host}/api/v1/legacy/media-info?source={src}".format(
        host=SHADOW_API_HOST, src=v1_source,
    )

    try:
        backend = requests.get(v1_url, timeout=5)
        backend_body = backend.text
        backend_status = backend.status_code
    except requests.exceptions.RequestException as exc:
        backend_body = "<v1 backend unreachable: {}>".format(exc)
        backend_status = 502

    return jsonify({
        "file_id":         file_id,
        "metadata": {
            "customer_name":  record["customer_name"],
            "application_id": record["application_id"],
            "file_name":      record["file_name"],
            "uploaded_at":    record["uploaded_at"],
        },
        "internal_source":  v1_url,
        "backend_status":   backend_status,
        "backend_response": backend_body,
    })


@app.errorhandler(404)
def not_found(_e):
    return jsonify({"error": "not_found", "service": SERVICE_NAME}), 404


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)