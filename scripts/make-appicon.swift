#!/usr/bin/env swift
//
// アプリアイコン（1024x1024 PNG）を生成する。
//
//   swift scripts/make-appicon.swift
//
// 出力先: ios/VocabBlossom/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png
// 図柄は assets/icon.svg と揃えている（5 枚の花びら + 中心）。
//

import AppKit
import CoreGraphics
import Foundation

let size = 1024
let scale = CGFloat(size) / 100  // SVG の 100x100 座標系に合わせる

let background = CGColor(red: 0.992, green: 0.949, blue: 0.973, alpha: 1)  // #fdf2f8
let petal = CGColor(red: 0.976, green: 0.659, blue: 0.831, alpha: 1)  // #f9a8d4
let center = CGColor(red: 0.984, green: 0.749, blue: 0.141, alpha: 1)  // #fbbf24

guard let context = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fatalError("描画コンテキストを作れませんでした")
}

// 背景（角丸はシステムがマスクするため、全面を塗る）
context.setFillColor(background)
context.fill(CGRect(x: 0, y: 0, width: size, height: size))

func circle(x: CGFloat, y: CGFloat, r: CGFloat, color: CGColor) {
    context.setFillColor(color)
    // SVG は左上原点、CoreGraphics は左下原点なので y を反転する
    let rect = CGRect(
        x: (x - r) * scale,
        y: (100 - y - r) * scale,
        width: r * 2 * scale,
        height: r * 2 * scale
    )
    context.fillEllipse(in: rect)
}

circle(x: 50, y: 29, r: 14, color: petal)
circle(x: 70, y: 43, r: 14, color: petal)
circle(x: 62, y: 66, r: 14, color: petal)
circle(x: 38, y: 66, r: 14, color: petal)
circle(x: 30, y: 43, r: 14, color: petal)
circle(x: 50, y: 49, r: 11, color: center)

guard let image = context.makeImage() else {
    fatalError("画像を作れませんでした")
}

let output = URL(fileURLWithPath: "ios/VocabBlossom/Resources/Assets.xcassets")
    .appendingPathComponent("AppIcon.appiconset/icon-1024.png")
let bitmap = NSBitmapImageRep(cgImage: image)
guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("PNG に変換できませんでした")
}
try data.write(to: output)
print("wrote \(output.path)")
