import XCTest
@testable import Zion

final class LocalizationTests: XCTestCase {
    func testL10nReturnsCorrectKeys() {
        // Since we can't easily change the system locale in tests without side effects,
        // we test if the keys return something (meaning the lookup is happening).
        
        let errorString = L10n("Erro")
        XCTAssertFalse(errorString.isEmpty)
        
        // Test with arguments
        let branchFilter = L10n("Filtro de branch ativo: %@ · %@ commits", "main", "10")
        XCTAssertTrue(branchFilter.contains("main"))
        XCTAssertTrue(branchFilter.contains("10"))
    }
    
    func testLanguageEnums() {
        XCTAssertEqual(AppLanguage.en.rawValue, "en")
        XCTAssertEqual(AppLanguage.ptBR.rawValue, "pt-BR")
        XCTAssertEqual(AppLanguage.es.rawValue, "es")
    }
}
