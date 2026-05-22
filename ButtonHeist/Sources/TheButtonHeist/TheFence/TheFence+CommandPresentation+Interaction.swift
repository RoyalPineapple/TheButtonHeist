import Foundation

extension TheFence.Command {
    static func interactionPresentationDescription(for toolName: String) -> String? {
        switch toolName {
        case Self.activate.rawValue:
            return """
                Activate a UI element (VoiceOver-style double-tap): tap buttons, follow links, toggle \
                controls. Pass 'action' to invoke a named action like "increment", "decrement", or \
                any entry from the element's actions array.
                """

        case Self.rotor.rawValue:
            return """
                Move through a rotor exposed by an element. Defaults to next. Use rotors listed by \
                get_interface to pick rotor or rotorIndex; pass currentHeistId from the previous \
                object result to continue like a VoiceOver user. For text-range results, also pass \
                the returned start and end offsets.
                """

        case Self.typeText.rawValue:
            return """
                Type non-empty text via keyboard injection. Optionally target an \
                element to focus it first and read back the resulting value.
                """

        case Self.scroll.rawValue:
            return """
                Scroll within scroll views. mode=page scrolls one page in 'direction'; \
                mode=to_visible brings a known element into view; mode=search scrolls until a \
                matching element is found; mode=to_edge scrolls to a top/bottom/left/right edge.
                """

        case Self.gestureMCPToolName:
            return """
                Perform a touch gesture. Prefer 'activate' for element interactions — gestures are for \
                swipes, drags, pinches, rotates, and free-form path drawing. Set 'type' to one of: \
                swipe, one_finger_tap, drag, long_press, pinch, rotate, two_finger_tap, draw_path, draw_bezier.
                """

        case Self.editAction.rawValue:
            return """
                Perform an edit or keyboard action on the current first responder. \
                Actions: copy, paste, cut, select, selectAll, delete, dismiss (dismiss the keyboard).
                """

        case Self.setPasteboard.rawValue:
            return """
                Write text to the general pasteboard from within the app. Content written by the app \
                itself does not trigger the iOS "Allow Paste" dialog when subsequently read.
                """

        case Self.getPasteboard.rawValue:
            return """
                Read text from the general pasteboard. iOS may show "Allow Paste" if the content \
                was written by another app.
                """

        default:
            return nil
        }
    }
}
