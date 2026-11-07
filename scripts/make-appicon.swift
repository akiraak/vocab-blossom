#!/usr/bin/env swift
//
// アプリアイコン（1024x1024 PNG）を生成する。
//
//   swift scripts/make-appicon.swift
//
// 出力先: ios/VocabBlossom/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png
// 図柄は assets/icon.svg と揃えている（白地に地平線と、つぼみ・花・芽の線画。2026-11-07 のデザイン）。
//

import AppKit
import CoreGraphics
import Foundation

let size = 1024
let scale = CGFloat(size) / 100  // SVG の 100x100 座標系に合わせる

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

let background = rgb(0xFFFFFF)
let ground = rgb(0xC9C9C4)
let bud = rgb(0x7FA38A)
let blossom = rgb(0x3F6B4C)
let sprout = rgb(0x9DBBA5)

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

// 以降は SVG と同じ「左上原点・100x100」の座標で描く
context.translateBy(x: 0, y: CGFloat(size))
context.scaleBy(x: scale, y: -scale)
context.setLineCap(.round)
context.setLineJoin(.round)

func stroke(_ color: CGColor, width: CGFloat, _ build: (CGMutablePath) -> Void) {
    let path = CGMutablePath()
    build(path)
    context.addPath(path)
    context.setStrokeColor(color)
    context.setLineWidth(width)
    context.strokePath()
}

// 地平線
stroke(ground, width: 1.8) { path in
    path.move(to: CGPoint(x: 16, y: 76))
    path.addLine(to: CGPoint(x: 84, y: 76))
}

// 左: つぼみ
stroke(bud, width: 2.4) { path in
    path.move(to: CGPoint(x: 33, y: 76))
    path.addLine(to: CGPoint(x: 33, y: 51.2))
    path.addEllipse(in: CGRect(x: 33 - 3.6, y: 45 - 6.2, width: 7.2, height: 12.4))
}

// まん中: 花
stroke(blossom, width: 2.4) { path in
    path.move(to: CGPoint(x: 50, y: 76))
    path.addLine(to: CGPoint(x: 50, y: 35.5))
    path.move(to: CGPoint(x: 50, y: 64))
    path.addCurve(to: CGPoint(x: 37.6, y: 54), control1: CGPoint(x: 43, y: 64), control2: CGPoint(x: 38.5, y: 60))
    path.addCurve(to: CGPoint(x: 50, y: 64), control1: CGPoint(x: 44, y: 54.2), control2: CGPoint(x: 48.8, y: 58))
    path.closeSubpath()
    path.addEllipse(in: CGRect(x: 50 - 8.5, y: 27 - 8.5, width: 17, height: 17))
}
context.setFillColor(blossom)
context.fillEllipse(in: CGRect(x: 50 - 2.4, y: 27 - 2.4, width: 4.8, height: 4.8))

// 右: 芽
stroke(sprout, width: 2.4) { path in
    path.move(to: CGPoint(x: 67, y: 76))
    path.addLine(to: CGPoint(x: 67, y: 64))
    path.move(to: CGPoint(x: 67, y: 68))
    path.addCurve(to: CGPoint(x: 72.6, y: 63.4), control1: CGPoint(x: 70, y: 68), control2: CGPoint(x: 72.4, y: 66.2))
    path.addCurve(to: CGPoint(x: 67, y: 68), control1: CGPoint(x: 69.8, y: 63.6), control2: CGPoint(x: 67.4, y: 65.2))
    path.closeSubpath()
}

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
