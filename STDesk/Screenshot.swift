//
//  Screenshot.swift
//
//  Opening the app straight onto one screen, so the store captures can be
//  taken by CI instead of by hand on a rented Mac.
//
//  `xcrun simctl` can create a simulator, install an app and launch it, but
//  it has no tap API — there is no way to drive the interface to a screen.
//  Without something like this every capture is the first screen the app
//  happens to show, which for a launcher is an empty library.
//
//  STDESK_SHOT names the screen to open on. The capture job sets it through
//  SIMCTL_CHILD_STDESK_SHOT, which is how an environment variable reaches an
//  app under simctl.
//
//  AN ENVIRONMENT VARIABLE, NOT A BUILD FLAG, deliberately: the binary that
//  is photographed is then the same binary that is submitted, rather than a
//  near-identical one. It is inert in the shipped app because nothing can set
//  an environment variable for an App Store app on a device — and it is not a
//  "hidden feature" under guideline 5.6, because it unlocks nothing the
//  toolbar does not already reach. It only chooses which of them opens first.
//
//  The sibling app (DOSDeck) does the same thing with RETRODOS_SHOT.

import Foundation

enum Screenshot {
    /// Which screen a capture run asked for, or nil in normal use.
    static let requested: String? = {
        guard let value = ProcessInfo.processInfo.environment["STDESK_SHOT"],
              !value.isEmpty else { return nil }
        return value
    }()

    static func wants(_ screen: String) -> Bool { requested == screen }

    /// True whenever a capture run is driving the app, whatever the screen.
    static var isCapturing: Bool { requested != nil }
}
