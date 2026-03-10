#!/usr/bin/env python3
import torch
import numpy as np
from pathlib import Path
from PIL import Image
import io
import base64
from flask import Flask, request, jsonify
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

MODEL = None
DEVICE = None
INPUT_SIZE = 518
CALIBRATION_VALUE = 147.0
CALIBRATION_DISTANCE = 6.0

def load_model():
    global MODEL, DEVICE
    if MODEL is not None:
        return
    
    if torch.cuda.is_available():
        DEVICE = torch.device("cuda")
        logger.info(f"Using GPU: {torch.cuda.get_device_name(0)}")
    else:
        DEVICE = torch.device("cpu")
        logger.info("Using CPU")
    
    try:
        from transformers import AutoModelForDepthEstimation, AutoImageProcessor
        logger.info("Loading model...")
        MODEL = AutoModelForDepthEstimation.from_pretrained("LiheYoung/depth-anything-small-hf")
        MODEL.to(DEVICE)
        MODEL.eval()
        logger.info("Model loaded successfully")
    except Exception as e:
        logger.error(f"Failed to load model: {e}")
        raise

def calibrate_depth(raw_value):
    if raw_value == 0:
        return 0.0
    return (raw_value / CALIBRATION_VALUE) * CALIBRATION_DISTANCE

@app.route('/health', methods=['GET'])
def health():
    return jsonify({'status': 'ok', 'device': str(DEVICE)})

@app.route('/estimate_depth', methods=['POST'])
def estimate_depth():
    if MODEL is None:
        load_model()
    
    try:
        data = request.get_json()
        image_data = base64.b64decode(data.get('image', ''))
        image = Image.open(io.BytesIO(image_data)).convert('RGB')
        image = image.resize((INPUT_SIZE, INPUT_SIZE))
        
        image_np = np.array(image, dtype=np.float32) / 255.0
        image_tensor = torch.from_numpy(image_np.transpose(2, 0, 1)).unsqueeze(0).to(DEVICE)
        
        with torch.no_grad():
            output = MODEL(image_tensor)
            depth_map = output.predicted_depth
        
        depth_value = depth_map.cpu().numpy().max()
        calibrated = calibrate_depth(float(depth_value))
        
        return jsonify({
            'depth': calibrated,
            'raw': float(depth_value)
        })
    except Exception as e:
        logger.error(f"Error estimating depth: {e}")
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    load_model()
    app.run(host='127.0.0.1', port=5000, debug=False)
