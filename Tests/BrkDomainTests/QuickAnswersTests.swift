import XCTest

import BrkBase
@testable import BrkDomain

/// The command bar's quick answers: what reads as a question, what stays an ordinary search, and the answers.
final class QuickAnswersTests: XCTestCase {
    /// Saturday 7 November 2026, 12:00 UTC.
    private let noon = Instant(milliseconds: 1_794_052_800_000)
    private let utc = TimeZone(identifier: "UTC")!
    private let posix = Locale(identifier: "en_GB")
    private let rates = CurrencyRates(date: "2026-11-06", perEuro: ["EUR": 1, "USD": 1.10, "CNY": 7.70, "JPY": 165])

    private func answer(_ text: String, rates: CurrencyRates? = nil, zone: TimeZone? = nil) -> QuickAnswer? {
        QuickAnswers.answer(text, QuickAnswerContext(now: noon, timeZone: zone ?? utc, locale: posix, rates: rates))
    }

    private func assertAnswer(_ text: String, _ expected: String, line: UInt = #line) {
        XCTAssertEqual(answer(text)?.answer, expected, text, line: line)
    }

    func testPercentAndRoot() {
        assertAnswer("52% of 900", "468")
        assertAnswer("52 % of 900", "468")
        assertAnswer("10 percent of 1,200", "120")
        assertAnswer("square root of 625", "25")
        assertAnswer("SQRT 2", "1.414213562")
        assertAnswer("sqrt(81)", "9")
    }

    func testUnits() {
        assertAnswer("10ft in m", "3.048 m")
        assertAnswer("10 ft to m", "3.048 m")
        assertAnswer("1 mile in km", "1.609344 km")
        assertAnswer("5 lb in kg", "2.26796185 kg")
        assertAnswer("100 c in f", "212 °F")
        assertAnswer("32 f in c", "0 °C")
        assertAnswer("1 gb in mb", "1000 MB")
        assertAnswer("1 gib in mib", "1024 MiB")
        assertAnswer("1 fl oz in ml", "29.57352956 mL")
        assertAnswer("60 mph in km/h", "96.56064 km/h")
        assertAnswer("10 in in cm", "25.4 cm")
    }

    func testCSSLengths() {
        assertAnswer("2rem in px", "32 px")
        assertAnswer("24px in rem", "1.5 rem")
        assertAnswer("1in in px", "96 px")
        assertAnswer("12 pt in px", "16 px")
        // "pt" is a point beside a length and a pint beside a volume.
        assertAnswer("1 pt in ml", "473.176473 mL")
    }

    func testDatesAndTimes() {
        assertAnswer("days until 31 Mar", "144 days")
        assertAnswer("days until march 31", "144 days")
        assertAnswer("days until 2026-11-08", "1 day")
        assertAnswer("days until 7 nov", "0 days")
        assertAnswer("days until 6 nov", "364 days")
        assertAnswer("days since 6 nov", "1 day")
        assertAnswer("days since 1st jan 2026", "310 days")
        assertAnswer("days until 29 feb", "479 days")
        XCTAssertNil(answer("days until 31 feb"))
        assertAnswer("145 mins to timespan", "2 hours 25 minutes")
        assertAnswer("90061 s to timespan", "1 day 1 hour 1 minute 1 second")
        assertAnswer("0 mins to timespan", "0 seconds")
    }

    func testTimeZones() {
        // The system formats these; only the parts are pinned, so a new macOS's punctuation breaks nothing.
        func parts(_ text: String, _ expected: String..., line: UInt = #line) {
            for part in expected { XCTAssertTrue(answer(text)?.answer.contains(part) == true, "\(text): \(String(describing: answer(text)?.answer))", line: line) }
        }
        parts("time in tokyo", "Sat", "7 Nov", "21:00")
        parts("time in new york", "Sat", "7 Nov", "07:00")
        parts("time in sf", "Sat", "7 Nov", "04:00")
        parts("time in pst", "Sat", "7 Nov", "04:00")
        XCTAssertEqual(answer("5pm ldn in sf")?.answer, "Sat 09:00")
        XCTAssertEqual(answer("5:30 pm ldn to tokyo")?.answer, "Sun 02:30")
        XCTAssertEqual(answer("17:00 in tokyo")?.answer, "Sun 02:00")
        XCTAssertEqual(answer("9am in tokyo", zone: TimeZone(identifier: "Asia/Shanghai"))?.answer, "Sat 10:00")
    }

