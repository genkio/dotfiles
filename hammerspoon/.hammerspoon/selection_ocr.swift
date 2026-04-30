#!/usr/bin/env swift

// OCR helper for hammerspoon/selection_ocr.lua.
//
// Hammerspoon captures a selected screen region to an image file, then invokes
// this script with that path. The script runs Apple's Vision OCR locally,
// normalizes recognized chunks into readable lines with Japanese and English
// support, and prints the final text to stdout for Hammerspoon to copy.

import CoreGraphics
import Foundation
import Vision

struct TextChunk {
  let text: String
  let minX: CGFloat
  let maxX: CGFloat
  let midY: CGFloat
}

enum OCRScriptError: LocalizedError {
  case missingImagePath
  case unreadableImage(String)
  case noTextFound

  var errorDescription: String? {
    switch self {
    case .missingImagePath:
      return "usage: selection_ocr.swift <image-path>"
    case let .unreadableImage(path):
      return "image not found: \(path)"
    case .noTextFound:
      return "no text found"
    }
  }
}

private let lineThreshold: CGFloat = 0.025
private let chunkGapThreshold: CGFloat = 0.012
private let recognitionLanguages = ["ja-JP", "en-US"]

func isASCIIWord(_ scalar: Unicode.Scalar) -> Bool {
  CharacterSet.alphanumerics.contains(scalar) && scalar.isASCII
}

func shouldInsertSpaceBetweenLines(_ left: String, _ right: String) -> Bool {
  guard let leftScalar = left.unicodeScalars.last, let rightScalar = right.unicodeScalars.first else {
    return false
  }

  return isASCIIWord(leftScalar) && isASCIIWord(rightScalar)
}

func normalizedLine(from chunks: [TextChunk]) -> String {
  var result = ""
  var previousChunk: TextChunk? = nil

  for chunk in chunks.sorted(by: { $0.minX < $1.minX }) {
    if let previousChunk, chunk.minX - previousChunk.maxX > chunkGapThreshold {
      result.append(" ")
    }

    result.append(chunk.text)
    previousChunk = chunk
  }

  return result.trimmingCharacters(in: .whitespacesAndNewlines)
}

func normalizedText(from chunks: [TextChunk]) -> String {
  let sortedChunks = chunks.sorted { lhs, rhs in
    if abs(lhs.midY - rhs.midY) > lineThreshold {
      return lhs.midY > rhs.midY
    }

    return lhs.minX < rhs.minX
  }

  var lines: [[TextChunk]] = []
  var linePositions: [CGFloat] = []

  for chunk in sortedChunks {
    if let lastMidY = linePositions.last, abs(lastMidY - chunk.midY) <= lineThreshold {
      lines[lines.count - 1].append(chunk)
      linePositions[linePositions.count - 1] = (lastMidY + chunk.midY) / 2
      continue
    }

    lines.append([chunk])
    linePositions.append(chunk.midY)
  }

  let normalizedLines = lines
    .map(normalizedLine(from:))
    .filter { !$0.isEmpty }

  guard let firstLine = normalizedLines.first else {
    return ""
  }

  return normalizedLines.dropFirst().reduce(firstLine) { partialResult, line in
    if shouldInsertSpaceBetweenLines(partialResult, line) {
      return partialResult + " " + line
    }

    return partialResult + line
  }
}

func recognizeText(at imageURL: URL) throws -> String {
  guard FileManager.default.fileExists(atPath: imageURL.path) else {
    throw OCRScriptError.unreadableImage(imageURL.path)
  }

  let request = VNRecognizeTextRequest()
  request.recognitionLevel = .accurate
  request.recognitionLanguages = recognitionLanguages
  request.usesLanguageCorrection = true

  let handler = VNImageRequestHandler(url: imageURL, options: [:])
  try handler.perform([request])

  let chunks = (request.results ?? []).compactMap { observation -> TextChunk? in
    guard let candidate = observation.topCandidates(1).first else {
      return nil
    }

    let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)

    if text.isEmpty {
      return nil
    }

    return TextChunk(
      text: text,
      minX: observation.boundingBox.minX,
      maxX: observation.boundingBox.maxX,
      midY: observation.boundingBox.midY
    )
  }

  let text = normalizedText(from: chunks)

  if text.isEmpty {
    throw OCRScriptError.noTextFound
  }

  return text
}

do {
  guard let imagePath = CommandLine.arguments.dropFirst().first else {
    throw OCRScriptError.missingImagePath
  }

  let text = try recognizeText(at: URL(fileURLWithPath: imagePath))
  FileHandle.standardOutput.write(Data(text.utf8))
} catch {
  let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
  FileHandle.standardError.write(Data(message.utf8))
  exit(1)
}
