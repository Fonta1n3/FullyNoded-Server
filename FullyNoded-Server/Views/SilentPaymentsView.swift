//
//  SilentPaymentsView.swift
//  FullyNoded-Server
//
//  Silent payments (BIP352) setup window, opened from Utilities.
//
//  The user picks the Fully Noded wallet (watch-only in Core) to import into, imports their scan private key (b_scan) and
//  silent payment address (sp1… / tsp1…, as exported from Fully Noded's signer
//  detail screen) by text or QR (camera if one is available, or a QR image file),
//  picks a start height, and starts SilentPaymentService. The spend public key
//  (B_spend) is read from the address, and the address's B_scan is used to check
//  that the scan key really belongs to it. The service then follows the chain in
//  the background and imports every output that belongs to them into the selected
//  wallet as a watch-only rawtr() descriptor.
//
//  The keys are saved (encrypted, in the Keychain) so scanning resumes automatically
//  when the app launches. Nothing about found outputs is ever saved.
//
//  All UI is SwiftUI. The camera is read with AVFoundation and each frame is shown as
//  a SwiftUI Image; QR codes are decoded with Core Image.
//

import SwiftUI
import AVFoundation
import CoreImage
import UniformTypeIdentifiers
import P256K

// MARK: - Saved configuration

/// Everything SilentPaymentService.start needs.
struct SPConfig: Codable, Equatable {
    var walletName: String
    var scanPrivateKeyHex: String
    var scanPublicKeyHex: String
    var spendPublicKeyHex: String
    var birthdayHeight: Int
    /// The sp1… / tsp1… address B_spend was read from (shown again in the form).
    var address: String?
    /// The network the keys were set up on (getblockchaininfo's chain). The scanner only
    /// ever talks to this network's node. Nil in configs saved before it was recorded.
    var chain: String?

    /// `chain`, or for older configs the network implied by the address: sp1… is mainnet,
    /// tsp1… is the selected network if that is a test network. Nil when that can't be told
    /// (tsp1… while mainnet is selected).
    var resolvedChain: String? {
        if let chain = chain { return chain }
        let selected = UserDefaults.standard.string(forKey: "chain") ?? "main"
        guard let hrp = address.flatMap({ SPKeyInput.address($0) })?.hrp else { return selected }
        if hrp == "sp" { return "main" }
        return selected == "main" ? nil : selected
    }
}

/// Stores the config encrypted (Crypto, the app's key) in the Keychain, never in
/// UserDefaults: it contains the scan private key.
enum SPConfigStore {
    private static let key = "silentPaymentsConfig"

    static func save(_ config: SPConfig) -> Bool {
        guard let json = try? JSONEncoder().encode(config),
              let encrypted = Crypto.encrypt(json) else { return false }
        return KeyChain.set(encrypted, forKey: key)
    }

    static func load() -> SPConfig? {
        guard let encrypted = KeyChain.getData(key),
              let json = Crypto.decrypt(encrypted) else { return nil }
        return try? JSONDecoder().decode(SPConfig.self, from: json)
    }

    static func remove() {
        _ = KeyChain.remove(key: key)
    }

    /// True if keys have been imported (cheap: no decryption).
    static var isConfigured: Bool {
        KeyChain.getData(key) != nil
    }

    /// Called at app launch: if keys were imported before, keep scanning.
    /// (The service retries with backoff if the node isn't up yet.)
    static func resumeIfConfigured() {
        guard let config = load() else { return }
        try? start(config)
    }

    /// `fromBirthday`: ignore saved progress and scan from the config's start height.
    static func start(_ config: SPConfig, fromBirthday: Bool = false) throws {
        guard let chain = config.resolvedChain else {
            throw SPError.config("These keys are for a test network, but which one wasn't saved. Select that network in Bitcoin Core, then press Resume.")
        }
        try SilentPaymentService.shared.start(
            chain: chain,
            walletName: config.walletName,
            scanPrivateKeyHex: config.scanPrivateKeyHex,
            scanPublicKeyHex: config.scanPublicKeyHex,
            spendPublicKeyHex: config.spendPublicKeyHex,
            birthdayHeight: config.birthdayHeight,
            fromBirthday: fromBirthday
        )
        // Older config with an sp1… address: it can only be mainnet, so record it now and later
        // network switches can't change it. A tsp1… one stays inferred from the selected test
        // network (the scanner refuses a node that doesn't have the wallet), so selecting the
        // right network and resuming fixes a wrong guess; Save & restart records it.
        if config.chain == nil, chain == "main" {
            var pinned = config
            pinned.chain = chain
            _ = save(pinned)
        }
    }
}

// MARK: - Key parsing

/// Parses / validates what the user typed or scanned.
enum SPKeyInput {
    /// Trims whitespace and common QR wrappers ("bitcoin:" URIs, query strings).
    static func clean(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("bitcoin:") { s = String(s.dropFirst("bitcoin:".count)) }
        if let q = s.firstIndex(of: "?") { s = String(s[..<q]) }
        return s
    }

    /// b_scan hex → (b_scan, B_scan) as lowercase hex, or nil if not a valid key.
    static func scanKey(_ raw: String) -> (priv: String, pub: String)? {
        let hex = clean(raw).lowercased()
        guard hex.count == 64, let data = SPHex.decode(hex),
              let key = try? P256K.Signing.PrivateKey(dataRepresentation: data) else { return nil }
        return (hex, SPHex.encode(Data(key.publicKey.dataRepresentation)))
    }

    /// Fully Noded's one-scan export (signer → scan private key → "Fully Noded Server QR"):
    ///
    ///     fnsp://import?v=1&address=<sp1… / tsp1…>&scankey=<64 hex>[&wallet=<Core wallet name>]
    ///
    /// Returns the raw address, scan key and (when the export came from a Fully Noded wallet)
    /// the node wallet to import into, or nil if `raw` isn't such a link. The values are
    /// validated by `address(_:)` / `scanKey(_:)` like typed ones.
    static func importLink(_ raw: String) -> (address: String, scanKey: String, wallet: String?)? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: s),
              components.scheme?.lowercased() == "fnsp",
              components.host?.lowercased() == "import" else { return nil }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name.lowercased() == name }?.value
        }
        guard let address = value("address"), let scanKey = value("scankey") else { return nil }
        let wallet = value("wallet")?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (address, scanKey, wallet?.isEmpty == false ? wallet : nil)
    }

    struct Address {
        /// The address as entered (cleaned).
        let address: String
        /// B_scan and B_spend, 33-byte compressed hex.
        let scanPub: String
        let spendPub: String
        /// "sp" (mainnet) or "tsp" (test networks).
        let hrp: String
    }

    /// sp1… / tsp1… address → its keys, or nil if it isn't a valid silent payment
    /// address with valid secp256k1 keys.
    static func address(_ raw: String) -> Address? {
        let s = clean(raw)
        guard let decoded = SPAddressDecoder.decode(s),
              (try? P256K.Signing.PublicKey(dataRepresentation: decoded.spend, format: .compressed)) != nil else { return nil }
        return Address(address: s.lowercased(),
                       scanPub: SPHex.encode(decoded.scan),
                       spendPub: SPHex.encode(decoded.spend),
                       hrp: decoded.hrp)
    }
}

/// Minimal BIP352 address decoder (bech32m, version 0: B_scan ‖ B_spend).
enum SPAddressDecoder {
    private static let charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
    private static let bech32mConst: UInt32 = 0x2bc8_30a3

    static func decode(_ address: String) -> (hrp: String, scan: Data, spend: Data)? {
        // No mixed case.
        guard address == address.lowercased() || address == address.uppercased() else { return nil }
        let s = address.lowercased()
        guard let sep = s.lastIndex(of: "1") else { return nil }
        let hrp = String(s[..<sep])
        guard hrp == "sp" || hrp == "tsp" else { return nil }

        var values: [UInt8] = []
        for c in s[s.index(after: sep)...] {
            guard let i = charset.firstIndex(of: c) else { return nil }
            values.append(UInt8(i))
        }
        guard values.count > 7, polymod(hrpExpand(hrp) + values) == bech32mConst else { return nil }

        let payload = Array(values.dropLast(6))
        let version = payload[0]
        guard version < 31, let program = convertBits(Array(payload.dropFirst()), from: 5, to: 8, pad: false) else { return nil }
        // v0 is exactly 66 bytes; later versions (forward compatible) start with them.
        guard (version == 0 && program.count == 66) || (version > 0 && program.count >= 66) else { return nil }
        return (hrp, Data(program[0..<33]), Data(program[33..<66]))
    }

