import Foundation
import CoreNFC

@objc public class NFCReader: NSObject, NFCTagReaderSessionDelegate {
    private var readerSession: NFCTagReaderSession?

    public var onUIDReceived: ((String, String) -> Void)?
    public var onNDEFMessageReceived: (([NFCNDEFMessage], [String: Any]?) -> Void)?
    public var onError: ((Error) -> Void)?

    @objc public func startScanning() {
        print("NFCReader startScanning called")

        guard NFCTagReaderSession.readingAvailable else {
            print("NFC scanning not supported on this device")
            return
        }
        readerSession = NFCTagReaderSession(pollingOption: [.iso14443, .iso15693, .iso18092], delegate: self, queue: nil)
        readerSession?.alertMessage = "Hold your iPhone near the NFC tag."
        readerSession?.begin()
    }

    @objc public func cancelScanning() {
        if let session = readerSession {
            session.invalidate()
        }
        readerSession = nil
    }

    // NFCTagReaderSessionDelegate methods
    public func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
      print("NFC session active")
    }

    public func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        print("NFC reader session error: \(error.localizedDescription)")
        onError?(error)
        readerSession = nil
    }

    public func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let tag = tags.first else { return }

        if tags.count > 1 {
            let retryInterval = DispatchTimeInterval.milliseconds(500)
            session.alertMessage = "More than one tag detected. Please remove extra tags and try again."
            DispatchQueue.global().asyncAfter(deadline: .now() + retryInterval) {
                session.restartPolling()
            }
            return
        }

        session.connect(to: tag) { (error: Error?) in
            if let error = error {
                session.invalidate(errorMessage: "Unable to connect to tag.")
                self.onError?(error)
                return
            }

            // Extract tag information
            let tagInfo = self.extractTagInfo(from: tag)
            let uid = (tagInfo["uid"] as? String) ?? ""
            let type = (tagInfo["type"] as? String) ?? "Unknown"

            self.tryReadNDEF(tag: tag, session: session, tagInfo: tagInfo) { success in
              if !success {
                // NDEF non rilevato ritorno UID
                session.alertMessage = "Tag detected"
                session.invalidate()
                self.onUIDReceived?(uid, type)
              }
            }

        }
    }

    private func extractTagInfo(from tag: NFCTag) -> [String: Any] {
        var tagInfo: [String: Any] = [:]
        var uid = ""
        var type = "Unknown"

        switch tag {
        case .iso7816(let t):
            uid = t.identifier.map { String(format: "%02X", $0) }.joined()
            type = "ISO7816"
        case .miFare(let t):
            uid = t.identifier.map { String(format: "%02X", $0) }.joined()
            type = "MiFare"
        case .feliCa(let t):
            uid = t.currentIDm.map { String(format: "%02X", $0) }.joined()
            type = "FeliCa"
        case .iso15693(let t):
            uid = t.identifier.map { String(format: "%02X", $0) }.joined()
            type = "ISO15693"
        @unknown default:
            type = "Unknown"
        }

        tagInfo["uid"] = uid
        tagInfo["type"] = type
        return tagInfo
    }

    private func tryReadNDEF(tag: NFCTag, session: NFCTagReaderSession, tagInfo: [String: Any], completion: @escaping (Bool) -> Void) {
        // Gestione universale NDEF
        switch tag {
        case .miFare(let miFareTag):
            readNDEF(from: miFareTag, session: session, tagInfo: tagInfo, completion: completion)
        case .iso15693(let iso15693Tag):
            readNDEF(from: iso15693Tag, session: session, tagInfo: tagInfo, completion: completion)
        case .feliCa(let feliCaTag):
            readNDEF(from: feliCaTag, session: session, tagInfo: tagInfo, completion: completion)
        default:
            completion(false)
        }
    }

    private func readNDEF(from tag: NFCNDEFTag, session: NFCTagReaderSession, tagInfo: [String: Any], completion: @escaping (Bool) -> Void) {
        tag.queryNDEFStatus { status, capacity, error in
            if let error = error {
                print("Error querying NDEF status: \(error.localizedDescription)")
                completion(false)
                return
            }

            guard status != .notSupported else {
                completion(false)
                return
            }

            tag.readNDEF { message, error in
                if let error = error {
                    print("Error reading NDEF: \(error.localizedDescription)")
                    completion(false)
                    return
                }

                if let message = message {
                    var info = tagInfo
                    info["capacity"] = capacity
                    session.alertMessage = "NDEF message found."
                    session.invalidate()
                    self.onNDEFMessageReceived?([message], info)
                    completion(true)
                } else {
                    completion(false)
                }
            }
        }
    }
}
