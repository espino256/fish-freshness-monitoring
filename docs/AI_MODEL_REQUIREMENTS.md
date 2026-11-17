# AI model requirements

`assets/models/fish_freshness_model.tflite` is preserved but not deployed because its tensor metadata, class order, preprocessing specification, and evaluation evidence are absent. Supply a versioned label map, input shape/type and quantization details, preprocessing specification, and independent per-part test results before enabling inference. Train and validate gills, eyes, and skin/scales separately; do not reuse a gill model for another region without evidence.