    private static func polymod(_ values: [UInt8]) -> UInt32 {
        let gen: [UInt32] = [0x3b6a_57b2, 0x2650_8e6d, 0x1ea1_19fa, 0x3d42_33dd, 0x2a14_62b3]
        var chk: UInt32 = 1
        for v in values {
            let top = chk >> 25
            chk = ((chk & 0x1ff_ffff) << 5) ^ UInt32(v)
            for i in 0..<5 where (top >> UInt32(i)) & 1 == 1 {
                chk ^= gen[i]
            }
        }
        return chk
    }

    private static func hrpExpand(_ hrp: String) -> [UInt8] {
        let bytes = Array(hrp.utf8)
        return bytes.map { $0 >> 5 } + [0] + bytes.map { $0 & 31 }
    }

    private static func convertBits(_ data: [UInt8], from: Int, to: Int, pad: Bool) -> [UInt8]? {
        var acc = 0, bits = 0
        let maxv = (1 << to) - 1
        var out: [UInt8] = []
        for value in data {
            guard Int(value) >> from == 0 else { return nil }
            acc = (acc << from) | Int(value)
            bits += from
            while bits >= to {
                bits -= to
                out.append(UInt8((acc >> bits) & maxv))
            }
        }
        if pad {
            if bits > 0 { out.append(UInt8((acc << (to - bits)) & maxv)) }
        } else if bits >= from || ((acc << (to - bits)) & maxv) != 0 {
            return nil
        }
        return out
    }
}

// MARK: - QR decoding (camera + image files)

/// Reads the camera with AVFoundation, publishes each frame as a CGImage (shown by a
/// SwiftUI Image) and the first QR code it finds.
final class SPQRCamera: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var frame: CGImage?
    @Published var code: String?
    @Published var error: String?

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "FullyNoded-Server.SPQRCamera")
    private let context = CIContext()
    private let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                      options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
    private var lastDetection = Date.distantPast
    private var configured = false

    private static func devices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
                                         mediaType: .video,
                                         position: .unspecified).devices
    }

    /// True if this Mac has (or is connected to) a camera.
    static var isAvailable: Bool { !devices().isEmpty }

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            queue.async { self.run() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    self.queue.async { self.run() }
                } else {
                    self.publishError("Camera access was denied.")
                }
            }
        default:
            publishError("Camera access is off for FullyNoded-Server. Turn it on in System Settings → Privacy & Security → Camera.")
        }
    }

    func stop() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    // On `queue`.
    private func run() {
        if !configured {
            guard let device = Self.devices().first,
                  let input = try? AVCaptureDeviceInput(device: device) else {
                publishError("No camera found.")
                return
            }
            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: queue)

            session.beginConfiguration()
            if session.canSetSessionPreset(.vga640x480) { session.sessionPreset = .vga640x480 }
            guard session.canAddInput(input), session.canAddOutput(output) else {
                session.commitConfiguration()
                publishError("Unable to use the camera.")
                return
            }
            session.addInput(input)
            session.addOutput(output)
            session.commitConfiguration()
            configured = true
        }
        if !session.isRunning { session.startRunning() }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let cgImage = context.createCGImage(image, from: image.extent)

        // Look for a QR code ~4 times a second.
        var found: String?
        if Date().timeIntervalSince(lastDetection) > 0.25 {
            lastDetection = Date()
            found = detector?.features(in: image)
                .compactMap { ($0 as? CIQRCodeFeature)?.messageString }
                .first
        }

        DispatchQueue.main.async {
            self.frame = cgImage
            if let found = found, self.code == nil {
                self.code = found
            }
        }
    }

    private func publishError(_ message: String) {
        DispatchQueue.main.async { self.error = message }
    }

    /// Decodes the first QR code in an image file.
    static func decode(imageAt url: URL) -> String? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let image = CIImage(contentsOf: url),
              let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                        options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]) else { return nil }
        return detector.features(in: image)
            .compactMap { ($0 as? CIQRCodeFeature)?.messageString }
            .first
    }
}

/// Camera sheet: live preview with a target frame, closes itself on the first QR code.
struct SPQRScannerSheet: View {
    let title: String
    let onResult: (String?) -> Void

    @StateObject private var camera = SPQRCamera()

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.headline)

            ZStack {
                Rectangle()
                    .fill(.black)

                if let frame = camera.frame {
                    Image(decorative: frame, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(x: -1, y: 1) // mirror, like a selfie camera
                } else if let error = camera.error {
                    Text(error)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding()
                } else {
                    ProgressView("Starting camera…")
                        .foregroundStyle(.white)
                }

                Rectangle()
                    .strokeBorder(.white.opacity(0.85), style: StrokeStyle(lineWidth: 2, dash: [10, 6]))
                    .frame(width: 220, height: 220)
            }
            .frame(width: 480, height: 360)
            .clipShape(Rectangle())

            Text("Hold the QR code up to the camera.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel") { finish(nil) }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding()
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
        .onChange(of: camera.code) { _, code in
            if let code = code { finish(code) }
        }
    }

    private func finish(_ code: String?) {
        camera.stop()
        onResult(code)
    }
}

/// Your silent payment address as a QR code and text, to share with people who pay you:
/// copy the text or the image, or save the QR as a PNG. The address is public; it can't
/// spend or reveal your payments.
struct SPAddressQRSheet: View {
    let address: String
    let onDone: () -> Void

    @State private var message: (text: String, ok: Bool)?

    private var qrImage: NSImage { address.qrQode }

    var body: some View {
        VStack(spacing: 12) {
            Text("Your silent payment address")
                .font(.headline)

            Image(nsImage: qrImage)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 280, height: 280)
                .padding(8)
                .background(Color.white)

            Text(address)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)

            Text("Share it with anyone who pays you. It's public: it can't be used to spend or to see your payments.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)

            HStack {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(address, forType: .string)
                    message = ("Address copied", true)
                } label: {
                    Label("Copy address", systemImage: "doc.on.doc")
                }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([qrImage])
                    message = ("QR image copied", true)
                } label: {
                    Label("Copy QR image", systemImage: "photo.on.rectangle")
                }
                Button {
                    saveImage()
                } label: {
                    Label("Save QR…", systemImage: "square.and.arrow.down")
                }
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
            if let message = message {
                Label(message.text, systemImage: message.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .font(.caption)
                    .foregroundStyle(message.ok ? Cypher.accent : Cypher.danger)
            }
        }
        .padding()
        .frame(width: 480)
    }

    private func saveImage() {
        guard let cgImage = qrImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
            message = ("Couldn't create the image.", false)
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "silent-payment-address.png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try png.write(to: url)
            message = ("Saved to \(url.lastPathComponent)", true)
        } catch {
            message = ("Couldn't save: \(error.localizedDescription)", false)
        }
    }
}

// MARK: - Model

final class SilentPaymentsModel: ObservableObject {
    /// One model for every Silent Payments screen (the sidebar page and the Utilities
    /// window): the scanner has a single set of progress callbacks, so two models would leave
    /// one of the screens showing stale state.
    static let shared = SilentPaymentsModel()

    /// Callbacks are attached as soon as the model exists (at launch), not only when the
    /// page is opened, so imports found in the background still raise the alert.
    private init() {
        attachCallbacks()
    }

    @Published var wallets: [String] = []
    @Published var selectedWallet = ""
    @Published var scanKeyInput = ""
    @Published var addressInput = ""
    @Published var birthdayInput = ""

    @Published var isRunning = false
    @Published var savedConfig: SPConfig?
    @Published var scannedHeight: Int?
    @Published var tipHeight: Int?
    @Published var foundThisSession = 0
    @Published var lastError: String?
    @Published var alertMessage: String?
    @Published var isBusy = false

    /// The network this setup is for (getblockchaininfo's chain name). Every setup RPC goes to
    /// this network's node, independent of the Bitcoin Core network picker.
    @Published private(set) var network: String = UserDefaults.standard.string(forKey: "chain") ?? "main"
    private var networkInitialized = false

    static let networks = ["main", "test", "testnet4", "signet", "regtest"]

    static func networkName(_ chain: String) -> String {
        switch chain {
        case "main": return "Mainnet"
        case "test": return "Testnet3"
        case "testnet4": return "Testnet4"
        case "signet": return "Signet"
        case "regtest": return "Regtest"
        default: return chain
        }
    }

    /// Switches the setup to another network: its wallets and start height are loaded from
    /// that network's node (nothing from the previous network carries over).
    func selectNetwork(_ chain: String) {
        guard chain != network else { return }
        network = chain
        wallets = []
        // The saved wallet / start height only belong to the saved setup's network.
        if let saved = savedConfig, saved.resolvedChain == chain {
            selectedWallet = saved.walletName
            birthdayInput = "\(saved.birthdayHeight)"
        } else {
            selectedWallet = ""
            birthdayInput = ""
        }
        startHeightNote = nil
        refreshWallets()
        if birthdayInput.isEmpty { useCurrentTip() }
    }

    // MARK: Derived validation

