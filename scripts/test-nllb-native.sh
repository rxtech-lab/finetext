#!/bin/bash
# Run after scripts/build.sh has compiled the native package dependencies.
# Downloads ~1.34 GB of NLLB weights into build/NLLBModels on the first run.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED="$ROOT/build/DerivedData"
PRODUCTS="$DERIVED/Build/Products/Debug"
CHECKOUTS="$DERIVED/SourcePackages/checkouts"
ORT="$DERIVED/SourcePackages/artifacts/onnxruntime-swift-package-manager/onnxruntime/onnxruntime.xcframework/macos-arm64_x86_64"
OBJECTS=()
for module in Tokenizers Hub HuggingFace Jinja OrderedCollections InternalCollectionsUtilities Crypto yyjson EventSource OnnxRuntimeBindings; do
  OBJECTS+=("$PRODUCTS/$module.o")
done
xcrun swiftc -parse-as-library -swift-version 6 -target arm64-apple-macos26.0 \
  -I "$PRODUCTS" -I "$CHECKOUTS/yyjson/src" \
  -I "$CHECKOUTS/onnxruntime-swift-package-manager/objectivec/include" \
  -Xcc "-fmodule-map-file=$DERIVED/Build/Intermediates.noindex/GeneratedModuleMaps/OnnxRuntimeBindings.modulemap" \
  -Xcc "-fmodule-map-file=$DERIVED/Build/Intermediates.noindex/GeneratedModuleMaps/yyjson.modulemap" \
  -F "$ORT" -framework onnxruntime -framework Security -framework SystemConfiguration \
  -lc++ -lresolv "${OBJECTS[@]}" \
  "$ROOT/FineText/Services/NLLB.swift" "$ROOT/scripts/tests/NLLBNativeSmoke.swift" \
  -o "$ROOT/build/nllb-native-smoke"
"$ROOT/build/nllb-native-smoke" "$ROOT/build/NLLBModels"
