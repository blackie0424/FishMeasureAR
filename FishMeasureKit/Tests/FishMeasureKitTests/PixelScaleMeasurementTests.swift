import XCTest
@testable import FishMeasureKit

/// 照片像素 + 已知尺寸比例尺 → 魚長換算(比例尺步驟的核心數學)。
final class PixelScaleMeasurementTests: XCTestCase {

    func testStraightLineConversion() {
        // 魚線 300px,比例尺 100px 對應 10cm → 魚長 30cm
        let length = PixelScaleMeasurement.lengthCM(
            fishA: PlanePoint(x: 0, y: 0), fishB: PlanePoint(x: 300, y: 0),
            scaleA: PlanePoint(x: 0, y: 50), scaleB: PlanePoint(x: 100, y: 50),
            scaleLengthCM: 10)
        XCTAssertEqual(length!, 30.0, accuracy: 1e-9)
    }

    func testDiagonalDistancesUsePythagoras() {
        // 魚線 3-4-5 三角形 → 500px;比例尺 100px = 8cm → 40cm
        let length = PixelScaleMeasurement.lengthCM(
            fishA: PlanePoint(x: 100, y: 100), fishB: PlanePoint(x: 400, y: 500),
            scaleA: PlanePoint(x: 10, y: 10), scaleB: PlanePoint(x: 110, y: 10),
            scaleLengthCM: 8)
        XCTAssertEqual(length!, 40.0, accuracy: 1e-9)
    }

    func testDegenerateScaleBarReturnsNil() {
        // 比例尺兩端重合(0px)不可換算
        let length = PixelScaleMeasurement.lengthCM(
            fishA: PlanePoint(x: 0, y: 0), fishB: PlanePoint(x: 300, y: 0),
            scaleA: PlanePoint(x: 50, y: 50), scaleB: PlanePoint(x: 50, y: 50),
            scaleLengthCM: 10)
        XCTAssertNil(length)
    }

    func testNonPositiveScaleLengthReturnsNil() {
        let length = PixelScaleMeasurement.lengthCM(
            fishA: PlanePoint(x: 0, y: 0), fishB: PlanePoint(x: 300, y: 0),
            scaleA: PlanePoint(x: 0, y: 50), scaleB: PlanePoint(x: 100, y: 50),
            scaleLengthCM: 0)
        XCTAssertNil(length)
    }

    func testCMPerPixelRescaling() {
        // AR 已測得 45cm、線長 900px → 拖曳端點後 800px 應為 40cm
        let cmPerPx = PixelScaleMeasurement.cmPerPixel(
            lengthCM: 45,
            pointA: PlanePoint(x: 0, y: 0), pointB: PlanePoint(x: 900, y: 0))
        XCTAssertEqual(cmPerPx!, 0.05, accuracy: 1e-9)
        let adjusted = PixelScaleMeasurement.length(
            from: PlanePoint(x: 0, y: 0), to: PlanePoint(x: 800, y: 0),
            cmPerPixel: cmPerPx!)
        XCTAssertEqual(adjusted, 40.0, accuracy: 1e-9)
    }

    func testPixelLengthForRealWorldCM() {
        // 疊圖用:cm/px = 0.05 時,26cm 的藍白拖 → 520px
        XCTAssertEqual(PixelScaleMeasurement.pixelLength(forCM: 26, cmPerPixel: 0.05)!,
                       520, accuracy: 1e-9)
    }

    func testPixelLengthGuardsInvalidInput() {
        XCTAssertNil(PixelScaleMeasurement.pixelLength(forCM: 26, cmPerPixel: 0))
        XCTAssertNil(PixelScaleMeasurement.pixelLength(forCM: 0, cmPerPixel: 0.05))
    }

    func testCMPerPixelWithDegenerateLineReturnsNil() {
        XCTAssertNil(PixelScaleMeasurement.cmPerPixel(
            lengthCM: 45,
            pointA: PlanePoint(x: 5, y: 5), pointB: PlanePoint(x: 5, y: 5)))
    }
}