    var scanKey: (priv: String, pub: String)? { SPKeyInput.scanKey(scanKeyInput) }
    var address: SPKeyInput.Address? { SPKeyInput.address(addressInput) }

    var scanKeyStatus: (ok: Bool, text: String)? {
        guard !scanKeyInput.isEmpty else { return nil }
        guard let key = scanKey else { return (false, "Not a valid 32-byte private key (64 hex characters).") }
        return (true, "Valid. Scan public key \(Self.short(key.pub))")
    }

    var addressStatus: (ok: Bool, text: String)? {
        guard !addressInput.isEmpty else { return nil }
        guard let address = address else {
            return (false, "Not a valid silent payment address (sp1… / tsp1…).")
        }
        let expected = network == "main" ? "sp" : "tsp"
        if address.hrp != expected {
            return (false, address.hrp == "sp"
                    ? "That is a mainnet address, but \(Self.networkName(network)) is selected above."
                    : "That is a test network address, but Mainnet is selected above. Select the test network it's for.")
        }
        // Scan key known (typed now or saved earlier): it must belong to this address.
        if let scanPub = effectiveScanKey?.pub, scanPub != address.scanPub {
            return (false, "The scan private key does not belong to this address.")
        }
        return (true, "Valid. Spend public key \(Self.short(address.spendPub))")
    }

    /// The scan key to use: the one typed in, or the saved one while the field is left
    /// empty (so the wallet or start height can be changed without entering it again).
    var effectiveScanKey: (priv: String, pub: String)? {
        if !scanKeyInput.isEmpty { return scanKey }
        guard let saved = savedConfig else { return nil }
        return (saved.scanPrivateKeyHex, saved.scanPublicKeyHex)
    }

    var canStart: Bool {
        !isBusy && setupSteps.allSatisfy { $0.done }
    }

    // MARK: Setup checklist

    enum SetupField: String {
        case wallet, scanKey, address, startHeight
    }

    struct SetupStep: Identifiable {
        let field: SetupField
        let done: Bool
        /// What to do while it isn't done, or what's there once it is.
        let text: String
        var id: String { field.rawValue }
    }

    /// Everything Start needs, in the order the page shows it.
    var setupSteps: [SetupStep] {
        let addressOk = addressStatus?.ok == true
        return [
            SetupStep(field: .wallet, done: !selectedWallet.isEmpty,
                      text: selectedWallet.isEmpty ? "Select the Fully Noded wallet to import payments into" : "Wallet selected"),
            SetupStep(field: .scanKey, done: effectiveScanKey != nil,
                      text: effectiveScanKey != nil
                        ? (scanKeyInput.isEmpty ? "Scan private key (saved)" : "Scan private key")
                        : (scanKeyInput.isEmpty ? "Add your scan private key" : "Fix the scan private key")),
            SetupStep(field: .address, done: addressOk,
                      text: addressOk ? "Silent payment address"
                        : (addressInput.isEmpty ? "Add your silent payment address" : "Fix the silent payment address")),
            SetupStep(field: .startHeight, done: Int(birthdayInput) != nil,
                      text: Int(birthdayInput) != nil ? "Start height \(birthdayInput)" : "Set a start height")
        ]
    }

    /// True once setup has begun (keys saved, or something entered), so missing fields are
    /// highlighted only then, not on an untouched page.
    var setupInProgress: Bool {
        savedConfig != nil || !scanKeyInput.isEmpty || !addressInput.isEmpty
    }

    /// Whether a card's field still needs input (highlighted on the page).
    func needsInput(_ field: SetupField) -> Bool {
        setupInProgress && setupSteps.first { $0.field == field }?.done == false
    }

    /// The address to share (copy / QR): the valid one in the field, else the saved one.
    var shareableAddress: String? {
        if addressStatus?.ok == true, let address = address { return address.address }
        return savedConfig?.address
    }

    /// The form differs from the saved setup (Save & restart applies it).
    var hasUnsavedChanges: Bool {
        guard let saved = savedConfig else { return false }
        if network != saved.resolvedChain { return true }
        if selectedWallet != saved.walletName { return true }
        if (address?.address ?? addressInput) != (saved.address ?? "") { return true }
        if Int(birthdayInput) != saved.birthdayHeight { return true }
        if let typed = scanKey, typed.priv != saved.scanPrivateKeyHex { return true }
        return false
    }

    static func short(_ hex: String) -> String {
        hex.count > 20 ? "\(hex.prefix(10))…\(hex.suffix(8))" : hex
    }

    /// Fills the form from a Fully Noded export link (pasted, scanned or opened as a URL).
    /// Nothing is started: the user still checks the wallet and start height and presses
    /// Start / Save & restart, so a link can never swap the keys behind their back.
    @discardableResult
    func applyImportLink(_ raw: String) -> Bool {
        guard let link = SPKeyInput.importLink(raw) else { return false }
        addressInput = SPKeyInput.clean(link.address)
        scanKeyInput = SPKeyInput.clean(link.scanKey)
        if scanKey == nil || address == nil {
            alertMessage = "That Fully Noded link doesn't contain a valid silent payment address and scan private key."
            return true
        }
        // An sp1… address can only be mainnet. (tsp1… could be any test network: the address
        // card asks for it if Mainnet is selected.)
        if address?.hrp == "sp" { selectNetwork("main") }
        // Exported from a Fully Noded wallet: select that wallet on the node.
        if let wallet = link.wallet {
            selectedWallet = wallet
            if !wallets.contains(wallet) { wallets.append(wallet) }
            refreshWallets()
            BitcoinRPC.shared.spCommand(method: "listwallets", params: [:], chain: network) { result in
                DispatchQueue.main.async {
                    guard case .success(let value) = result,
                          let loaded = value as? [String], !loaded.contains(wallet) else { return }
                    self.alertMessage = "The link is for the wallet \"\(wallet)\", which isn't loaded on this node. Load it (or select another wallet) before pressing Start."
                }
            }
        }
        return true
    }

    // MARK: Lifecycle

    func onAppear() {
        attachCallbacks()
        isRunning = SilentPaymentService.shared.isRunning
        // The callbacks only report what happens from now on: start from the scanner's
        // current state so the page agrees with the sidebar icon straight away.
        let status = SilentPaymentService.shared.status()
        scannedHeight = status.scannedHeight
        tipHeight = status.tipHeight
        lastError = status.lastError
        savedConfig = SPConfigStore.load()
        if !networkInitialized {
            networkInitialized = true
            if let chain = savedConfig?.resolvedChain { network = chain }
        }
        // Prefill from the saved setup only where the form is empty: the model is shared, so a
        // link opened just before the window appeared (or edits on another screen) must survive.
        if let saved = savedConfig {
            if selectedWallet.isEmpty { selectedWallet = saved.walletName }
            if addressInput.isEmpty { addressInput = saved.address ?? "" }
            if birthdayInput.isEmpty { birthdayInput = "\(saved.birthdayHeight)" }
        }
        refreshWallets()
        if birthdayInput.isEmpty { useCurrentTip() }
    }

    private func attachCallbacks() {
        let service = SilentPaymentService.shared
        // All three are called on the main queue.
        service.onProgress = { [weak self] height, tip in
            self?.scannedHeight = height
            self?.tipHeight = tip
            self?.lastError = nil
        }
        service.onFound = { [weak self] outputs in
            self?.foundThisSession += outputs.count
            SPImportFeed.shared.record(outputs, wallet: SilentPaymentService.shared.status().walletName)
        }
        service.onError = { [weak self] error in
            self?.lastError = error.description
        }
    }

    // MARK: Node

    func refreshWallets() {
        let chain = network
        BitcoinRPC.shared.spCommand(method: "listwallets", params: [:], chain: chain) { result in
            DispatchQueue.main.async {
                guard chain == self.network else { return }   // switched meanwhile
                switch result {
                case .success(let value):
                    self.wallets = (value as? [String] ?? []).sorted()
                    if !self.selectedWallet.isEmpty, !self.wallets.contains(self.selectedWallet) {
                        // Saved wallet isn't loaded right now; keep it selectable.
                        self.wallets.append(self.selectedWallet)
                    }
                case .failure(let error):
                    self.alertMessage = "Unable to list wallets on \(Self.networkName(chain)): \(error.description). Is that network's node running?"
                }
            }
        }
    }

    /// Note under the start height after "Earliest available" (what was filled in and why).
    @Published var startHeightNote: String?

    /// Taproot activation: no silent payment (they're taproot outputs) can be older.
    private static let taprootActivationMainnet = 709_632

    /// The earliest block the scanner can actually read: a pruned node's `pruneheight`
    /// (the lowest block it still has with undo data, which the scanner needs for each
    /// input's prevout). An unpruned node has everything, so it's the earliest block that
    /// could hold a silent payment: taproot activation on mainnet, 0 on test networks.
    func useEarliestAvailable() {
        earliestAvailableHeight(chain: network) { height, note in
            self.birthdayInput = "\(height)"
            self.startHeightNote = note
        }
    }

