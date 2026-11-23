"""Read structural facts, not model validity, without an inference runtime.

Usage: python tools/inspect_tflite.py [path/to/model.tflite]
Field indices follow TensorFlow's v2.20.0 schema:
https://github.com/tensorflow/tensorflow/blob/v2.20.0/tensorflow/compiler/mlir/lite/schema/schema.fbs
This inspects the schema-v3 fields used here; it is not a FlatBuffer verifier.
"""

import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import zipfile
from collections import Counter


class Table:
    def __init__(self, data, position):
        self.data = data
        self.position = position
        self.vtable = position - self.read("i", position)

    def read(self, fmt, position):
        return struct.unpack_from("<" + fmt, self.data, position)[0]

    def field(self, index):
        entry = self.vtable + 4 + index * 2
        if entry >= self.vtable + self.read("H", self.vtable):
            return None
        offset = self.read("H", entry)
        return self.position + offset if offset else None

    def scalar(self, index, fmt="I", default=0):
        position = self.field(index)
        return self.read(fmt, position) if position is not None else default

    def indirect(self, position):
        return position + self.read("I", position)

    def string(self, index):
        position = self.field(index)
        if position is None:
            return None
        start = self.indirect(position)
        size = self.read("I", start)
        return self.data[start + 4:start + 4 + size].decode("utf-8")

    def vector(self, index, fmt="i"):
        position = self.field(index)
        if position is None:
            return []
        start = self.indirect(position)
        count = self.read("I", start)
        size = struct.calcsize("<" + fmt)
        return [self.read(fmt, start + 4 + size * i) for i in range(count)]

    def tables(self, index):
        position = self.field(index)
        if position is None:
            return []
        start = self.indirect(position)
        return [Table(self.data, self.indirect(start + 4 + 4 * i))
                for i in range(self.read("I", start))]

    def table(self, index):
        position = self.field(index)
        return Table(self.data, self.indirect(position)) if position else None


OPS = {0: "ADD", 1: "AVERAGE_POOL_2D", 3: "CONV_2D",
       4: "DEPTHWISE_CONV_2D", 6: "DEQUANTIZE", 9: "FULLY_CONNECTED",
       18: "MUL", 19: "RELU", 21: "RELU6", 22: "RESHAPE",
       25: "SOFTMAX", 32: "CUSTOM", 34: "PAD", 40: "MEAN",
       41: "SUB", 42: "DIV", 114: "QUANTIZE"}
TYPES = {0: "FLOAT32", 1: "FLOAT16", 2: "INT32", 3: "UINT8",
         4: "INT64", 9: "INT8"}


