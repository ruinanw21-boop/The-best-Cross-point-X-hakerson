#!/bin/sh
set -eu

source_dir="$SRCROOT/CampusCards/Resources/OfflineSpeech"
bundle_dir="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/OfflineSpeech"
model=openai_whisper-base
mkdir -p "$bundle_dir"

# Device builds use the verified Argmax artifacts directly. An unprepared
# checkout still builds the app with its typing and recording fallback.
if [ "$PLATFORM_NAME" != iphonesimulator ] || [ ! -d "$source_dir/$model" ]; then
    /usr/bin/rsync -a --delete "$source_dir/" "$bundle_dir/"
    exit 0
fi

# Compile the original model programs against this Xcode's simulator
# runtime. Each model.mlmodel resolves its FP16 weights in the adjacent
# weights/ directory. Keep the bundled tokenizer and mel frontend intact.
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
mkdir -p "$staging/OfflineSpeech/$model" "$staging/compiler"
/usr/bin/rsync -a --exclude="/$model/AudioEncoder.mlmodelc" \
    --exclude="/$model/TextDecoder.mlmodelc" "$source_dir/" "$staging/OfflineSpeech/"
for component in AudioEncoder TextDecoder; do
    xcrun coremlcompiler compile "$source_dir/$model/$component.mlmodelc/model.mlmodel" "$staging/compiler"
    mv "$staging/compiler/model.mlmodelc" "$staging/OfflineSpeech/$model/$component.mlmodelc"
done
/usr/bin/rsync -a --delete "$staging/OfflineSpeech/" "$bundle_dir/"