    /// The earliest block worth scanning and why (main queue), on `chain`'s node (nil: the
    /// selected network). Errors raise the alert.
    func earliestAvailableHeight(chain: String? = nil, _ completion: @escaping (Int, String) -> Void) {
        BitcoinRPC.shared.spCommand(method: "getblockchaininfo", params: [:], chain: chain) { result in
            DispatchQueue.main.async {
                guard case .success(let value) = result, let info = value as? [String: Any] else {
                    if case .failure(let error) = result {
                        self.alertMessage = "Unable to read the node's blockchain info: \(error.description)"
                    }
                    return
                }
                let chain = info["chain"] as? String ?? ""
                if info["pruned"] as? Bool == true, let pruneHeight = info["pruneheight"] as? Int {
                    completion(pruneHeight, "Your node is pruned: block \(pruneHeight.formatted()) is the oldest it still has. Payments received before it can't be found by scanning this node.")
                } else {
                    let earliest = chain == "main" ? Self.taprootActivationMainnet : 0
                    completion(earliest, chain == "main"
                        ? "Your node isn't pruned, so every block is available. Block \(earliest.formatted()) is when taproot activated; no silent payment can be older. Scanning from here takes a long time."
                        : "Your node isn't pruned, so every block is available.")
                }
            }
        }
    }

    // MARK: Check a transaction

    @Published var checkTxid = ""
    @Published var checkHeight = ""
    @Published var checkLines: [(ok: Bool?, text: String)] = []
    @Published var isChecking = false

    /// Runs the scanner's own BIP352 receiver math on one transaction with the SAVED keys
    /// and explains the result. Only public values are shown (public keys, output keys);
    /// the scan private key never leaves this process.
    func checkTransaction() {
        let txid = checkTxid.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard txid.count == 64, SPHex.decode(txid) != nil else {
            checkLines = [(false, "Enter a 64-character txid.")]
            return
        }
        guard let config = SPConfigStore.load() else {
            checkLines = [(false, "No saved keys to check with.")]
            return
        }
        // Checked on the keys' network, not the selected one.
        guard let chain = config.resolvedChain else {
            checkLines = [(false, "These keys are for a test network, but which one wasn't saved. Select that network in Bitcoin Core and try again.")]
            return
        }
        var lines: [(ok: Bool?, text: String)] = []

        // 1. The saved keys themselves.
        let keys: SPScanKeys
        do {
            keys = try SPScanKeys(scanPrivateKeyHex: config.scanPrivateKeyHex,
                                  spendPublicKeyHex: config.spendPublicKeyHex,
                                  extraLabels: [])
        } catch {
            checkLines = [(false, "The saved keys don't parse: \(error)")]
            return
        }
        let derivedScanPub = SPHex.encode(Data(keys.scanPriv.publicKey.dataRepresentation))
        lines.append((nil, "Saved address: \(config.address ?? "(not saved)")"))
        lines.append((nil, "Scan public key (from the saved scan private key): \(derivedScanPub)"))
        lines.append((nil, "Spend public key (saved): \(config.spendPublicKeyHex)"))
        if let address = config.address.flatMap({ SPKeyInput.address($0) }) {
            lines.append((address.scanPub == derivedScanPub,
                          address.scanPub == derivedScanPub ? "Scan key belongs to the saved address." : "Scan key does NOT belong to the saved address (address has \(address.scanPub))."))
            lines.append((address.spendPub == config.spendPublicKeyHex.lowercased(),
                          address.spendPub == config.spendPublicKeyHex.lowercased() ? "Spend key matches the saved address." : "Spend key does NOT match the saved address."))
            let expectedHrp = chain == "main" ? "sp" : "tsp"
            lines.append((address.hrp == expectedHrp, "Address network: \(address.hrp == "sp" ? "mainnet" : "test networks"), keys set up on: \(chain)."))
        }

        isChecking = true
        checkLines = lines + [(nil, "Fetching the transaction…")]

        func finish(_ more: [(ok: Bool?, text: String)]) {
            DispatchQueue.main.async {
                self.isChecking = false
                self.checkLines = lines + more
            }
        }

        // 2. The transaction with its prevouts (verbosity 2). A pruned node without a
        // tx index needs the block: from the height, if given.
        func fetch(blockhash: String?) {
            var params: [String: Any] = ["txid": txid, "verbosity": 2]
            if let blockhash = blockhash { params["blockhash"] = blockhash }
            BitcoinRPC.shared.spCommand(method: "getrawtransaction", params: params, chain: chain) { result in
                guard case .success(let value) = result, let tx = value as? [String: Any] else {
                    if case .failure(let e) = result {
                        finish([(false, "Couldn't fetch the transaction: \(e.description)" + (blockhash == nil ? " Enter its block height and try again." : ""))])
                    }
                    return
                }
                finish(Self.analyse(tx: tx, keys: keys))
            }
        }

        if let height = Int(checkHeight.trimmingCharacters(in: .whitespaces)) {
            BitcoinRPC.shared.spCommand(method: "getblockhash", params: ["height": height], chain: chain) { result in
                guard case .success(let value) = result, let hash = value as? String else {
                    finish([(false, "No block at height \(height).")])
                    return
                }
                fetch(blockhash: hash)
            }
        } else {
            fetch(blockhash: nil)
        }
    }

    private static func analyse(tx: [String: Any], keys: SPScanKeys) -> [(ok: Bool?, text: String)] {
        var lines: [(ok: Bool?, text: String)] = []
        guard let vins = tx["vin"] as? [[String: Any]], let vouts = tx["vout"] as? [[String: Any]] else {
            return [(false, "Unexpected transaction data.")]
        }
        if vins.contains(where: { $0["prevout"] == nil }) {
            return [(false, "The node returned no prevouts for this transaction (pruned below its block?).")]
        }
        let pubkeys = vins.compactMap { SPPrevout.extractEligiblePubkey(vin: $0) }
        let outpoints: [(txid: String, vout: UInt32)] = vins.compactMap { vin in
            guard let t = vin["txid"] as? String, let n = (vin["vout"] as? NSNumber)?.uint32Value else { return nil }
            return (t, n)
        }
        let taproot: [(vout: Int, xonly: String)] = vouts.enumerated().compactMap { idx, vout in
            guard let hex = (vout["scriptPubKey"] as? [String: Any])?["hex"] as? String, SPPrevout.isP2TR(hex) else { return nil }
            return ((vout["n"] as? NSNumber)?.intValue ?? idx, String(hex.lowercased().dropFirst(4)))
        }
        lines.append((!pubkeys.isEmpty, "Eligible inputs: \(pubkeys.count) of \(vins.count)" + (pubkeys.isEmpty ? " (none, so it can't be a silent payment)" : "")))
        lines.append((!taproot.isEmpty, "Taproot outputs: " + (taproot.isEmpty ? "none" : taproot.map { "#\($0.vout) \($0.xonly)" }.joined(separator: ", "))))
        guard !pubkeys.isEmpty, !taproot.isEmpty else { return lines }

        do {
            let expected = try SilentPaymentCrypto.expectedOutputs(keys: keys, inputPubkeysCompressed: pubkeys, inputs: outpoints)
            lines.append((nil, "Your saved keys expect (k = 0): \(expected.unlabeled)"))
            for label in expected.labeled {
                lines.append((nil, "…or with label m = \(label.m)\(label.m == 0 ? " (change)" : ""): \(label.xonly)"))
            }
            let matches = try SilentPaymentCrypto.scanTransaction(keys: keys, inputPubkeysCompressed: pubkeys, inputs: outpoints, taprootOutputs: taproot)
            if matches.isEmpty {
                lines.append((false, "No output matches your saved keys. The transaction was made for a different silent payment address (or different keys) than the one saved here."))
            } else {
                for m in matches {
                    lines.append((true, "Output #\(m.vout) is yours (k = \(m.k)\(m.label.map { ", label m = \($0.m)" } ?? "")). A rescan from its block will import it."))
                }
            }
        } catch {
            lines.append((false, "BIP352 math failed for this transaction: \(error)"))
        }
        return lines
    }

    /// Height offered by "Rescan from earliest", waiting for confirmation.
    @Published var pendingRescan: (height: Int, note: String)?

    /// First step: look up the earliest block, then ask to confirm (`pendingRescan`).
    func prepareRescanFromEarliest() {
        guard let config = savedConfig else { return }
        // The scanner's network, not the selected one.
        earliestAvailableHeight(chain: config.resolvedChain) { height, note in
            self.pendingRescan = (height, note)
        }
    }

