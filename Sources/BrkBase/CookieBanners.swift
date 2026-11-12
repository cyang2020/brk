/// What Block Cookie Banners (Arc's setting; per site, Hide matching cookie banners) hides: the banners and dialogs of
/// the consent tools most sites use, and the two marks Brk's fixture pages carry. One rule per selector, so a selector
/// this Chromium does not support drops alone. Two tools also stop the page from scrolling while their dialog is up;
/// with the dialog hidden, scrolling comes back.
public enum CookieBanners {
    public static let selectors = [
        "[data-cookie-banner]", "[aria-label=\"cookie consent\"]",
        "#onetrust-consent-sdk", "#CybotCookiebotDialog", "#CybotCookiebotDialogBodyUnderlay", "#didomi-host",
        "#qc-cmp2-container", "#consent_blackbar", "#truste-consent-track", ".truste_box_overlay", ".truste_overlay",
        ".osano-cm-window", "#usercentrics-root", "#usercentrics-cmp-ui", ".cc-window", ".cky-consent-container", ".cky-overlay",
        "#cmplz-cookiebanner-container", "#iubenda-cs-banner", "#BorlabsCookieBox", ".fc-consent-root",
        "div[id^=\"sp_message_container_\"]", "#cmpbox", "#cmpbox2", "#hs-eu-cookie-confirmation", "#cookie-notice",
        "#cookie-law-info-bar", "#moove_gdpr_cookie_info_bar", "#shopify-pc__banner", ".klaro .cookie-notice",
        ".klaro .cookie-modal", "#axeptio_overlay", "#lanyard_root", "#_evidon_banner", "[data-hook=\"consent-banner-root\"]",
    ]
    public static let css = (selectors.map { $0 + "{display:none!important;}" }
        + ["html.sp-message-open:root{overflow:auto!important;}", "html body.didomi-popup-open{overflow:auto!important;}"])
        .joined(separator: "\n")
}
