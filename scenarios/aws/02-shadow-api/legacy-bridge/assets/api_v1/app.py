from flask import Flask, request, jsonify, Response
import requests
import socket

app = Flask(__name__)

SERVICE_NAME = "Internal Manager (v1 Shadow)"
VERSION      = "1.0.4"


@app.route("/")
def index():
    return jsonify({
        "service":  SERVICE_NAME,
        "version":  VERSION,
        "status":   "ok",
        "note":     "Internal-only legacy v1 surface. Not exposed to Internet.",
    })


@app.route("/api/v1/health")
def health():
    return jsonify({"status": "healthy", "hostname": socket.gethostname()})


@app.route("/api/v1/legacy/media-info")
def media_info():
    src = request.args.get("source")
    if not src:
        return jsonify({"error": "missing parameter", "detail": "source is required"}), 400

    try:
        r = requests.get(src, timeout=5)
    except requests.exceptions.RequestException as exc:
        return jsonify({"error": "fetch_failed", "detail": str(exc), "source": src}), 502

    content_type = r.headers.get("Content-Type", "text/plain")
    return Response(r.content, status=r.status_code, mimetype=content_type)


@app.errorhandler(404)
def not_found(_e):
    return jsonify({"error": "not_found", "service": SERVICE_NAME}), 404


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)