"""Run in the training environment to export an actual real-image Keras reference.

Requires TensorFlow and numpy. Does not train, convert, or overwrite any model.
Register the output directory in pubspec.yaml before running Flutter parity tests.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--keras", type=Path, required=True)
    parser.add_argument("--tflite", type=Path, required=True)
    parser.add_argument("--image", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True,
                        help="New directory, e.g. assets/ai_reference/gills")
    args = parser.parse_args()
    for path in (args.keras, args.tflite, args.image):
        if not path.is_file():
            parser.error(f"Input file is missing: {path}")
    if args.output.exists():
        parser.error("Choose a new output directory; existing files are never overwritten")

    import numpy as np
    import tensorflow as tf

    encoded = args.image.read_bytes()
    image = tf.io.decode_image(encoded, channels=3, expand_animations=False)
    tensor = tf.cast(tf.image.resize(image, [224, 224]), tf.float32)[None, ...].numpy()
    model = tf.keras.models.load_model(args.keras, compile=False)
    scores = np.asarray(model(tensor, training=False).numpy(), dtype=np.float32)
    if tensor.shape != (1, 224, 224, 3) or scores.shape != (1, 3) or not np.isfinite(scores).all():
        raise ValueError("Unexpected reference input/output contract")
    tensor_bytes = tensor.astype("<f4").tobytes()
    args.output.mkdir(parents=True)
    image_name = "input" + args.image.suffix.lower()
    shutil.copyfile(args.image, args.output / image_name)
    (args.output / "input.f32").write_bytes(tensor_bytes)
    # Paths are project-relative asset keys. Run from the Flutter project root,
    # or copy the directory there and adjust its manifest asset keys accordingly.
    report = {"modelFile": args.tflite.name,
              "modelSha256": digest(args.tflite.read_bytes()),
              "kerasSha256": digest(args.keras.read_bytes()),
              "imageAsset": (args.output / image_name).as_posix(),
              "imageSha256": digest(encoded),
              "tensorAsset": (args.output / "input.f32").as_posix(),
              "tensorSha256": digest(tensor_bytes),
              "tensorShape": list(tensor.shape),
              "kerasScores": scores[0].tolist(),
              "tensorflowVersion": tf.__version__,
              "scientificallyValidated": False}
    (args.output / "reference.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(f"Exported real-image reference to {args.output}. No freshness validation is claimed.")


if __name__ == "__main__":
    main()