def inspect(path):
    data = path.read_bytes()
    if data[4:8] != b"TFL3":
        raise ValueError("Missing TFL3 identifier")
    model = Table(data, struct.unpack_from("<I", data)[0])
    codes = []
    for code in model.tables(1):
        number = max(code.scalar(0, "b"), code.scalar(3, "i"))
        codes.append({"code": number, "name": OPS.get(number, f"BUILTIN_{number}"),
                      "version": code.scalar(2, "i", 1), "custom": code.string(1)})
    buffers = model.tables(4)

    def tensor(t):
        quantization = t.table(4)
        return {"name": t.string(3), "shape": t.vector(0),
                "shape_signature": t.vector(7),
                "type": TYPES.get(t.scalar(1, "b"), t.scalar(1, "b")),
                "quantization_scales": quantization.vector(2, "f") if quantization else [],
                "quantization_zero_points": quantization.vector(3, "q") if quantization else []}

    graphs = []
    for graph in model.tables(2):
        tensors = graph.tables(0)
        operations = graph.tables(3)
        counts = Counter(codes[op.scalar(0)]["name"] for op in operations)
        first = []
        for op in operations[:5]:
            constants = []
            for index in op.vector(1):
                if index < 0:
                    continue
                t = tensors[index]
                raw = bytes(buffers[t.scalar(2)].vector(0, "B"))
                if raw and len(raw) <= 32 and t.scalar(1, "b") == 0:
                    constants.append({"name": t.string(3), "float32_values":
                                      list(struct.unpack("<" + "f" * (len(raw) // 4), raw))})
            first.append({"operator": codes[op.scalar(0)]["name"],
                          "inputs": [tensors[i].string(3) for i in op.vector(1) if i >= 0],
                          "small_float_constants": constants})
        graphs.append({"name": graph.string(4), "tensor_count": len(tensors),
                       "inputs": [tensor(tensors[i]) for i in graph.vector(1)],
                       "outputs": [tensor(tensors[i]) for i in graph.vector(2)],
                       "operator_count": len(operations), "operator_counts": dict(counts),
                       "first_operators": first,
                       "last_operator": codes[operations[-1].scalar(0)]["name"] if operations else None})
    metadata = []
    for entry in model.tables(6):
        raw = bytes(buffers[entry.scalar(1)].vector(0, "B"))
        metadata.append({"name": entry.string(0), "size": len(raw),
                         "ascii_strings": [s.decode("ascii") for s in re.findall(rb"[ -~]{4,}", raw)]})
    return {"path": path.as_posix(), "size_bytes": len(data),
            "sha256": hashlib.sha256(data).hexdigest(), "identifier": "TFL3",
            "schema_version": model.scalar(0), "description": model.string(3),
            "operator_codes": codes, "subgraphs": graphs, "metadata": metadata,
            "associated_zip_files": zipfile.ZipFile(path).namelist() if zipfile.is_zipfile(path) else [],
            "runtime_inference_tested": False}


def smoke_test(path):
    """Optional execution check; synthetic inputs do not validate classification."""
    import numpy as np
    from ai_edge_litert.interpreter import Interpreter

    interpreter = Interpreter(model_path=str(path), num_threads=1)
    interpreter.allocate_tensors()
    inputs = interpreter.get_input_details()
    outputs = interpreter.get_output_details()
    if len(inputs) != 1 or len(outputs) != 1 or inputs[0]["dtype"] != np.float32:
        raise ValueError("Smoke test requires one float32 input and one output")
    shape = tuple(inputs[0]["shape"])
    results = []
    samples = {"zero": np.zeros(shape, dtype=np.float32),
               "255": np.full(shape, 255, dtype=np.float32),
               "ramp": np.linspace(0, 255, int(np.prod(shape)), dtype=np.float32).reshape(shape)}
    for name, values in samples.items():
        interpreter.set_tensor(inputs[0]["index"], values)
        interpreter.invoke()
        scores = interpreter.get_tensor(outputs[0]["index"])
        interpreter.invoke()
        repeated = interpreter.get_tensor(outputs[0]["index"])
        finite = bool(np.isfinite(scores).all() and np.isfinite(repeated).all())
        if not finite:
            raise ValueError(f"Non-finite output for {name}")
        results.append({"synthetic_input": name, "output_shape": list(scores.shape),
                        "finite": finite, "sum": float(scores.sum()),
                        "repeat_max_absolute_difference": float(np.max(np.abs(scores - repeated)))})
    return {"runtime": "ai-edge-litert", "synthetic_checks": results,
            "scientific_validation": False,
            "flutter_or_mobile_inference_tested": False}


def specialize_batch_one(original):
    """Independent reference for the browser's in-memory metadata binding."""
    if original[4:8] != b"TFL3":
        raise ValueError("Missing TFL3 identifier")
    data = bytearray(original)
    model = Table(data, struct.unpack_from("<I", data)[0])
    modified = []
    for graph in model.tables(2):
        for tensor in graph.tables(0):
            shape, signature = tensor.vector(0), tensor.vector(7)
            if not signature:
                continue
            if len(shape) != len(signature):
                raise ValueError("Inconsistent shape signature")
            start = tensor.indirect(tensor.field(7)) + 4
            for axis, (concrete, declared) in enumerate(zip(shape, signature)):
                if declared == -1 and axis == 0 and concrete == 1:
                    struct.pack_into("<i", data, start + axis * 4, 1)
                    modified.append(start + axis * 4)
                elif declared != concrete:
                    raise ValueError("Only dynamic batch-one specialization is supported")
    return bytes(data), modified


def check_batch_one(path):
    import numpy as np
    from ai_edge_litert.interpreter import Interpreter

    original = path.read_bytes()
    specialized, positions = specialize_batch_one(original)
    allowed = {p + i for p in positions for i in range(4)}
    changed = {i for i, (a, b) in enumerate(zip(original, specialized)) if a != b}
    if not changed.issubset(allowed) or len(original) != len(specialized):
        raise ValueError("Changes outside batch metadata")
    sample = np.empty((1, 224, 224, 3), dtype=np.float32)
    y, x = np.indices((224, 224))
    sample[0, :, :, 0], sample[0, :, :, 1], sample[0, :, :, 2] = x, (x + y) % 256, y
    outputs = []
    for content in (original, specialized):
        interpreter = Interpreter(model_content=content, num_threads=1)
        interpreter.allocate_tensors()
        interpreter.set_tensor(interpreter.get_input_details()[0]["index"], sample)
        interpreter.invoke()
        outputs.append(interpreter.get_tensor(interpreter.get_output_details()[0]["index"]))
    difference = float(np.max(np.abs(outputs[0] - outputs[1])))
    if not np.array_equal(outputs[0], outputs[1]):
        raise ValueError(f"Batch specialization changed outputs: {difference}")
    return {"model": path.name, "signature_fields_bound": len(positions),
            "changed_bytes": len(changed), "changes_confined_to_batch_metadata": True,
            "specialized_sha256": hashlib.sha256(specialized).hexdigest(),
            "max_absolute_difference": difference, "original_scores": outputs[0][0].tolist(),
            "scientifically_validated": False}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("model", nargs="?", default="assets/models/fish_freshness_model.tflite")
    parser.add_argument("--smoke-test", action="store_true",
                        help="Requires ai-edge-litert and numpy; does not validate freshness")
    parser.add_argument("--check-batch-one", action="store_true",
                        help="Compare the untouched model and browser metadata specialization")
    arguments = parser.parse_args()
    model_path = Path(arguments.model)
    report = inspect(model_path)
    if arguments.smoke_test:
        report["runtime_smoke_test"] = smoke_test(model_path)
        report["runtime_inference_tested"] = True
    if arguments.check_batch_one:
        report["batch_one_equivalence"] = check_batch_one(model_path)
        report["runtime_inference_tested"] = True
    print(json.dumps(report, indent=2))