    /// Confirmed: scan again from `height` with the saved keys (starting them if needed).
    func rescan(from height: Int) {
        guard let config = savedConfig else { return }
        if !SilentPaymentService.shared.isRunning {
            do {
                try SPConfigStore.start(config)
                savedConfig = SPConfigStore.load()   // now with its network recorded
            } catch {
                alertMessage = "Unable to start: \(error)"
                return
            }
        }
        SilentPaymentService.shared.rescan(fromHeight: height)
        isRunning = true
        scannedHeight = nil
        lastError = nil
    }

    func useCurrentTip() {
        let chain = network
        BitcoinRPC.shared.spCommand(method: "getblockcount", params: [:], chain: chain) { result in
            DispatchQueue.main.async {
                guard chain == self.network else { return }   // switched meanwhile
                if case .success(let value) = result, let height = value as? Int {
                    self.birthdayInput = "\(height)"
                }
            }
        }
    }

    // MARK: Start / stop

    /// Checks the wallet is a watch-only descriptor wallet, saves the keys and starts
    /// the background scanner.
    func start() {
        guard let scanKey = effectiveScanKey, let address = address, let birthday = Int(birthdayInput) else { return }
        var config = SPConfig(walletName: selectedWallet,
                              scanPrivateKeyHex: scanKey.priv,
                              scanPublicKeyHex: scanKey.pub,
                              spendPublicKeyHex: address.spendPub,
                              birthdayHeight: max(birthday, 0),
                              address: address.address)
        isBusy = true

        // The selected network's node, which must report that network; it's saved with the keys
        // and the scanner stays on it whatever is selected later.
        let selected = network
        BitcoinRPC.shared.spCommand(method: "getblockchaininfo", params: [:], chain: selected) { result in
            DispatchQueue.main.async {
                guard case .success(let value) = result,
                      let chain = (value as? [String: Any])?["chain"] as? String else {
                    self.isBusy = false
                    if case .failure(let error) = result {
                        self.alertMessage = "Unable to read the node's network: \(error.description)"
                    } else {
                        self.alertMessage = "Unable to read the node's network."
                    }
                    return
                }
                let info = value as? [String: Any] ?? [:]
                if info["pruned"] as? Bool == true, let pruneHeight = info["pruneheight"] as? Int, config.birthdayHeight < pruneHeight {
                    self.isBusy = false
                    self.alertMessage = "Your node is pruned: block \(pruneHeight.formatted()) is the oldest it still has, so it can't scan from \(config.birthdayHeight.formatted()). Use a start height of \(pruneHeight.formatted()) or later (Earliest available fills it in)."
                    return
                }
                guard chain == selected else {
                    self.isBusy = false
                    self.alertMessage = "The node on \(Self.networkName(selected))'s port reports \(chain). Check which node is running there."
                    return
                }
                guard (chain == "main") == (address.hrp == "sp") else {
                    self.isBusy = false
                    self.alertMessage = "That is a \(address.hrp == "sp" ? "mainnet" : "test network") address but the node is on \(chain)."
                    return
                }
                config.chain = chain
                self.checkWalletAndLaunch(config)
            }
        }
    }

    private func checkWalletAndLaunch(_ config: SPConfig) {
        BitcoinRPC.shared.spCommand(method: "getwalletinfo", params: [:], wallet: config.walletName, chain: config.chain) { result in
            DispatchQueue.main.async {
                self.isBusy = false
                switch result {
                case .failure(let error):
                    self.alertMessage = "Unable to check wallet \"\(config.walletName)\": \(error.description)"
                case .success(let value):
                    let info = value as? [String: Any] ?? [:]
                    guard info["private_keys_enabled"] as? Bool == false, info["descriptors"] as? Bool != false else {
                        self.alertMessage = "\"\(config.walletName)\" must be a watch-only descriptor wallet (private keys disabled), like the wallets Fully Noded creates on your node. Select your Fully Noded wallet."
                        return
                    }
                    self.launch(config)
                }
            }
        }
    }

    private func launch(_ config: SPConfig) {
        // A start height that differs from the saved one (or a different network) is meant to
        // take effect now: scan from it instead of resuming earlier progress.
        let fromBirthday = savedConfig.map { $0.birthdayHeight != config.birthdayHeight || $0.resolvedChain != config.chain } ?? true
        do {
            try SPConfigStore.start(config, fromBirthday: fromBirthday)
        } catch {
            alertMessage = "Unable to start: \(error)"
            return
        }
        guard SPConfigStore.save(config) else {
            alertMessage = "Scanning started, but the keys could not be saved, so it won't resume after a restart."
            isRunning = true
            return
        }
        savedConfig = config
        scanKeyInput = ""
        isRunning = true
        foundThisSession = 0
    }

    func resumeSaved() {
        guard let config = savedConfig else { return }
        do {
            try SPConfigStore.start(config)
            savedConfig = SPConfigStore.load()   // now with its network recorded
            isRunning = true
        } catch {
            alertMessage = "Unable to resume: \(error)"
        }
    }

    func stop() {
        SilentPaymentService.shared.stop()
        isRunning = false
    }

    /// Stops scanning and deletes the saved keys.
    func forget() {
        stop()
        SPConfigStore.remove()
        savedConfig = nil
        scannedHeight = nil
        tipHeight = nil
        // The form was prefilled from the saved setup: clear it too, or the keys still show.
        selectedWallet = ""
        scanKeyInput = ""
        addressInput = ""
        birthdayInput = ""
        startHeightNote = nil
        foundThisSession = 0
        lastError = nil
        checkLines = []
        pendingRescan = nil
    }
}

// MARK: - View

struct SilentPaymentsView: View {
    @StateObject private var model = SilentPaymentsModel.shared
    @Environment(\.openWindow) private var openWindow

    private enum Field: String, Identifiable {
        case scanKey, address
        var id: String { rawValue }
        var title: String { self == .scanKey ? "Scan the scan private key QR" : "Scan the silent payment address QR" }
    }

