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

        case Self.increment.rawValue:
            return "Move the matched adjustable element one step up using its accessibility increment action."

        case Self.decrement.rawValue:
            return "Move the matched adjustable element one step down using its accessibility decrement action."

        case Self.performCustomAction.rawValue:
            return "Invoke a named custom accessibility action exposed by the matched element or container."

        case Self.scroll.rawValue:
            return """
                Scroll within scroll views. mode=page scrolls one page in 'direction'; \
                mode=to_visible brings a known element into view; mode=search scrolls until a \
                matching element is found; mode=to_edge scrolls to a top/bottom/left/right edge.
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

        case Self.gestureMCPToolName:
            return """
                Perform a touch gesture. Prefer 'activate' for element interactions — gestures are for \
                swipes, drags, pinches, rotates, and free-form path drawing. Set 'type' to one of: \
                swipe, one_finger_tap, drag, long_press, pinch, rotate, two_finger_tap, draw_path, draw_bezier.
                """

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
                Actions: copy, paste, cut, select, selectAll, delete, dismiss (dismiss the keyboard).
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
