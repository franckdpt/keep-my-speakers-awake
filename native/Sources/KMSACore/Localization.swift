import Foundation

public enum AppLanguage: String, CaseIterable {
    case french = "fr"
    case english = "en"

    /// Only the primary preferred language counts; a secondary French preference must not override another language.
    public static func resolve(_ preferredLanguages: [String]) -> AppLanguage {
        guard let primary = preferredLanguages.first else { return .english }
        let code = primary.replacingOccurrences(of: "_", with: "-").split(separator: "-").first?.lowercased()
        return code == "fr" ? .french : .english
    }
}

public enum L10n {
    public static let language = AppLanguage.resolve(Locale.preferredLanguages)
    public static var locale: Locale { Locale(identifier: language.rawValue) }
    public static func text(_ key: AppText) -> String { key.localized(in: language) }
}

public enum AppLinks {
    public static let repository = URL(string: "https://github.com/franckdpt/keep-my-speakers-awake")!
}

/// Exhaustive bilingual copy shared by controls, help, accessibility and model messages.
public enum AppText: String, CaseIterable {
    case subtitle
    case enableApp
    case wakeVolume
    case testWake
    case stopTest
    case smartMode
    case smartModeOption
    case recommended
    case aboutSmartMode
    case smartModeHint
    case openAtLogin
    case noJack
    case quit
    case githubRepository
    case checkUpdates, checkingUpdates, appUpToDate, updateAvailable, updateExplanation
    case installAndRelaunch, installUpdate, updateToVersion, automaticUpdateChecks, later, downloadingUpdate, verifyingUpdate, installingUpdate, updateFailed
    case updateInstallLocation, updateNeedsNewerMacOS, updateVerificationFailed, updateCheckFailed
    case paused
    case wakePlaying
    case ready
    case audioFilesUnavailable
    case wakeBlocked
    case wakeFileMissing
    case jackUnavailable
    case routeChanged
    case playbackFailed
    case playbackInterrupted
    case loginApproval
    case loginFailed
    case autoPaused
    case sessionUnavailable
    case unknownAudio
    case audioInUse
    case recentAudio
    case microphoneInUse
    case unknownMicrophone
    case inactive
    case unknownOutput
    case inputBusy
    case outputBusy
    case audioAvailable
    case smartHelp
    case relocationSuccess
    case relocationFailed

