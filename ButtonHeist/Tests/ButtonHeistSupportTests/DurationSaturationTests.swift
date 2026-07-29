import ButtonHeistSupport
import Testing

@Suite struct DurationSaturationTests {
    @Test func `finite seconds saturate to a representable duration`() {
        #expect(Duration.saturatingSeconds(1.5) == .seconds(1.5))
        #expect(Duration.saturatingSeconds(Double.greatestFiniteMagnitude) > .zero)
    }
}
