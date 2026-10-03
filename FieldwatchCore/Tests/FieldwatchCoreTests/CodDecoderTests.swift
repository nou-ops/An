//
//  CodDecoderTests.swift
//  FieldwatchCoreTests
//
//  منقول من app/src/test/java/app/fieldwatch/domain/CodDecoderTest.kt (5 اختبارات).
//

import XCTest
@testable import FieldwatchCore

final class CodDecoderTests: XCTestCase {

    func testSmartphoneIsPhoneSlashSmartphone() {
        // major 0x02 Phone، minor 0x03 Smartphone، format 0.
        let d = CodDecoder.decode(0x020C)
        XCTAssertEqual("Phone", d.major)
        XCTAssertEqual("Smartphone", d.minor)
        XCTAssertEqual("Phone / Smartphone", d.summary())
    }

    func testServiceBitsAppendToSummary() {
        // Networking (bit 4) + Audio (bit 8) من حقل الخدمات؛ A/V headphones.
        let cod = (1 << 17) | (1 << 21) | (0x04 << 8) | (0x06 << 2)
        let d = CodDecoder.decode(cod)
        XCTAssertEqual("Audio / Video", d.major)
        XCTAssertEqual("Headphones", d.minor)
        XCTAssertEqual("Audio / Video / Headphones · Networking, Audio", d.summary())
    }

    func testPeripheralKeyboard() {
        // major 0x05 Peripheral، minor 0x10 = بت لوحة المفاتيح HID وحده.
        let d = CodDecoder.decode((0x05 << 8) | (0x10 << 2))
        XCTAssertEqual("Peripheral", d.major)
        XCTAssertEqual("Keyboard", d.minor)
    }

    func testNonZeroFormatSuppressesMinorName() {
        let d = CodDecoder.decode((0x02 << 8) | (0x03 << 2) | 0x01)
        XCTAssertEqual("format 1", d.minor)
    }

    func testZeroAndNullDecodeToNull() {
        XCTAssertNil(CodDecoder.decodeOrNull(nil))
        XCTAssertNil(CodDecoder.decodeOrNull(0))
    }
}