    func testBareWordsAreAnswersButNotLeads() {
        func parts(_ text: String, _ expected: String..., line: UInt = #line) {
            for part in expected { XCTAssertTrue(answer(text)?.answer.contains(part) == true, "\(text): \(String(describing: answer(text)?.answer))", line: line) }
        }
        parts("today", "Saturday", "7 November 2026")
        parts("Tomorrow", "Sunday", "8 November 2026")
        parts("yesterday", "Friday", "6 November 2026")
        XCTAssertEqual(answer("time")?.answer, "12:00")
        parts("now", "Sat", "7 Nov 2026", "12:00")
        for word in ["today", "tomorrow", "yesterday", "time", "now"] {
            XCTAssertEqual(answer(word)?.leads, false, word)
            XCTAssertFalse(QuickAnswers.leads(word), word)
            XCTAssertTrue(QuickAnswers.usesClock(word), word)
        }
    }

    func testCurrency() {
        let row = answer("100 usd in cny", rates: rates)
        XCTAssertEqual(row?.answer, "700.00 CNY")
        XCTAssertEqual(row?.detail, "100 usd in cny · ECB 2026-11-06")
        XCTAssertEqual(row?.kind, .currency)
        XCTAssertEqual(answer("100usd TO eur", rates: rates)?.answer, "90.91 EUR")
        XCTAssertEqual(answer("1,000 eur as jpy", rates: rates)?.answer, "165000.00 JPY")
        XCTAssertTrue(QuickAnswers.asksCurrency("100 usd in cny"))
    }

    func testNoRatesOrAnUnknownCodeMeansNoAnswer() {
        XCTAssertNil(answer("100 usd in cny"), "no rates yet")
        XCTAssertNil(answer("100 usd in thb", rates: rates), "a code the file does not have")
        XCTAssertNil(answer("100 usd in xyz", rates: rates))
        XCTAssertFalse(QuickAnswers.asksCurrency("100 usd in xyz"))
        XCTAssertFalse(QuickAnswers.asksCurrency("100 usd"))
        XCTAssertFalse(QuickAnswers.asksCurrency("usd in cny"))
    }

    /// Ordinary searches and addresses never become answers.
    func testInputsThatStaySearches() {
        let searches = [
            "10 things", "10 things in m", "best 10 ft in m", "what is 10 ft in m", "1 in 4", "5 in a row", "2 men in a boat", "7 days to die", "10 min to go", "5 days in paris",
            "3 to 5 m", "1 to 10", "2 m to go", "24 h to m", "10 kg in m", "10 am to pm", "8am to 5pm", "5 in tokyo", "time in", "time in nowhere land", "time flies", "time of day",
            "days until", "days until christmas", "days of thunder", "today show", "now playing", "tomorrow never dies", "timespan", "145 mins", "10ft", "rem", "2rem",
            "square root", "root of 625", "sqrt", "sqrt x", "52% of", "% of 900", "of 900", "half of 900", "10 percent", "100 usd", "usd to cny", "100 dollars in pounds sterling",
            "example.com", "https://example.com/10ft-in-m", "10.0.0.1", "localhost:5173", "time.com", "now.sh", "emoji smile", "file report",
        ]
        for text in searches {
            XCTAssertNil(answer(text, rates: rates), text)
            XCTAssertFalse(QuickAnswers.leads(text), text)
        }
    }

    func testAVeryLongTextIsNoQuestion() {
        XCTAssertNil(answer(String(repeating: "1", count: 100) + " ft in m"))
    }

