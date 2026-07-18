// Train the community category classifier (Create ML, macOS only).
//
// Input: a CSV with `text,label` columns (from build_category_corpus.py).
// Output: CategoryClassifier.mlmodel + metrics.json in the output directory.
//
// Run:  swift tools/train_category_classifier.swift corpus.csv out/
//
// This is the deferred "real ML" leg of docs/LEARNING_IMPROVEMENTS.md — the
// app does NOT bundle this model yet. When accuracy clears the bar (see
// metrics.json), wire it into CategoryClassifier.swift as a lane above the
// NLEmbedding nearest-neighbor fallback.

import CreateML
import Foundation

let args = CommandLine.arguments
guard args.count == 3 else {
    print("usage: swift train_category_classifier.swift <corpus.csv> <output-dir>")
    exit(1)
}
let corpusURL = URL(fileURLWithPath: args[1])
let outputDir = URL(fileURLWithPath: args[2])
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let table = try MLDataTable(contentsOf: corpusURL)
print("corpus rows: \(table.rows.count)")

let (trainingData, testingData) = table.randomSplit(by: 0.85, seed: 42)
let classifier = try MLTextClassifier(
    trainingData: trainingData,
    textColumn: "text",
    labelColumn: "label"
)

let evaluation = classifier.evaluation(on: testingData, textColumn: "text", labelColumn: "label")
let accuracy = (1.0 - evaluation.classificationError) * 100

let metrics: [String: Any] = [
    "trainingRows": trainingData.rows.count,
    "testingRows": testingData.rows.count,
    "accuracyPercent": accuracy,
    "trainingAccuracyPercent": (1.0 - classifier.trainingMetrics.classificationError) * 100,
    "validationAccuracyPercent": (1.0 - classifier.validationMetrics.classificationError) * 100,
]
let metricsData = try JSONSerialization.data(withJSONObject: metrics, options: [.prettyPrinted, .sortedKeys])
try metricsData.write(to: outputDir.appendingPathComponent("metrics.json"))
print("test accuracy: \(String(format: "%.1f", accuracy))%")

let metadata = MLModelMetadata(
    author: "PaperTrail community learning pipeline",
    shortDescription: "Category from merchant + product text, trained on anonymized community corrections",
    version: ISO8601DateFormatter().string(from: .now)
)
try classifier.write(to: outputDir.appendingPathComponent("CategoryClassifier.mlmodel"), metadata: metadata)
print("wrote \(outputDir.path)/CategoryClassifier.mlmodel")
