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
                Scroll one page within scroll views in the requested direction. Use scroll_to_visible, \
                element_search, or scroll_to_edge for those canonical operations.
                """

        case Self.scrollToVisible.rawValue:
            return """
                Make a semantic target visible by resolving it, revealing its owning scroll path, \
                refreshing the hierarchy, and returning fresh live geometry.
                """

        case Self.elementSearch.rawValue:
            return "Search scrollable content for a semantic element match without performing an action."

        case Self.scrollToEdge.rawValue:
            return "Scroll the selected container, or the target's owning scroll ancestor, to a requested edge."

        case Self.oneFingerTap.rawValue:
            return "Tap a coordinate or semantic element target after actionability resolution."

        case Self.longPress.rawValue:
            return "Long-press a coordinate or semantic element target for a resolved duration."

        case Self.swipe.rawValue:
            return "Swipe in a direction or between explicit points; semantic targets are made actionable first."

        case Self.drag.rawValue:
            return "Drag from one point to another using explicit coordinates or a semantic target."

        case Self.pinch.rawValue:
            return "Pinch around a resolved center point using scale, angle, and duration."

        case Self.rotate.rawValue:
            return "Rotate around a resolved center point using angle, radius, and duration."

        case Self.twoFingerTap.rawValue:
            return "Tap with two fingers at a coordinate or actionable semantic target."

        case Self.drawPath.rawValue:
            return "Draw a free-form path through explicit screen-coordinate points."

        case Self.drawBezier.rawValue:
            return "Draw a Bezier path from a start point through one or more curve segments."

        case Self.editAction.rawValue:
            return """
                Perform an edit or keyboard action on the current first responder. \
                Actions: copy, paste, cut, select, selectAll, delete. Use dismiss_keyboard to dismiss the keyboard.
                """

        case Self.dismissKeyboard.rawValue:
            return "Dismiss the on-screen keyboard through the current first responder or keyboard action path."

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