    public func localized(in language: AppLanguage) -> String {
        let copy: (fr: String, en: String)
        switch self {
        case .subtitle: copy = ("Gardez vos enceintes éveillées", "Keep your speakers awake")
        case .enableApp: copy = ("Activer Keep My Speakers Awake", "Enable Keep My Speakers Awake")
        case .wakeVolume: copy = ("Puissance du réveil", "Wake-up strength")
        case .testWake: copy = ("Tester le réveil", "Test wake-up")
        case .stopTest: copy = ("Arrêter le test", "Stop test")
        case .smartMode: copy = ("Mode intelligent", "Smart mode")
        case .smartModeOption: copy = ("Mode intelligent (recommandé)", "Smart mode (recommended)")
        case .recommended: copy = ("(recommandé)", "(recommended)")
        case .aboutSmartMode: copy = ("À propos du mode intelligent", "About smart mode")
        case .smartModeHint: copy = ("Afficher les règles de réveil des enceintes", "Show the speaker wake-up rules")
        case .openAtLogin: copy = ("Ouvrir avec la session", "Open at login")
        case .noJack: copy = ("Pas de connexion jack détectée", "No jack connection detected")
        case .githubRepository: copy = ("GitHub : étoiles, questions et signalements", "GitHub: stars, issues and source code")
        case .checkUpdates: copy = ("Chercher une mise à jour", "Check for Updates")
        case .checkingUpdates: copy = ("Recherche en cours…", "Checking for updates…")
        case .appUpToDate: copy = ("KMSA est à jour", "KMSA is up to date")
        case .updateAvailable: copy = ("Une mise à jour est disponible", "An update is available")
        case .updateExplanation: copy = ("La nouvelle version sera téléchargée depuis le dépôt GitHub officiel, vérifiée, puis installée. L’app redémarrera et tes réglages seront conservés.", "The new version will be downloaded from the official GitHub repository, verified and installed. The app will restart and your settings will be preserved.")
        case .installAndRelaunch: copy = ("Installer et relancer", "Install and Relaunch")
        case .installUpdate: copy = ("Installer la mise à jour…", "Install Update…")
        case .updateToVersion: copy = ("Mettre à jour vers", "Update to")
        case .automaticUpdateChecks: copy = ("Vérification au démarrage, puis toutes les 24 h.", "Checked at startup, then every 24 hours.")
        case .later: copy = ("Plus tard", "Later")
        case .downloadingUpdate: copy = ("Téléchargement…", "Downloading…")
        case .verifyingUpdate: copy = ("Vérification…", "Verifying…")
        case .installingUpdate: copy = ("Préparation du redémarrage…", "Preparing to restart…")
        case .updateFailed: copy = ("La mise à jour n’a pas pu être terminée.", "The update could not be completed.")
        case .updateInstallLocation: copy = ("Place KMSA dans un dossier Applications où tu peux modifier l’app, puis réessaie.", "Move KMSA to an Applications folder where you can modify the app, then try again.")
        case .updateNeedsNewerMacOS: copy = ("Cette mise à jour nécessite une version plus récente de macOS.", "This update requires a newer version of macOS.")
        case .updateVerificationFailed: copy = ("La vérification de la mise à jour a échoué. L’app actuelle est conservée.", "Update verification failed. The current app has been kept.")
        case .updateCheckFailed: copy = ("Impossible de rechercher la mise à jour. Vérifie la connexion et réessaie.", "Could not check for updates. Check your connection and try again.")
        case .quit: copy = ("Quitter", "Quit")
        case .paused: copy = ("En pause", "Paused")
        case .wakePlaying: copy = ("Réveil en cours…", "Wake-up in progress…")
        case .ready: copy = ("Prêt · connexion jack détectée", "Ready · jack connection detected")
        case .audioFilesUnavailable: copy = ("Fichiers audio indisponibles", "Audio files unavailable")
        case .wakeBlocked: copy = ("Réveil bloqué", "Wake-up blocked")
        case .wakeFileMissing: copy = ("Fichier du réveil introuvable.", "Wake-up audio file not found.")
        case .jackUnavailable: copy = ("Impossible de réserver la sortie jack.", "Unable to reserve the jack output.")
        case .routeChanged: copy = ("Sortie modifiée : réveil annulé.", "Output changed: wake-up cancelled.")
        case .playbackFailed: copy = ("Impossible de lire le réveil.", "Unable to play the wake-up audio.")
        case .playbackInterrupted: copy = ("La lecture du réveil a été interrompue.", "Wake-up playback was interrupted.")
        case .loginApproval: copy = ("Autorise l’ouverture dans Réglages Système > Général > Ouverture.", "Allow the app in System Settings > General > Login Items.")
        case .loginFailed: copy = ("Impossible de modifier l’ouverture à la connexion.", "Unable to change the login item setting.")
        case .autoPaused: copy = ("Réveils automatiques en pause", "Automatic wake-ups paused")
        case .sessionUnavailable: copy = ("Session verrouillée ou indisponible", "Session locked or unavailable")
        case .unknownAudio: copy = ("Activité audio indéterminée", "Audio activity unknown")
        case .audioInUse: copy = ("Audio en cours · volume du Mac ≥ 50 % ou indisponible", "Audio playing · Mac volume ≥ 50% or unavailable")
        case .recentAudio: copy = ("Pause de 2 min après l’audio", "Paused for 2 min after audio")
        case .microphoneInUse: copy = ("Micro utilisé · réveil bloqué", "Microphone in use · wake-up blocked")
        case .unknownMicrophone: copy = ("Activité du micro indéterminée", "Microphone activity unknown")
        case .inactive: copy = ("Mac inactif · aucun son en cours", "Mac idle · no audio playing")
        case .unknownOutput: copy = ("Sortie inconnue", "Unknown output")
        case .inputBusy: copy = ("Entrée audio utilisée par une autre app", "Audio input in use by another app")
        case .outputBusy: copy = ("Sortie audio utilisée par une autre app", "Audio output in use by another app")
        case .audioAvailable: copy = ("Audio disponible", "Audio available")
        case .smartHelp: copy = ("• Micro allumé : aucun réveil, même en test.\n• Mac inactif depuis 5 min et aucun son : réveils en pause.\n• Souris ou clavier au retour : réveil immédiat.\n• Son du Mac à 50 % ou plus : réveils en pause, puis reprise après 2 min de calme.\n• Son à moins de 50 % : les réveils continuent.\n• Activité ou volume inconnus : réveils en pause par précaution.", "• Microphone on: no wake-ups, including tests.\n• Mac idle for 5 min with no audio: wake-ups paused.\n• Mouse or keyboard activity on return: immediate wake-up.\n• Mac volume at 50% or above: wake-ups paused, resuming after 2 min of quiet.\n• Volume below 50%: wake-ups continue.\n• Unknown activity or volume: wake-ups paused as a precaution.")
        case .relocationSuccess: copy = ("L’ouverture à la connexion utilise maintenant", "The login item now uses")
        case .relocationFailed: copy = ("Impossible de déplacer l’ouverture à la connexion.", "Unable to relocate the login item.")
        }
        return language == .french ? copy.fr : copy.en
    }
}
