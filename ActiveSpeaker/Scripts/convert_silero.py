"""
Convert Silero VAD ONNX model to CoreML .mlpackage format.

Usage:
    pip install coremltools onnx numpy
    python convert_silero.py

The script will:
1. Download silero_vad.onnx if not present
2. Convert to CoreML with fixed shapes (no dynamic dimensions)
3. Save as SileroVAD.mlpackage

Copy the resulting SileroVAD.mlpackage into the Xcode project's Models/ folder.
"""

import os
import urllib.request
import numpy as np
import coremltools as ct

MODEL_URL = "https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx"
ONNX_PATH = "silero_vad.onnx"
OUTPUT_PATH = "SileroVAD.mlpackage"


def download_model():
    if os.path.exists(ONNX_PATH):
        print(f"Found existing {ONNX_PATH}")
        return
    print(f"Downloading Silero VAD ONNX model...")
    urllib.request.urlretrieve(MODEL_URL, ONNX_PATH)
    print("Download complete.")


def convert():
    print("Converting ONNX to CoreML...")

    mlmodel = ct.convert(
        ONNX_PATH,
        inputs=[
            ct.TensorType(name="input", shape=(1, 576), dtype=np.float32),
            ct.TensorType(name="state", shape=(2, 1, 128), dtype=np.float32),
            ct.TensorType(name="sr", shape=(1,), dtype=np.int64),
        ],
        outputs=[
            ct.TensorType(name="output", dtype=np.float32),
            ct.TensorType(name="stateOut", dtype=np.float32),
        ],
        minimum_deployment_target=ct.target.iOS16,
        compute_units=ct.ComputeUnit.CPU_ONLY,
    )

    mlmodel.author = "Silero Team (converted for iOS)"
    mlmodel.short_description = "Silero VAD v4 — Voice Activity Detection"
    mlmodel.save(OUTPUT_PATH)
    print(f"Saved to {OUTPUT_PATH}")
    print(f"Copy {OUTPUT_PATH} into your Xcode project's Models/ folder.")


if __name__ == "__main__":
    download_model()
    convert()
