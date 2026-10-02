#!/bin/sh
# Downloads Apple's Core ML Depth Anything V2 Small (Apache-2.0), which Create uses for parallax motion.
# The app builds without it and falls back to a plain push-in.
set -e
name=DepthAnythingV2SmallF16P6
base="https://huggingface.co/apple/coreml-depth-anything-v2-small/resolve/main/$name.mlpackage"
dest="$(dirname "$0")/../LiveWall/Resources/Models/$name.mlpackage"
for file in Manifest.json Data/com.apple.CoreML/model.mlmodel Data/com.apple.CoreML/weights/weight.bin; do
    mkdir -p "$(dirname "$dest/$file")"
    curl -fL --progress-bar "$base/$file" -o "$dest/$file"
done
echo "Saved $dest"