    @State private var cameraTarget: Field?
    @State private var imageTarget: Field?
    @State private var showImageImporter = false
    /// The image importer / camera was opened from "Import from Fully Noded" (a link, not a field).
    @State private var importingLink = false
    @State private var cameraForLink = false
    /// What the last "Import from Fully Noded" filled in.
    @State private var importNote: String?
    @State private var revealScanKey = false
    /// Address shown in the QR sheet (nil: closed).
    @State private var addressForQr: String?
    @State private var addressCopied = false
    @State private var confirmForget = false
    private let hasCamera = SPQRCamera.isAvailable

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                scannerCard
                networkCard
                walletCard
                scanKeyCard
                addressCard
                startHeightCard
                checkCard
            }
            .padding(20)
            .frame(maxWidth: 760, alignment: .leading)
            // Quieter than the rest of the app: neutral cards and buttons, so green only
            // marks the main action and live status.
            .groupBoxStyle(SPQuietGroupBoxStyle())
            .buttonStyle(SPQuietButtonStyle())
        }
        .frame(minWidth: 480, idealWidth: 620, minHeight: 560)
        .onAppear { model.onAppear() }
        // Saved (Start / Save & restart) or forgotten: the import note no longer applies.
        .onChange(of: model.savedConfig) { _, _ in importNote = nil }
        .sheet(item: $cameraTarget) { target in
            SPQRScannerSheet(title: target.title) { code in
                cameraTarget = nil
                if let code = code { apply(code, to: target) }
            }
        }
        .sheet(isPresented: Binding(get: { addressForQr != nil },
                                    set: { if !$0 { addressForQr = nil } })) {
            SPAddressQRSheet(address: addressForQr ?? "") { addressForQr = nil }
        }
        .sheet(isPresented: $cameraForLink) {
            SPQRScannerSheet(title: "Scan the Fully Noded Server QR") { code in
                cameraForLink = false
                if let code = code { importLink(code) }
            }
        }
        .fileImporter(isPresented: $showImageImporter, allowedContentTypes: [.image]) { result in
            let forLink = importingLink
            let target = imageTarget
            importingLink = false
            imageTarget = nil
            guard forLink || target != nil else { return }
            switch result {
            case .success(let url):
                if let code = SPQRCamera.decode(imageAt: url) {
                    if let target = target { apply(code, to: target) } else { importLink(code) }
                } else {
                    model.alertMessage = "No QR code found in that image."
                }
            case .failure(let error):
                model.alertMessage = error.localizedDescription
            }
        }
        .alert(model.alertMessage ?? "", isPresented: Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        }
        .alert("Rescan from block \(model.pendingRescan?.height.formatted() ?? "")?",
               isPresented: Binding(get: { model.pendingRescan != nil },
                                    set: { if !$0 { model.pendingRescan = nil } })) {
            Button("Rescan") {
                if let height = model.pendingRescan?.height { model.rescan(from: height) }
                model.pendingRescan = nil
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) { model.pendingRescan = nil }
        } message: {
            Text((model.pendingRescan.map { $0.note.isEmpty ? "" : $0.note + "\n\n" } ?? "") + "Every block from there to the tip is scanned again with your saved keys, and anything found is imported into your wallet (payments already imported are unaffected). This can take a long time; scanning continues in the background.")
        }
        .alert("Stop scanning and delete the saved keys?", isPresented: $confirmForget) {
            Button("Forget keys", role: .destructive) {
                model.forget()
                importNote = nil
                revealScanKey = false
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Outputs already imported stay in the wallet. You can import the keys again at any time.")
        }
    }

    // MARK: Layout

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "eye.slash")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Cypher.accent)
                Text("Silent Payments")
                    .font(Cypher.mono(20, weight: .bold))
            }
            Text("Fully Noded Server finds silent payments (BIP352) sent to you and imports them into your Fully Noded wallet on this node. It only needs your scan private key and your silent payment address: it can see payments, never spend them. In Fully Noded, open the wallet (Silent payments → FN-SERVER LINK) or the signer (scan private key → \"Fully Noded Server QR\"), then use Import from Fully Noded below to fill everything in.")
                .font(Cypher.mono(12))
                .foregroundStyle(Cypher.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A titled card (the page's GroupBox style draws the "> TITLE" caption and border) with
    /// an optional explanation under its content.
    /// `required`: the card's field still needs filling in for setup; it gets an amber border
    /// and a "· required" tag so the next thing to do stands out.
    private func card<Content: View>(_ title: String,
                                     footer: String? = nil,
                                     required: Bool = false,
                                     @ViewBuilder content: () -> Content) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                content()
                if let footer = footer {
                    Text(footer)
                        .font(Cypher.mono(11))
                        .foregroundStyle(Cypher.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } label: {
            HStack(spacing: 0) {
                Text(title)
                if required {
                    Text(" · required")
                        .foregroundStyle(Cypher.amber)
                }
            }
        }
        .overlay(Rectangle().stroke(Cypher.amber.opacity(required ? 0.7 : 0), lineWidth: 1))
    }

    /// What's still needed before Start, and whether the setup is saved.
    @ViewBuilder
    private var setupStatus: some View {
        if model.savedConfig != nil, !model.hasUnsavedChanges {
            Label {
                Text("Setup saved. Your keys are stored encrypted in the Keychain, and scanning resumes automatically whenever Fully Noded Server launches.")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "checkmark.seal.fill")
            }
            .font(Cypher.mono(11))
            .foregroundStyle(Cypher.accent)
        } else {
            VStack(alignment: .leading, spacing: 5) {
                Text(model.savedConfig == nil ? "To start scanning:" : "Unsaved changes. To apply them:")
                    .font(Cypher.mono(11, weight: .semibold))
                    .foregroundStyle(model.savedConfig == nil ? Cypher.text : Cypher.amber)
                ForEach(model.setupSteps) { step in
                    Label(step.text, systemImage: step.done ? "checkmark.circle.fill" : "circle")
                        .font(Cypher.mono(11))
                        .foregroundStyle(step.done ? Cypher.accent : (model.setupInProgress ? Cypher.amber : Cypher.text))
                }
                Text(model.savedConfig == nil
                     ? "Then press Start scanning. Nothing is saved until you do."
                     : "Then press Save & restart. Until you do, the saved setup keeps being used.")
                    .font(Cypher.mono(11))
                    .foregroundStyle(Cypher.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Cards

    /// Scanner state first: on this page it is what you come back to look at.
    private var scannerCard: some View {
        card("Scanner",
             footer: "Scanning keeps running in the background while Fully Noded Server is open, and resumes automatically when it launches.") {
            HStack {
                SPScanActivityView(startHeight: model.savedConfig?.birthdayHeight)
                if model.isBusy { ProgressView().controlSize(.small) }
            }
            if let saved = model.savedConfig {
                // Wallet names are long hashes: one line, middle truncated, full name on hover.
                Text("\(saved.resolvedChain.map { SilentPaymentsModel.networkName($0) } ?? "?") · wallet \(saved.walletName)")
                    .font(Cypher.mono(11))
                    .foregroundStyle(Cypher.dim)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(saved.walletName)
            }

            if model.foundThisSession > 0 {
                Label("\(model.foundThisSession) payment(s) found and imported this session", systemImage: "checkmark.seal")
                    .foregroundStyle(Cypher.accent)
            }

            importRow

            setupStatus

            HStack {
                if model.isRunning {
                    Button("Stop") { model.stop() }
                        .help("Stop scanning")
                } else if model.savedConfig != nil {
                    Button("Resume") { model.resumeSaved() }
                        .help("Resume scanning with the saved keys")
                }
                if model.savedConfig != nil { importMenu }
                Spacer()
                if model.savedConfig != nil {
                    Button("Forget keys", role: .destructive) { confirmForget = true }
                    Button {
                        model.prepareRescanFromEarliest()
                    } label: {
                        Label("Rescan", systemImage: "arrow.counterclockwise")
                    }
                    .help("Rescan from the earliest block your node has, e.g. to find payments received before your start height")
                }
                Button {
                    openWindow(id: "SPHistory")
                } label: {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                Button(model.savedConfig == nil ? "Start scanning" : "Save & restart") {
                    model.start()
                }
                .buttonStyle(.cypherProminent)
                .lineLimit(1)
                .fixedSize()
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canStart)
            }
        }
    }

    /// One place to bring in a Fully Noded export link (fnsp://…): it fills the address, scan
    /// key and (from a wallet export) the wallet. Nothing starts until Start / Save & restart.
    /// Kept quiet: a single line of small text links before setup, and once keys are saved just
    /// an "Import…" menu in the button row (`importMenu`), since it's rarely needed again.
    @ViewBuilder
    private var importRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            if model.savedConfig == nil {
                HStack(spacing: 12) {
                    Text("Import from Fully Noded:")
                    importLinkButton("Paste link", help: "Paste a Fully Noded Server link (fnsp://…), e.g. copied on your iPhone with Universal Clipboard", action: pasteLink)
                    importLinkButton("QR image…", help: "Pick a screenshot or saved image of the Fully Noded Server QR", action: chooseLinkImage)
                    if hasCamera {
                        importLinkButton("Scan QR", help: "Scan the Fully Noded Server QR with the camera") { cameraForLink = true }
                    }
                }
                .font(Cypher.mono(11))
                .foregroundStyle(Cypher.dim)
            }
            if let note = importNote {
                Label(note, systemImage: "checkmark.circle")
                    .font(Cypher.mono(11))
                    .foregroundStyle(Cypher.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Plain underlined text, not a bordered button.
    private func importLinkButton(_ title: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).underline()
        }
        .buttonStyle(.plain)
        .foregroundStyle(Cypher.text)
        .help(help)
    }

    /// With keys saved: importing again (replacing them) lives behind a small menu.
    private var importMenu: some View {
        Menu {
            Button("Paste link", action: pasteLink)
            Button("QR image…", action: chooseLinkImage)
            if hasCamera {
                Button("Scan QR") { cameraForLink = true }
            }
        } label: {
            Text("Import…")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .font(Cypher.mono(11))
        .foregroundStyle(Cypher.dim)
        .tint(Cypher.dim)
        .help("Replace the saved keys with a Fully Noded Server link")
    }

    private func pasteLink() {
        if let text = NSPasteboard.general.string(forType: .string) {
            importLink(text)
        } else {
            model.alertMessage = "The clipboard is empty. In Fully Noded, tap Copy Text on the Fully Noded Server link first."
        }
    }

    private func chooseLinkImage() {
        importingLink = true
        showImageImporter = true
    }

    private func importLink(_ text: String) {
        importNote = nil
        guard model.applyImportLink(text) else {
            model.alertMessage = "That isn't a Fully Noded Server link. In Fully Noded, open the wallet's Silent payments section and tap FN-SERVER LINK, then copy or save its QR."
            return
        }
        guard model.scanKey != nil, model.address != nil else { return }   // applyImportLink alerted
        let wallet = SPKeyInput.importLink(text)?.wallet
        importNote = "Imported the address and scan key" + (wallet.map { " and selected wallet \(Self.shortWallet($0))" } ?? "")
            + " (not saved yet)." + (model.canStart ? "" : " Complete the steps below.")
    }

    private static func shortWallet(_ name: String) -> String {
        name.count > 28 ? "\(name.prefix(18))…\(name.suffix(6))" : name
    }

    private var networkCard: some View {
        card("Network",
             footer: "The node this setup uses: its wallets, start height and the blocks scanned. Separate from the Bitcoin Core network picker, and saved with the keys.") {
            Picker("Network", selection: Binding(get: { model.network }, set: { model.selectNetwork($0) })) {
                ForEach(SilentPaymentsModel.networks, id: \.self) { chain in
                    Text(SilentPaymentsModel.networkName(chain)).tag(chain)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if let saved = model.savedConfig, let savedChain = saved.resolvedChain, savedChain != model.network {
                Label("Your saved setup scans \(SilentPaymentsModel.networkName(savedChain)). Save & restart to move it to \(SilentPaymentsModel.networkName(model.network)).",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Cypher.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var walletCard: some View {
        card("Wallet",
             footer: "Found outputs are imported into this wallet as watch-only. Pick the Fully Noded wallet you'll spend from (Fully Noded wallets are watch-only descriptor wallets on your node, with their own change addresses).",
             required: model.needsInput(.wallet)) {
            HStack {
                Picker("Wallet", selection: $model.selectedWallet) {
                    Text("Select a wallet…").tag("")
                    ForEach(model.wallets, id: \.self) { wallet in
                        Text(wallet).tag(wallet)
                    }
                }
                .labelsHidden()
                Button {
                    model.refreshWallets()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh the list of loaded wallets")
            }
        }
    }

    private var scanKeyCard: some View {
        card("Scan private key (b_scan)",
             footer: "Lets this server detect payments to you. It can't spend, but anyone who has it can see every silent payment you receive. Stored encrypted in the Keychain.",
             required: model.needsInput(.scanKey)) {
            HStack {
                Group {
                    if revealScanKey {
                        TextField("64 hex characters", text: $model.scanKeyInput)
                    } else {
                        SecureField("64 hex characters", text: $model.scanKeyInput)
                    }
                }
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.roundedBorder)

                Button {
                    revealScanKey.toggle()
                } label: {
                    Image(systemName: revealScanKey ? "eye.slash" : "eye")
                }
                .help(revealScanKey ? "Hide" : "Show")
            }
            inputButtons(for: .scanKey)
            statusLine(model.scanKeyStatus)
            if model.scanKeyInput.isEmpty, let saved = model.savedConfig {
                Label("Using your saved scan key (scan public key \(SilentPaymentsModel.short(saved.scanPublicKeyHex))). Enter one only to replace it.",
                      systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Cypher.accent)
            }
        }
    }

    private var addressCard: some View {
        card("Silent payment address",
             footer: "Your spend public key is read from the address and used to recognise your outputs; the scan key is checked against it.",
             required: model.needsInput(.address)) {
            TextField("sp1… / tsp1…", text: $model.addressInput)
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.roundedBorder)
            inputButtons(for: .address)
            statusLine(model.addressStatus)
            if let shareable = model.shareableAddress {
                HStack {
                    Text("Share:")
                        .font(Cypher.mono(11))
                        .foregroundStyle(Cypher.dim)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(shareable, forType: .string)
                        addressCopied = true
                    } label: {
                        Label(addressCopied ? "Copied" : "Copy address", systemImage: addressCopied ? "checkmark" : "doc.on.doc")
                    }
                    .help("Copy your silent payment address")
                    Button {
                        addressForQr = shareable
                    } label: {
                        Label("Show QR", systemImage: "qrcode")
                    }
                    .help("Show your silent payment address as a QR code, to copy or save")
                    Spacer()
                }
                .onChange(of: shareable) { _, _ in addressCopied = false }
            }
        }
    }

    private var startHeightCard: some View {
        card("Start height",
             footer: "The first block that could contain a payment to you, e.g. when you first shared your address. Earlier means a longer initial scan. It's only used the first time these keys are scanned: changing it later doesn't go back, so use Rescan here to scan again from the height above.",
             required: model.needsInput(.startHeight)) {
            HStack {
                TextField("Block height", text: $model.birthdayInput)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                Button("Use current height") {
                    model.startHeightNote = nil
                    model.useCurrentTip()
                }
                Button {
                    model.useEarliestAvailable()
                } label: {
                    Label("Earliest available", systemImage: "arrow.down.to.line")
                }
                .help("Fill in the oldest block your node can scan (its prune height, if pruned)")
                Button {
                    if let height = Int(model.birthdayInput.trimmingCharacters(in: .whitespaces)) {
                        model.pendingRescan = (height, "")
                    }
                } label: {
                    Label("Rescan", systemImage: "arrow.counterclockwise")
                }
                .disabled(model.savedConfig == nil || Int(model.birthdayInput.trimmingCharacters(in: .whitespaces)) == nil)
                .help("Rescan from this block now, with your saved keys")
            }
            if let note = model.startHeightNote {
                Label(note, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(Cypher.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var checkCard: some View {
        card("Check a transaction",
             footer: "Runs the scanner's silent payment math on one transaction with your saved keys, to see whether it pays you and why not. Only public keys are shown; your scan private key stays in FN-Server.") {
            HStack {
                TextField("txid", text: $model.checkTxid)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                TextField("block height (optional)", text: $model.checkHeight)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                Button("Check") { model.checkTransaction() }
                    .disabled(model.isChecking || model.savedConfig == nil)
            }
            ForEach(Array(model.checkLines.enumerated()), id: \.offset) { _, line in
                Label {
                    Text(line.text)
                        .font(Cypher.mono(11))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: line.ok == nil ? "circle.fill" : (line.ok! ? "checkmark.circle.fill" : "xmark.octagon.fill"))
                        .font(.system(size: line.ok == nil ? 5 : 11))
                        .foregroundStyle(line.ok == nil ? Cypher.dim : (line.ok! ? Cypher.accent : Cypher.danger))
                }
            }
        }
    }

    // MARK: Helpers

    private func inputButtons(for field: Field) -> some View {
        HStack {
            if hasCamera {
                Button {
                    cameraTarget = field
                } label: {
                    Label("Scan QR", systemImage: "qrcode.viewfinder")
                }
            }
            Button {
                imageTarget = field
                showImageImporter = true
            } label: {
                Label("QR image…", systemImage: "photo")
            }
            Button {
                if let text = NSPasteboard.general.string(forType: .string) {
                    apply(text, to: field)
                }
            } label: {
                Label("Paste", systemImage: "doc.on.clipboard")
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func statusLine(_ status: (ok: Bool, text: String)?) -> some View {
        if let status = status {
            Label(status.text, systemImage: status.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .font(.caption)
                .foregroundStyle(status.ok ? Cypher.accent : Cypher.danger)
        }
    }

    private func apply(_ text: String, to field: Field) {
        // A Fully Noded export link fills both fields, whichever one it was entered into.
        if model.applyImportLink(text) { return }
        let cleaned = SPKeyInput.clean(text)
        switch field {
        case .scanKey: model.scanKeyInput = cleaned
        case .address: model.addressInput = cleaned
        }
    }
}

// MARK: - Sidebar status icon

/// The state icon of the "Silent Payments" row in the main sidebar, like the checkmark /
/// cross the other services show: green check when the scanner is up to date, a spinner while
/// it catches up, amber when keys are saved but it isn't running (or is retrying), dim when no
/// keys have been imported. Refreshes itself every few seconds.
struct SPSidebarStatusIcon: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 3)) { _ in
            icon
        }
    }

    @ViewBuilder
    private var icon: some View {
        if !SPConfigStore.isConfigured {
            Image(systemName: "xmark")
                .foregroundStyle(Cypher.dim)
                .help("No silent payment keys imported")
        } else {
            let status = SilentPaymentService.shared.status()
            if !status.isRunning {
                Image(systemName: "xmark")
                    .foregroundStyle(Cypher.amber)
                    .help("Not scanning")
            } else if let error = status.lastError {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Cypher.amber)
                    .help(error)
            } else if status.isRescanning {
                SPPulseIcon(systemName: "arrow.triangle.2.circlepath", color: Cypher.amber, pulsing: true, period: 1.2, size: 11)
                    .help("Rescanning the wallet to add the payments found")
            } else if let tip = status.tipHeight, (status.scannedHeight ?? 0) >= tip {
                Image(systemName: "checkmark")
                    .foregroundStyle(Cypher.accent)
                    .help("Up to date at block \(tip.formatted())")
            } else {
                SPSidebarScanRing(status: status)
            }
        }
    }
}

/// Sidebar badge while the scanner catches up: a ring filling with the share of blocks
/// scanned since this run began, around a pulsing magnifying glass.
struct SPSidebarScanRing: View {
    let status: SilentPaymentService.Status

    /// nil until the tip is known (the ring then just pulses).
    private var fraction: Double? {
        guard let tip = status.tipHeight else { return nil }
        let first = status.startHeight ?? tip
        let scanned = (status.scannedHeight ?? first - 1) + 1
        let total = max(tip + 1 - first, 1)
        return min(max(Double(scanned - first) / Double(total), 0), 1)
    }

    private var helpText: String {
        guard let tip = status.tipHeight else { return "Connecting to your node…" }
        let next = (status.scannedHeight ?? (status.startHeight ?? tip) - 1) + 1
        let percent = fraction.map { " (\(Int($0 * 100))%)" } ?? ""
        return "Scanning block \(next.formatted()) of \(tip.formatted())\(percent)"
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Cypher.accent.opacity(0.2), lineWidth: 2)
            Circle()
                .trim(from: 0, to: fraction ?? 0)
                .stroke(Cypher.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
            SPPulseIcon(systemName: "magnifyingglass", color: Cypher.accent, pulsing: true, period: 1.6, size: 7)
        }
        .frame(width: 16, height: 16)
        .help(helpText)
    }
}

// MARK: - Scan activity

/// Live view of what the scanner is doing, refreshed every second from the service:
/// catching up (animated bar, blocks to go, speed and time left), rescanning the wallet,
/// watching for new blocks, retrying after an error, or stopped.
struct SPScanActivityView: View {
    /// The first block scanned for these keys: progress is measured from here, not genesis.
    let startHeight: Int?

    @StateObject private var rate = SPScanRate()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let status = SilentPaymentService.shared.status()
            content(status)
                .onChange(of: context.date) { _, date in
                    rate.add(height: status.scannedHeight, at: date)
                }
        }
    }

    private enum Phase {
        case stopped, starting, retrying(String), catchingUp(scanned: Int, tip: Int), rescanning(from: Int), pendingRescan(from: Int), watching(tip: Int)
    }

    private func phase(_ status: SilentPaymentService.Status) -> Phase {
        guard status.isRunning else { return .stopped }
        if let error = status.lastError { return .retrying(error) }
        guard let tip = status.tipHeight else { return .starting }
        let scanned = status.scannedHeight ?? max((startHeight ?? tip) - 1, 0)
        if scanned < tip { return .catchingUp(scanned: scanned, tip: tip) }
        if status.isRescanning, let from = status.pendingRescanFrom { return .rescanning(from: from) }
        if let from = status.pendingRescanFrom { return .pendingRescan(from: from) }
        return .watching(tip: tip)
    }

    @ViewBuilder
    private func content(_ status: SilentPaymentService.Status) -> some View {
        switch phase(status) {
        case .stopped:
            header(icon: "pause.circle", color: Cypher.dim, title: "Not scanning",
                   detail: SPConfigStore.isConfigured ? "Press Resume to continue." : "Use Import from Fully Noded below, or enter your keys, to start.")
        case .starting:
            VStack(alignment: .leading, spacing: 8) {
                header(icon: "antenna.radiowaves.left.and.right", color: Cypher.amber, title: "Starting…",
                       detail: "Connecting to your node.", pulsing: true)
                SPScanBar(fraction: nil, color: Cypher.amber)
            }
        case .retrying(let error):
            header(icon: "exclamationmark.triangle", color: Cypher.amber, title: "Retrying",
                   detail: error)
        case .catchingUp(let scanned, let tip):
            let first = min(startHeight ?? scanned, scanned)
            let total = max(tip - first, 1)
            let done = max(scanned - first, 0)
            let remaining = tip - scanned
            VStack(alignment: .leading, spacing: 8) {
                header(icon: "magnifyingglass", color: Cypher.accent,
                       title: "Scanning block \((scanned + 1).formatted()) of \(tip.formatted())",
                       detail: catchUpDetail(remaining: remaining), pulsing: true)
                SPScanBar(fraction: Double(done) / Double(total), color: Cypher.accent)
                Text("\(Int(Double(done) / Double(total) * 100))% · \(remaining.formatted()) block\(remaining == 1 ? "" : "s") to go")
                    .font(Cypher.mono(11))
                    .foregroundStyle(Cypher.dim)
            }
        case .rescanning(let from):
            VStack(alignment: .leading, spacing: 8) {
                header(icon: "arrow.triangle.2.circlepath", color: Cypher.amber,
                       title: "Rescanning wallet from block \(from.formatted())",
                       detail: "Bitcoin Core is adding the payments found to your wallet's history. Large ranges can take a while.",
                       pulsing: true)
                SPScanBar(fraction: nil, color: Cypher.amber)
            }
        case .pendingRescan(let from):
            header(icon: "clock", color: Cypher.amber, title: "Wallet rescan queued from block \(from.formatted())",
                   detail: "Runs as soon as the scan has caught up.")
        case .watching(let tip):
            header(icon: "dot.radiowaves.left.and.right", color: Cypher.accent,
                   title: "Up to date at block \(tip.formatted())",
                   detail: "Watching for new blocks.", pulsing: true, slow: true)
        }
    }

    private func catchUpDetail(remaining: Int) -> String {
        guard let perSecond = rate.blocksPerSecond, perSecond > 0 else { return "Measuring speed…" }
        let seconds = Double(remaining) / perSecond
        let speed = perSecond >= 1 ? String(format: "%.1f blocks/s", perSecond) : String(format: "%.0f s/block", 1 / perSecond)
        return "\(speed) · about \(Self.duration(seconds)) left"
    }

    private static func duration(_ seconds: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: max(seconds, 1)) ?? "–"
    }

    private func header(icon: String, color: Color, title: String, detail: String,
                        pulsing: Bool = false, slow: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            SPPulseIcon(systemName: icon, color: color, pulsing: pulsing, period: slow ? 2.4 : 1.2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Cypher.mono(13, weight: .semibold))
                Text(detail)
                    .font(Cypher.mono(11))
                    .foregroundStyle(Cypher.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Recent (time, height) samples → scan speed in blocks per second.
final class SPScanRate: ObservableObject {
    private var samples: [(date: Date, height: Int)] = []

    func add(height: Int?, at date: Date) {
        guard let height = height else { return }
        // A jump back (restart, reorg) starts the measurement over.
        if let last = samples.last, height < last.height { samples.removeAll() }
        samples.append((date, height))
        // Keep about the last 30 seconds.
        samples.removeAll { date.timeIntervalSince($0.date) > 30 }
    }

    var blocksPerSecond: Double? {
        guard let first = samples.first, let last = samples.last,
              last.date.timeIntervalSince(first.date) >= 3, last.height > first.height else { return nil }
        return Double(last.height - first.height) / last.date.timeIntervalSince(first.date)
    }
}

/// Status icon that gently pulses while work is going on.
struct SPPulseIcon: View {
    let systemName: String
    let color: Color
    let pulsing: Bool
    let period: Double
    var size: CGFloat = 16

    var body: some View {
        TimelineView(.animation(paused: !pulsing)) { context in
            let phase = pulsing ? (sin(context.date.timeIntervalSinceReferenceDate * 2 * .pi / period) + 1) / 2 : 1
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(color)
                .opacity(0.45 + 0.55 * phase)
                .shadow(color: color.opacity(0.6 * phase), radius: size * 0.375)
                .frame(width: size * 1.375, height: size * 1.375)
        }
    }
}

/// Thin bar: filled to `fraction`, with a light sweep running across it to show activity.
/// `fraction` nil: indeterminate (just the sweep).
struct SPScanBar: View {
    let fraction: Double?
    let color: Color

    var body: some View {
        TimelineView(.animation) { context in
            GeometryReader { geometry in
                let width = geometry.size.width
                let filled = width * CGFloat(min(max(fraction ?? 1, 0), 1))
                let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                let sweepWidth = max(width * 0.18, 40)
                ZStack(alignment: .leading) {
                    Rectangle().fill(color.opacity(0.12))
                    Rectangle().fill(color.opacity(fraction == nil ? 0.25 : 0.8)).frame(width: filled)
                    LinearGradient(colors: [color.opacity(0), color.opacity(0.9), color.opacity(0)],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: sweepWidth)
                        .offset(x: -sweepWidth + (filled + sweepWidth) * CGFloat(t))
                }
                .clipped()
                .overlay(Rectangle().stroke(color.opacity(0.45), lineWidth: 1))
            }
        }
        .frame(height: 8)
    }
}

// MARK: - Quiet styles (Silent Payments page)

/// Card with a faint neutral border and a dim "> TITLE" caption.
struct SPQuietGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                Text("> ")
                configuration.label
            }
            .font(Cypher.mono(11, weight: .bold))
            .foregroundStyle(Cypher.dim)
            .textCase(.uppercase)

            configuration.content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Cypher.panel)
        .overlay(Rectangle().stroke(Color.white.opacity(0.09), lineWidth: 1))
    }
}

/// Secondary button: pale text on the panel with a faint border (the main action keeps
/// `.cypherProminent`).
struct SPQuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.label
        }
        .font(Cypher.mono(12, weight: .semibold))
        .foregroundStyle(Cypher.text)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Rectangle().fill(configuration.isPressed ? Color.white.opacity(0.08) : Color.white.opacity(0.03)))
        .overlay(Rectangle().stroke(Color.white.opacity(0.14), lineWidth: 1))
        .opacity(isEnabled ? 1 : 0.4)
        .contentShape(Rectangle())
    }
}
