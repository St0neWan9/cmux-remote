#!/usr/bin/env swift
// Original geometric companion icon. No upstream branding or external assets.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let destination = URL(fileURLWithPath: "ios/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
let size = 1024
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
    bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.setFillColor(CGColor(red: 0.17, green: 0.35, blue: 0.95, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: size, height: size))
context.setStrokeColor(CGColor(gray: 1, alpha: 1))
context.setLineWidth(44)
context.setLineCap(.round)
context.setLineJoin(.round)
// A conversation window, with a prompt and connected phone in the foreground.
context.addPath(CGPath(roundedRect: CGRect(x: 184, y: 320, width: 550, height: 470),
    cornerWidth: 68, cornerHeight: 68, transform: nil))
context.strokePath()
context.move(to: CGPoint(x: 272, y: 640))
context.addLine(to: CGPoint(x: 334, y: 586))
context.addLine(to: CGPoint(x: 272, y: 532))
context.strokePath()
context.move(to: CGPoint(x: 378, y: 532))
context.addLine(to: CGPoint(x: 490, y: 532))
context.strokePath()
context.setFillColor(CGColor(red: 0.17, green: 0.35, blue: 0.95, alpha: 1))
let phone = CGPath(roundedRect: CGRect(x: 570, y: 190, width: 270, height: 450),
    cornerWidth: 54, cornerHeight: 54, transform: nil)
context.addPath(phone)
context.drawPath(using: .fillStroke)
context.move(to: CGPoint(x: 666, y: 260))
context.addLine(to: CGPoint(x: 744, y: 260))
context.strokePath()
let image = context.makeImage()!
let output = CGImageDestinationCreateWithURL(destination as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(output, image, nil)
precondition(CGImageDestinationFinalize(output), "Failed to save app icon")
