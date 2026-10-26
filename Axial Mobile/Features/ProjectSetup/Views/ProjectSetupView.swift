//
//  ProjectSetupView.swift
//  Axial Mobile
//

import SwiftUI

/// Project setup, presented as a full-screen cover — `ProjectSetupContainer`.
///
/// A full-screen cover can't be swiped away, which is the point: the only
/// way out is the close button, and that runs the web's guard
/// (`guardedNavigateTo`) so an unsaved or incomplete project can't be left
/// by accident.
struct ProjectSetupView: View {
    let projectId: String
    /// Opens on a step rather than the navigator — a dashboard action item
    /// that names one ("Upload your CIM").
    var initialStep: SetupStep?
    let onExit: (SetupExit) -> Void

    @Environment(APIClient.self) private var apiClient
    @State private var session: ProjectSetupSession?
    @State private var loadError: String?

    var body: some View {
        ZStack {
            if let session {
                SetupShell(session: session, initialStep: initialStep, onExit: onExit)
                    .transition(.opacity)
            } else {
                NavigationStack {
                    loadingContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(AxialColor.layer2)
                        .navigationTitle("Project Setup")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Close", systemImage: "xmark") { onExit(.closed) }
                            }
                        }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: session == nil)
        .task { await load() }
    }

    @ViewBuilder
    private var loadingContent: some View {
        if let loadError {
            ContentUnavailableView {
                Label("Couldn't open project setup", systemImage: "wifi.exclamationmark")
            } description: {
                Text(loadError)
            } actions: {
                Button("Retry") { Task { await load() } }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            ProgressView("Loading project…")
        }
    }

    private func load() async {
        loadError = nil
        do {
            let intent: JSONValue = try await apiClient.get("intents/\(projectId)")
            let session = ProjectSetupSession(intentId: projectId, intent: intent, api: apiClient)
            self.session = session
            await session.loadReferenceData()
        } catch {
            loadError = error.localizedDescription
        }
    }
}

/// Everything once the intent is in hand.
private struct SetupShell: View {
    let session: ProjectSetupSession
    let initialStep: SetupStep?
    let onExit: (SetupExit) -> Void

    @State private var router = SetupRouter()
    @State private var closePrompt: ClosePrompt?
    @State private var isClosing = false
    @State private var isShowingCompletion = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum ClosePrompt: Identifiable {
        case missingInformation, unsavedChanges, saveFailed
        var id: Self { self }
    }

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.path) {
            SetupNavigatorView(section: $router.section, currentStep: router.currentStep) { step in
                router.open(step)
            }
            .navigationTitle(session.internalName)
            .navigationSubtitle(session.statusLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { navigatorToolbar }
            .navigationDestination(for: SetupRoute.self) { route in
                switch route {
                case .step(let step):
                    SetupStepView(step: step, onReview: review)
                case .review:
                    SetupReviewView(onExit: onExit)
                }
            }
        }
        .tint(AxialColor.brandPrimary)
        .environment(session)
        .environment(router)
        .interactiveDismissDisabled()
        .onAppear {
            if let initialStep, router.path.isEmpty { router.open(initialStep) }
        }
        .alert(item: $closePrompt) { prompt in
            alert(for: prompt)
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var navigatorToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                Task { await close() }
            } label: {
                if isClosing {
                    ProgressView()
                } else {
                    Label("Close", systemImage: "xmark")
                }
            }
            .disabled(isClosing)
            .accessibilityIdentifier("setup-close")
        }
        if session.isAutosaveEnabled {
            ToolbarItem(placement: .topBarTrailing) {
                AutosaveIndicator()
            }
        }

        ToolbarItem(placement: .bottomBar) {
            Button {
                isShowingCompletion = true
            } label: {
                Label {
                    Text(session.completion.isComplete ? "Complete" : "\(session.completion.incompleteSteps.count) Incomplete")
                        .contentTransition(.numericText())
                } icon: {
                    Image(systemName: session.completion.isComplete ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(session.completion.isComplete ? AxialColor.success : AxialColor.textSecondary)
                }
                .labelStyle(.titleAndIcon)
            }
            .tint(AxialColor.textPrimary)
            .popover(isPresented: $isShowingCompletion) {
                SetupCompletionList(completion: session.completion,
                                    isAutoDrafting: session.context.isAutoDrafting) { step in
                    isShowingCompletion = false
                    session.revealValidationErrors()
                    router.open(step, toFix: true)
                }
                .presentationCompactAdaptation(.popover)
            }
            .accessibilityIdentifier("setup-completion")
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) {
            Button(session.reviewLabel) { review() }
                .buttonStyle(.borderedProminent)
                .tint(AxialColor.brandPrimary)
                .disabled(session.context.isAutoDrafting)
                .accessibilityIdentifier("setup-review")
        }
    }

    // MARK: Review

    /// `onReviewAndShare`: reveal every error; if complete, check the
    /// primary contact can share and open review; otherwise go to the
    /// first step that needs fixing.
    private func review() {
        Haptics.lightImpact()
        session.revealValidationErrors()
        let completion = session.completion
        if completion.isComplete {
            if session.unsignedPrimaryContact != nil {
                // `routeToDealTeamForTos`.
                router.pulseTosNotice = true
                router.open(.messaging, toFix: true)
                Haptics.error()
                return
            }
            router.review()
        } else if let first = completion.incompleteSteps.first {
            Haptics.error()
            router.open(first, toFix: true)
        }
    }

    // MARK: Close

    /// `guardedNavigateTo`. A draft autosaves, so it only needs its last
    /// edit flushed; a shared project gets the web's two prompts.
    private func close() async {
        let context = session.context
        let isDraft = context.intentState == "draft"
        let isInvalid = !session.completion.isComplete
        if isInvalid, !isDraft, context.isShared {
            closePrompt = .missingInformation
            return
        }
        if !session.isAutosaving, session.hasUnsavedChanges, !isDraft, !isInvalid || context.isShared {
            closePrompt = .unsavedChanges
            return
        }
        // Mobile addition: leaving mid-debounce would drop the last edit,
        // so wait for it — and say so if it didn't land.
        isClosing = true
        await session.settleAutosave()
        isClosing = false
        if session.autosaveStatus == .error, session.hasUnsavedChanges {
            closePrompt = .saveFailed
            return
        }
        onExit(.closed)
    }

    private func alert(for prompt: ClosePrompt) -> Alert {
        switch prompt {
        case .missingInformation:
            Alert(
                title: Text("Missing Required Information"),
                message: Text("This project is missing required information. To save your changes, please go back and complete all required fields."),
                primaryButton: .default(Text("Go Back & Edit")),
                secondaryButton: .destructive(Text("Discard Changes")) { onExit(.closed) }
            )
        case .unsavedChanges:
            Alert(
                title: Text("Unsaved Changes"),
                message: Text("This project has unsaved changes. You can choose to save the project or discard the changes."),
                primaryButton: .default(Text("Save Project")) { review() },
                secondaryButton: .destructive(Text("Discard Changes")) { onExit(.closed) }
            )
        case .saveFailed:
            Alert(
                title: Text("Changes Not Saved"),
                message: Text(session.lastSaveError ?? "Your latest changes couldn't be saved."),
                primaryButton: .default(Text("Try Again")) {
                    Task {
                        await session.triggerAutosave()
                        if session.autosaveStatus != .error { onExit(.closed) }
                    }
                },
                secondaryButton: .destructive(Text("Discard Changes")) { onExit(.closed) }
            )
        }
    }
}
