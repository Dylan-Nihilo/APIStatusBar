# Release Onboarding And Status Item Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make release builds self-guiding on first launch and give users a reliable recovery path when the menu bar item is hidden by a crowded status bar.

**Architecture:** Add a small pure launch policy that AppKit startup code can use and unit tests can verify. Keep the onboarding experience inside the existing settings window, adding an immersive top panel above the current configuration cards instead of introducing a separate window.

**Tech Stack:** Swift 6, SwiftUI, AppKit `NSStatusItem`, XCTest.

---

### Task 1: Launch Policy

**Files:**
- Create: `APIStatusBar/Core/LaunchPresentationPolicy.swift`
- Test: `APIStatusBarTests/LaunchPresentationPolicyTests.swift`
- Modify: `APIStatusBar/APIStatusBarApp.swift`

- [ ] Write failing tests for startup and status item persistence.
- [ ] Add `LaunchPresentationPolicy`.
- [ ] Use it in the app delegate and status item controller.
- [ ] Run the focused test.

### Task 2: Immersive Onboarding

**Files:**
- Modify: `APIStatusBar/UI/SettingsView.swift`

- [ ] Add a prominent onboarding panel shown while server URL or token is missing.
- [ ] Keep existing configuration controls below the panel.
- [ ] Include a concise menu bar recovery note.
- [ ] Build the app.

### Task 3: Release Docs

**Files:**
- Modify: `README.md`

- [ ] Update first-run instructions.
- [ ] Document crowded menu bar recovery.
- [ ] Run the full test suite.