    func testColorsAreReadInEveryForm() {
        let orange = QuickColor(red: 255, green: 85, blue: 0)
        for text in ["#ff5500", "#FF5500", "#f50", "rgb(255,85,0)", "rgb(255, 85, 0)", "RGB(255 85 0)", "hsl(20,100%,50%)", "hsl(20, 100%, 50%)"] {
            XCTAssertEqual(QuickColors.parse(text), orange, text)
        }
        XCTAssertEqual(orange.hex, "#FF5500")
        XCTAssertEqual(orange.rgb, "rgb(255, 85, 0)")
        XCTAssertEqual(orange.hsl, "hsl(20, 100%, 50%)")
        XCTAssertEqual(QuickColor(red: 128, green: 128, blue: 128).hsl, "hsl(0, 0%, 50%)")
        XCTAssertEqual(QuickColors.parse("hsl(240,100%,50%)"), QuickColor(red: 0, green: 0, blue: 255))
        XCTAssertEqual(QuickColors.parse("hsl(120,100%,25%)"), QuickColor(red: 0, green: 128, blue: 0))
        XCTAssertEqual(QuickColors.parse("hsl(360,100%,50%)"), QuickColor(red: 255, green: 0, blue: 0))
    }

    func testCSSNamesOnlyAfterTheColorPrefix() {
        XCTAssertNil(QuickColors.parse("tomato"), "an ordinary word")
        XCTAssertNil(QuickColors.parse("red"))
        XCTAssertEqual(QuickColors.parse("tomato", names: true), QuickColor(red: 255, green: 99, blue: 71))
        XCTAssertEqual(QuickColors.parse("Rebecca Purple", names: true), QuickColor(red: 102, green: 51, blue: 153))
        XCTAssertEqual(QuickColors.parse("ff5500", names: true), QuickColor(red: 255, green: 85, blue: 0), "under the prefix the # may go")
    }

    func testTextsThatAreNoColor() {
        for text in ["#", "#ab", "#abcd", "#abcde", "#abcdefg", "#ggg", "#hashtag", "rgb(1,2)", "rgb(1,2,3,4)", "rgb(256,0,0)", "rgb(a,b,c)", "rgb 1 2 3", "hsl(20,100,50)", "hsl(400,100%,50%)", "hsl(20,200%,50%)", "ff5500", "abc", "example.com/#abc"] {
            XCTAssertNil(QuickColors.parse(text), text)
        }
    }

    func testOnlyAFullColorLeads() {
        XCTAssertTrue(QuickColors.leads("#ff5500"))
        XCTAssertTrue(QuickColors.leads("rgb(255,85,0)"))
        XCTAssertTrue(QuickColors.leads("hsl(20,100%,50%)"))
        XCTAssertFalse(QuickColors.leads("#abc"), "can as well be a tag")
        XCTAssertFalse(QuickColors.leads("#hashtag"))
    }

    func testTheEuroBanksFile() {
        let file = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gesmes:Envelope xmlns:gesmes="http://www.gesmes.org/xml/2002-08-01" xmlns="http://www.ecb.int/vocabulary/2002-08-01/eurofxref">
          <gesmes:subject>Reference rates</gesmes:subject>
          <Cube><Cube time='2026-11-06'>
            <Cube currency='USD' rate='1.1165'/><Cube currency='JPY' rate='176.77'/><Cube currency='BAD' rate='-1'/><Cube currency='TOOLONG' rate='2'/>
          </Cube></Cube>
        </gesmes:Envelope>
        """
        let parsed = CurrencyRates.parseECB(Data(file.utf8))
        XCTAssertEqual(parsed?.date, "2026-11-06")
        XCTAssertEqual(parsed?.perEuro, ["USD": 1.1165, "JPY": 176.77, "EUR": 1])
        XCTAssertNil(CurrencyRates.parseECB(Data("not xml".utf8)))
        XCTAssertNil(CurrencyRates.parseECB(Data("<a><Cube time='2026-11-06'/></a>".utf8)), "no rates")
        XCTAssertNil(CurrencyRates.parseECB(Data("<a><Cube currency='USD' rate='1.1'/></a>".utf8)), "no date")
        XCTAssertNil(CurrencyRates.parseECB(Data(repeating: 32, count: (1 << 20) + 1)), "too large")
    }
}
