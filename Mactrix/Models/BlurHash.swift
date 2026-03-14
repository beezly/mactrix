// BlurHash encoder for macOS (CGImage-based)
// Based on https://github.com/woltapp/blurhash (MIT licence)

import AppKit

extension NSImage {
    func blurHash(numberOfComponents components: (Int, Int)) -> String? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let width = cgImage.width
        let height = cgImage.height

        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return nil }
        let pixels = data.assumingMemoryBound(to: UInt8.self)

        var factors: [(Float, Float, Float)] = []
        for j in 0..<components.1 {
            for i in 0..<components.0 {
                let normalisation: Float = (i == 0 && j == 0) ? 1 : 2
                let factor = multiplyBasisFunction(pixels: pixels, width: width, height: height, bytesPerRow: width * 4) {
                    normalisation * cos(Float.pi * Float(i) * $0 / Float(width)) * cos(Float.pi * Float(j) * $1 / Float(height))
                }
                factors.append(factor)
            }
        }

        let dc = factors.first!
        let ac = factors.dropFirst()

        var hash = ""
        hash += (components.0 - 1 + (components.1 - 1) * 9).encode83(length: 1)

        let maximumValue: Float
        if !ac.isEmpty {
            let actualMax = ac.map { max(abs($0.0), abs($0.1), abs($0.2)) }.max()!
            let quantised = Int(max(0, min(82, floor(actualMax * 166 - 0.5))))
            maximumValue = Float(quantised + 1) / 166
            hash += quantised.encode83(length: 1)
        } else {
            maximumValue = 1
            hash += 0.encode83(length: 1)
        }

        hash += encodeDC(dc).encode83(length: 4)
        for factor in ac {
            hash += encodeAC(factor, maximumValue: maximumValue).encode83(length: 2)
        }
        return hash
    }
}

private func multiplyBasisFunction(pixels: UnsafePointer<UInt8>, width: Int, height: Int, bytesPerRow: Int, basisFunction: (Float, Float) -> Float) -> (Float, Float, Float) {
    var r: Float = 0, g: Float = 0, b: Float = 0
    for y in 0..<height {
        for x in 0..<width {
            let basis = basisFunction(Float(x), Float(y))
            let offset = 4 * x + y * bytesPerRow
            r += basis * sRGBToLinear(pixels[offset])
            g += basis * sRGBToLinear(pixels[offset + 1])
            b += basis * sRGBToLinear(pixels[offset + 2])
        }
    }
    let scale = 1 / Float(width * height)
    return (r * scale, g * scale, b * scale)
}

private func encodeDC(_ value: (Float, Float, Float)) -> Int {
    (linearTosRGB(value.0) << 16) + (linearTosRGB(value.1) << 8) + linearTosRGB(value.2)
}

private func encodeAC(_ value: (Float, Float, Float), maximumValue: Float) -> Int {
    let qR = Int(max(0, min(18, floor(signPow(value.0 / maximumValue, 0.5) * 9 + 9.5))))
    let qG = Int(max(0, min(18, floor(signPow(value.1 / maximumValue, 0.5) * 9 + 9.5))))
    let qB = Int(max(0, min(18, floor(signPow(value.2 / maximumValue, 0.5) * 9 + 9.5))))
    return qR * 19 * 19 + qG * 19 + qB
}

private func signPow(_ value: Float, _ exp: Float) -> Float {
    copysign(pow(abs(value), exp), value)
}

private func linearTosRGB(_ value: Float) -> Int {
    let v = max(0, min(1, value))
    return v <= 0.0031308
        ? Int(v * 12.92 * 255 + 0.5)
        : Int((1.055 * pow(v, 1 / 2.4) - 0.055) * 255 + 0.5)
}

private func sRGBToLinear(_ value: UInt8) -> Float {
    let v = Float(value) / 255
    return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
}

private let encodeCharacters: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-./:;=?@[]^_{|}~")

extension Int {
    fileprivate func encode83(length: Int) -> String {
        var result = ""
        for i in 1...length {
            var divisor = 1
            for _ in 0..<(length - i) { divisor *= 83 }
            let digit = (self / divisor) % 83
            result.append(encodeCharacters[digit])
        }
        return result
    }
}
