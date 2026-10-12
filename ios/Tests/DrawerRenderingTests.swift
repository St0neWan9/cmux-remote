import XCTest
import SwiftUI
@testable import CmuxRemote

@MainActor
final class DrawerRenderingTests: XCTestCase {
    func testOpenDrawerShadowReachesBothUnsafeScreenEdges() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let appeared = expectation(description: "Drawer mounted")
        let host = UIHostingController(rootView:
            SideDrawer(isPresented: .constant(true)) { Color.white } drawer: { Color.white }
                .onAppear { appeared.fulfill() }
        )
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        await fulfillment(of: [appeared], timeout: 5)
        host.view.layoutIfNeeded()
        XCTAssertGreaterThan(host.view.safeAreaInsets.top, 20)
        XCTAssertGreaterThan(host.view.safeAreaInsets.bottom, 10)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: host.view.bounds.size, format: format).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let cg = try XCTUnwrap(image.cgImage)
        var pixels = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: cg.width, height: cg.height,
                bitsPerComponent: 8, bytesPerRow: cg.width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        }
        let edge = Int(min(440, host.view.bounds.width * 0.77))
        for y in [12, cg.height - 13] {
            let darkest = ((edge - 45)...(edge + 50)).map { pixels[(y * cg.width + $0) * 4] }.min()!
            XCTAssertLessThan(darkest, 252, "Shadow must reach screen edge at y=\(y), not stop at the safe area")
        }
        let attachment = XCTAttachment(image: image); attachment.name = "drawer-full-height"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
